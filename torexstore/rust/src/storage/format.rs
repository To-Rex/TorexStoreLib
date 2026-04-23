use crc32fast::Hasher;
use serde::{Deserialize, Serialize};

use crate::error::{StoreError, StoreResult};

/// Magic byte for TOREX storage format
pub const MAGIC_BYTE: u8 = 0x54; // 'T'
/// Current format version
pub const FORMAT_VERSION: u8 = 1;

/// Record types stored in the append-only log
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RecordType {
    /// New record insertion
    Insert = 1,
    /// Update existing record
    Update = 2,
    /// Delete a record (tombstone)
    Delete = 3,
    /// Compaction marker
    CompactionMarker = 4,
}

impl TryFrom<u8> for RecordType {
    type Error = StoreError;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            1 => Ok(RecordType::Insert),
            2 => Ok(RecordType::Update),
            3 => Ok(RecordType::Delete),
            4 => Ok(RecordType::CompactionMarker),
            _ => Err(StoreError::InvalidFormat(format!(
                "Invalid record type: {}",
                value
            ))),
        }
    }
}

bitflags::bitflags! {
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
    pub struct RecordFlags: u8 {
        const NONE = 0x00;
        const COMPRESSED = 0x01;
        const HAS_INDEX_DATA = 0x02;
    }
}

/// Header for each record in the append-only log
///
/// Binary layout (29 bytes):
/// [magic: u8][version: u8][record_type: u8][flags: u8]
/// [collection_len: u16][id_len: u16][data_len: u32]
/// [timestamp: u64][crc32: u32]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordHeader {
    /// Magic byte for format validation
    pub magic: u8,
    /// Format version
    pub version: u8,
    /// Type of record
    pub record_type: RecordType,
    /// Record flags
    pub flags: RecordFlags,
    /// Length of collection name in bytes
    pub collection_len: u16,
    /// Length of record ID in bytes
    pub id_len: u16,
    /// Length of payload data in bytes
    pub data_len: u32,
    /// Unix timestamp in milliseconds
    pub timestamp: u64,
    /// CRC32 checksum of the payload
    pub crc32: u32,
}

impl RecordHeader {
    /// Header size in bytes (fixed)
    pub const SIZE: usize = 29;

    /// Create a new header for an insert record
    pub fn new_insert(collection: &str, id: &str, data_len: u32) -> Self {
        Self {
            magic: MAGIC_BYTE,
            version: FORMAT_VERSION,
            record_type: RecordType::Insert,
            flags: RecordFlags::NONE,
            collection_len: collection.len() as u16,
            id_len: id.len() as u16,
            data_len,
            timestamp: chrono::Utc::now().timestamp_millis() as u64,
            crc32: 0,
        }
    }

    /// Create a new header for a delete record
    pub fn new_delete(collection: &str, id: &str) -> Self {
        Self {
            magic: MAGIC_BYTE,
            version: FORMAT_VERSION,
            record_type: RecordType::Delete,
            flags: RecordFlags::NONE,
            collection_len: collection.len() as u16,
            id_len: id.len() as u16,
            data_len: 0,
            timestamp: chrono::Utc::now().timestamp_millis() as u64,
            crc32: 0,
        }
    }

    /// Create a new header for an update record
    pub fn new_update(collection: &str, id: &str, data_len: u32) -> Self {
        Self {
            magic: MAGIC_BYTE,
            version: FORMAT_VERSION,
            record_type: RecordType::Update,
            flags: RecordFlags::NONE,
            collection_len: collection.len() as u16,
            id_len: id.len() as u16,
            data_len,
            timestamp: chrono::Utc::now().timestamp_millis() as u64,
            crc32: 0,
        }
    }

    /// Create a compaction marker header
    pub fn new_compaction_marker() -> Self {
        Self {
            magic: MAGIC_BYTE,
            version: FORMAT_VERSION,
            record_type: RecordType::CompactionMarker,
            flags: RecordFlags::NONE,
            collection_len: 0,
            id_len: 0,
            data_len: 0,
            timestamp: chrono::Utc::now().timestamp_millis() as u64,
            crc32: 0,
        }
    }

    /// Total record size on disk (header + collection + id + data)
    pub fn total_size(&self) -> u64 {
        RecordHeader::SIZE as u64
            + self.collection_len as u64
            + self.id_len as u64
            + self.data_len as u64
    }
}

/// A complete record with all data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Record {
    /// Record header
    pub header: RecordHeader,
    /// Collection name
    pub collection: String,
    /// Record ID
    pub id: String,
    /// Binary payload data
    pub data: Vec<u8>,
}

impl Record {
    /// Create a new insert record
    pub fn new_insert(collection: &str, id: &str, data: Vec<u8>) -> Self {
        let data_len = data.len() as u32;
        let mut header = RecordHeader::new_insert(collection, id, data_len);
        header.crc32 = compute_crc32(&data);

        Self {
            header,
            collection: collection.to_string(),
            id: id.to_string(),
            data,
        }
    }

    /// Create a new delete record (tombstone)
    pub fn new_delete(collection: &str, id: &str) -> Self {
        let header = RecordHeader::new_delete(collection, id);
        Self {
            header,
            collection: collection.to_string(),
            id: id.to_string(),
            data: Vec::new(),
        }
    }

