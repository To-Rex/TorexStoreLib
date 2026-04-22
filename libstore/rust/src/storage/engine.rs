use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use parking_lot::RwLock;

use crate::error::{StoreError, StoreResult};
use crate::storage::format::{Record, RecordHeader, RecordType};

/// Append-only storage engine
///
/// All records are written sequentially to a log file.
/// The engine supports reading records by offset and scanning all records.
pub struct StorageEngine {
    /// Base directory for database files
    base_dir: PathBuf,
    /// Active data file handle (append-only)
    active_file: RwLock<File>,
    /// Current active file path
    active_file_path: PathBuf,
    /// Current write offset
    write_offset: RwLock<u64>,
}

impl StorageEngine {
    /// Create or open a storage engine at the given directory
    pub fn open(base_dir: &Path) -> StoreResult<Self> {
        fs::create_dir_all(base_dir)?;

        let active_file_path = base_dir.join("data.torex");
        let file_exists = active_file_path.exists();

        let active_file = OpenOptions::new()
            .create(true)
            .append(true)
            .read(true)
            .open(&active_file_path)?;

        let write_offset = if file_exists {
            active_file.metadata()?.len()
        } else {
            0
        };

        Ok(Self {
            base_dir: base_dir.to_path_buf(),
            active_file: RwLock::new(active_file),
            active_file_path,
            write_offset: RwLock::new(write_offset),
        })
    }

    /// Append a record to the active file and return its offset
    pub fn append(&self, record: &Record) -> StoreResult<u64> {
        let mut file = self.active_file.write();
        let mut offset = self.write_offset.write();

        let bytes = record.to_bytes();
        file.write_all(&bytes)?;
        file.flush()?;

        let record_offset = *offset;
        *offset += bytes.len() as u64;

        Ok(record_offset)
    }

    /// Read a record at the given offset
    pub fn read_at(&self, offset: u64) -> StoreResult<Record> {
        let mut file = self.active_file.write();
        file.seek(SeekFrom::Start(offset))?;

        // Read header first
        let mut header_buf = [0u8; RecordHeader::SIZE];
        file.read_exact(&mut header_buf)?;

        // Parse header to know how much more data to read
        let header = Self::parse_header(&header_buf)?;

        // Read remaining data (collection + id + payload)
        let remaining_len = header.collection_len as usize
            + header.id_len as usize
            + header.data_len as usize;
        let mut remaining = vec![0u8; remaining_len];
        file.read_exact(&mut remaining)?;

        // Combine header + remaining for full record parsing
        let mut full_buf = header_buf.to_vec();
        full_buf.extend_from_slice(&remaining);

        Record::from_bytes(&full_buf)
    }

    /// Scan all records in the active file
    pub fn scan_all(&self) -> StoreResult<Vec<(u64, Record)>> {
        let mut file = self.active_file.write();
        file.seek(SeekFrom::Start(0))?;

        let file_size = file.metadata()?.len();
        let mut records = Vec::new();
        let mut offset = 0u64;

        while offset < file_size {
            // Read header
            let mut header_buf = [0u8; RecordHeader::SIZE];
            match file.read_exact(&mut header_buf) {
                Ok(()) => {}
                Err(_) => break, // EOF or partial record
            }

            let header = match Self::parse_header(&header_buf) {
                Ok(h) => h,
                Err(_) => break,
            };

            let remaining_len = header.collection_len as usize
                + header.id_len as usize
                + header.data_len as usize;
            let mut remaining = vec![0u8; remaining_len];
            match file.read_exact(&mut remaining) {
                Ok(()) => {}
                Err(_) => break,
            }

            let mut full_buf = header_buf.to_vec();
            full_buf.extend_from_slice(&remaining);

            match Record::from_bytes(&full_buf) {
                Ok(record) => {
                    let record_size = RecordHeader::SIZE as u64 + remaining_len as u64;
                    records.push((offset, record));
                    offset += record_size;
                }
                Err(_) => break,
            }
        }

        Ok(records)
    }

    /// Get the current file size (write offset)
    pub fn file_size(&self) -> u64 {
        *self.write_offset.read()
    }

    /// Get the base directory path
    pub fn base_dir(&self) -> &Path {
        &self.base_dir
    }

    /// Create a new active file (for compaction)
    pub fn rotate(&self) -> StoreResult<PathBuf> {
        let timestamp = chrono::Utc::now().timestamp_millis();
        let old_path = self.base_dir.join(format!("data_{}.torex", timestamp));
        let new_active = self.base_dir.join("data.torex");

        // Drop file handle, rename, create new
        {
            let mut file = self.active_file.write();
            *file = OpenOptions::new()
                .create(true)
                .append(true)
                .read(true)
                .open(&self.active_file_path)?;
        }

        fs::rename(&self.active_file_path, &old_path)?;

        {
            let mut file = self.active_file.write();
            *file = OpenOptions::new()
                .create(true)
                .append(true)
                .read(true)
                .open(&new_active)?;
        }

        *self.write_offset.write() = 0;

        Ok(old_path)
    }

    /// Write all records to a new compacted file
    pub fn write_compacted(&self, records: &[Record]) -> StoreResult<()> {
        let compacted_path = self.base_dir.join("data_compacted.torex");
        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&compacted_path)?;

        for record in records {
            let bytes = record.to_bytes();
            file.write_all(&bytes)?;
        }
        file.flush()?;

        Ok(())
    }

    /// Replace active file with compacted file
    pub fn finalize_compaction(&self) -> StoreResult<()> {
        let compacted_path = self.base_dir.join("data_compacted.torex");
        if !compacted_path.exists() {
            return Err(StoreError::InvalidOperation(
                "No compacted file found".to_string(),
            ));
        }

        // Drop file handle
        {
            let _ = self.active_file.write();
        }

        // Remove old data files
        let entries = fs::read_dir(&self.base_dir)?;
        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();
                if let Some(name) = path.file_name() {
                    let name = name.to_string_lossy();
                    if name.starts_with("data") && name != "data_compacted.torex" {
                        let _ = fs::remove_file(&path);
                    }
                }
            }
        }

        // Rename compacted to active
        fs::rename(&compacted_path, &self.active_file_path)?;

        // Reopen and update state
        {
            let mut file = self.active_file.write();
            *file = OpenOptions::new()
                .create(true)
                .append(true)
                .read(true)
                .open(&self.active_file_path)?;
        }

        let new_size = {
            let file = self.active_file.read();
            file.metadata()?.len()
        };
        *self.write_offset.write() = new_size;

        Ok(())
    }

    /// Parse a record header from raw bytes
    fn parse_header(data: &[u8]) -> StoreResult<RecordHeader> {
        if data.len() < RecordHeader::SIZE {
            return Err(StoreError::InvalidFormat("Header too short".to_string()));
        }

        let magic = data[0];
        if magic != super::format::MAGIC_BYTE {
            return Err(StoreError::InvalidFormat(format!(
                "Invalid magic byte: {:02X}",
                magic
            )));
        }

        let version = data[1];
        let record_type = RecordType::try_from(data[2])?;
        let flags = super::format::RecordFlags::from_bits_truncate(data[3]);

        let collection_len = u16::from_le_bytes([data[4], data[5]]);
        let id_len = u16::from_le_bytes([data[6], data[7]]);
        let data_len = u32::from_le_bytes([data[8], data[9], data[10], data[11]]);

        let timestamp = u64::from_le_bytes([
            data[12], data[13], data[14], data[15], data[16], data[17], data[18], data[19],
        ]);

        let crc32 = u32::from_le_bytes([data[20], data[21], data[22], data[23]]);

        Ok(RecordHeader {
            magic,
            version,
            record_type,
            flags,
            collection_len,
            id_len,
            data_len,
            timestamp,
            crc32,
        })
    }
}

impl Drop for StorageEngine {
    fn drop(&mut self) {
        // Ensure file is flushed on drop
        if let Some(mut file) = self.active_file.try_write() {
            let _ = file.flush();
        }
    }
}