    /// Create a new update record
    pub fn new_update(collection: &str, id: &str, data: Vec<u8>) -> Self {
        let data_len = data.len() as u32;
        let mut header = RecordHeader::new_update(collection, id, data_len);
        header.crc32 = compute_crc32(&data);

        Self {
            header,
            collection: collection.to_string(),
            id: id.to_string(),
            data,
        }
    }

    /// Check if this record is a tombstone (deleted)
    pub fn is_deleted(&self) -> bool {
        self.header.record_type == RecordType::Delete
    }

    /// Validate the CRC32 checksum
    pub fn validate_crc(&self) -> bool {
        if self.data.is_empty() {
            return true;
        }
        compute_crc32(&self.data) == self.header.crc32
    }

    /// Serialize the record to binary format for writing to disk
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(RecordHeader::SIZE + self.collection.len() + self.id.len() + self.data.len());

        // Header fields
        buf.push(self.header.magic);
        buf.push(self.header.version);
        buf.push(self.header.record_type as u8);
        buf.push(self.header.flags.bits());
        buf.extend_from_slice(&self.header.collection_len.to_le_bytes());
        buf.extend_from_slice(&self.header.id_len.to_le_bytes());
        buf.extend_from_slice(&self.header.data_len.to_le_bytes());
        buf.extend_from_slice(&self.header.timestamp.to_le_bytes());
        buf.extend_from_slice(&self.header.crc32.to_le_bytes());

        // Data fields
        buf.extend_from_slice(self.collection.as_bytes());
        buf.extend_from_slice(self.id.as_bytes());
        buf.extend_from_slice(&self.data);

        buf
    }

    /// Deserialize a record from binary data
    pub fn from_bytes(data: &[u8]) -> StoreResult<Self> {
        if data.len() < RecordHeader::SIZE {
            return Err(StoreError::InvalidFormat(format!(
                "Data too short for header: {} bytes",
                data.len()
            )));
        }

        let mut pos = 0;

        // Parse header
        let magic = data[pos];
        pos += 1;
        if magic != MAGIC_BYTE {
            return Err(StoreError::InvalidFormat(format!(
                "Invalid magic byte: {:02X}",
                magic
            )));
        }

        let version = data[pos];
        pos += 1;
        if version != FORMAT_VERSION {
            return Err(StoreError::InvalidFormat(format!(
                "Unsupported version: {}",
                version
            )));
        }

        let record_type = RecordType::try_from(data[pos])?;
        pos += 1;

        let flags = RecordFlags::from_bits_truncate(data[pos]);
        pos += 1;

        let collection_len = u16::from_le_bytes([data[pos], data[pos + 1]]);
        pos += 2;
        let id_len = u16::from_le_bytes([data[pos], data[pos + 1]]);
        pos += 2;
        let data_len = u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]);
        pos += 4;
        let timestamp = u64::from_le_bytes([
            data[pos], data[pos + 1], data[pos + 2], data[pos + 3],
            data[pos + 4], data[pos + 5], data[pos + 6], data[pos + 7],
        ]);
        pos += 8;
        let crc32 = u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]);
        pos += 4;

        let header = RecordHeader {
            magic,
            version,
            record_type,
            flags,
            collection_len,
            id_len,
            data_len,
            timestamp,
            crc32,
        };

        // Validate remaining data length
        let remaining = data.len() - pos;
        let expected = collection_len as usize + id_len as usize + data_len as usize;
        if remaining < expected {
            return Err(StoreError::InvalidFormat(format!(
                "Insufficient data: expected {} bytes, got {}",
                expected, remaining
            )));
        }

        // Parse data fields
        let collection = String::from_utf8(data[pos..pos + collection_len as usize].to_vec())
            .map_err(|e| StoreError::InvalidFormat(format!("Invalid collection name: {}", e)))?;
        pos += collection_len as usize;

        let id = String::from_utf8(data[pos..pos + id_len as usize].to_vec())
            .map_err(|e| StoreError::InvalidFormat(format!("Invalid ID: {}", e)))?;
        pos += id_len as usize;

        let payload = data[pos..pos + data_len as usize].to_vec();

        Ok(Record {
            header,
            collection,
            id,
            data: payload,
        })
    }
}

/// Compute CRC32 checksum
fn compute_crc32(data: &[u8]) -> u32 {
    let mut hasher = Hasher::new();
    hasher.update(data);
    hasher.finalize()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_roundtrip() {
        let original = Record::new_insert("users", "user_123", b"hello world".to_vec());
        let bytes = original.to_bytes();
        let parsed = Record::from_bytes(&bytes).unwrap();

        assert_eq!(original.collection, parsed.collection);
        assert_eq!(original.id, parsed.id);
        assert_eq!(original.data, parsed.data);
        assert_eq!(original.header.record_type, parsed.header.record_type);
    }

    #[test]
    fn test_delete_record() {
        let record = Record::new_delete("users", "user_123");
        assert!(record.is_deleted());
        assert!(record.data.is_empty());
    }

    #[test]
    fn test_crc_validation() {
        let record = Record::new_insert("users", "user_1", b"test data".to_vec());
        assert!(record.validate_crc());
    }
}
