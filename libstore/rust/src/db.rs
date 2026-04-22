use std::path::Path;
use std::sync::Arc;

use parking_lot::Mutex;

use crate::error::{StoreError, StoreResult};
use crate::index::primary::PrimaryIndex;
use crate::index::secondary::{IndexValue, SecondaryIndex};
use crate::query::condition::Query;
use crate::query::engine::QueryEngine;
use crate::query::optimizer::QueryOptimizer;
use crate::reactive::watcher::{StoreEvent, WatcherSystem};
use crate::storage::compaction::{self, CompactionStats, CompactionStrategy};
use crate::storage::engine::StorageEngine;
use crate::storage::format::Record;
use crossbeam_channel::Receiver;

/// Main database facade
///
/// Provides the high-level API for all database operations.
/// Thread-safe through internal synchronization.
pub struct Database {
    storage: Arc<StorageEngine>,
    primary: Arc<PrimaryIndex>,
    secondary: Arc<SecondaryIndex>,
    watcher: Arc<WatcherSystem>,
    closed: Mutex<bool>,
}

impl Database {
    /// Open or create a database at the given path
    pub fn open(path: &str) -> StoreResult<Self> {
        let base_dir = Path::new(path);
        let storage = StorageEngine::open(base_dir)?;
        let primary = PrimaryIndex::new();
        let secondary = SecondaryIndex::new();

        // Rebuild indexes from existing data
        let records = storage.scan_all()?;
        let mut index_entries = Vec::new();

        for (offset, record) in &records {
            let is_deleted = record.header.record_type == crate::storage::format::RecordType::Delete;
            index_entries.push((*offset, record.collection.clone(), record.id.clone(), is_deleted));
        }

        primary.rebuild_from(index_entries);

        // Rebuild secondary indexes from live records
        for (_, record) in records {
            if !record.is_deleted() {
                if let Ok(fields) = deserialize_fields_for_index(&record.data) {
                    for (field, value) in fields {
                        secondary.insert(&record.collection, &field, value, &record.id);
                    }
                }
            }
        }

        Ok(Self {
            storage: Arc::new(storage),
            primary: Arc::new(primary),
            secondary: Arc::new(secondary),
            watcher: Arc::new(WatcherSystem::new()),
            closed: Mutex::new(false),
        })
    }

    /// Insert a new record into a collection
    pub fn put(&self, collection: &str, id: &str, data: Vec<u8>) -> StoreResult<()> {
        self.ensure_open()?;

        let record = Record::new_insert(collection, id, data.clone());
        let offset = self.storage.append(&record)?;

        // Update primary index
        self.primary.insert(collection, id, offset);

        // Update secondary indexes
        if let Ok(fields) = deserialize_fields_for_index(&data) {
            for (field, value) in fields {
                self.secondary.insert(collection, &field, value, id);
            }
        }

        // Notify watchers
        self.watcher.notify(StoreEvent::Insert {
            collection: collection.to_string(),
            id: id.to_string(),
            data,
        });

        Ok(())
    }

    /// Get a record by collection and ID
    pub fn get(&self, collection: &str, id: &str) -> StoreResult<Vec<u8>> {
        self.ensure_open()?;

        let offset = self
            .primary
            .get(collection, id)
            .ok_or_else(|| StoreError::NotFound(id.to_string()))?;

        let record = self.storage.read_at(offset)?;
        if record.is_deleted() {
            return Err(StoreError::NotFound(id.to_string()));
        }

        Ok(record.data)
    }

    /// Update an existing record
    pub fn update(&self, collection: &str, id: &str, data: Vec<u8>) -> StoreResult<()> {
        self.ensure_open()?;

        // Check if record exists
        if !self.primary.contains(collection, id) {
            return Err(StoreError::NotFound(id.to_string()));
        }

        // Remove old secondary index entries
        self.secondary.remove_id(collection, id);

        // Write update record
        let record = Record::new_update(collection, id, data.clone());
        let offset = self.storage.append(&record)?;

        // Update primary index with new offset
        self.primary.insert(collection, id, offset);

        // Update secondary indexes
        if let Ok(fields) = deserialize_fields_for_index(&data) {
            for (field, value) in fields {
                self.secondary.insert(collection, &field, value, id);
            }
        }

        // Notify watchers
        self.watcher.notify(StoreEvent::Update {
            collection: collection.to_string(),
            id: id.to_string(),
            data,
        });

        Ok(())
    }

    /// Delete a record
    pub fn delete(&self, collection: &str, id: &str) -> StoreResult<()> {
        self.ensure_open()?;

        // Check if record exists
        if !self.primary.contains(collection, id) {
            return Err(StoreError::NotFound(id.to_string()));
        }

        // Write tombstone record
        let record = Record::new_delete(collection, id);
        self.storage.append(&record)?;

        // Remove from indexes
        self.primary.remove(collection, id);
        self.secondary.remove_id(collection, id);

        // Notify watchers
        self.watcher.notify(StoreEvent::Delete {
            collection: collection.to_string(),
            id: id.to_string(),
        });

        Ok(())
    }

    /// Query records in a collection
    pub fn query(&self, collection: &str, query: Query) -> StoreResult<Vec<Vec<u8>>> {
        self.ensure_open()?;

        let plan = QueryOptimizer::optimize(&*self.secondary, collection, &query);

        let query_engine = QueryEngine::new(
            &*self.storage,
            &*self.primary,
            &*self.secondary,
        );

        let records = query_engine.execute(collection, &query, &plan)?;
        Ok(records.into_iter().map(|r| r.data).collect())
    }

    /// Get all records in a collection
    pub fn get_all(&self, collection: &str) -> StoreResult<Vec<Vec<u8>>> {
        self.ensure_open()?;

        let offsets = self.primary.get_collection_offsets(collection);
        let mut results = Vec::with_capacity(offsets.len());

        for (_, offset) in offsets {
            if let Ok(record) = self.storage.read_at(offset) {
                if !record.is_deleted() {
                    results.push(record.data);
                }
            }
        }

        Ok(results)
    }

    /// Get record count in a collection
    pub fn count(&self, collection: &str) -> usize {
        self.primary.collection_count(collection)
    }

    /// Get all collection names
    pub fn collections(&self) -> Vec<String> {
        self.primary.collections()
    }

    /// Check if a record exists
    pub fn exists(&self, collection: &str, id: &str) -> bool {
        self.primary.contains(collection, id)
    }

    /// Watch a collection for changes
    ///
    /// Returns a subscription ID and a receiver for events
    pub fn watch(&self, collection: &str) -> (u64, Receiver<StoreEvent>) {
        self.watcher.subscribe(collection)
    }

    /// Unwatch a collection
    pub fn unwatch(&self, subscription_id: u64) {
        self.watcher.unsubscribe(subscription_id);
    }

    /// Run compaction on the database
    pub fn compact(&self) -> StoreResult<CompactionStats> {
        self.ensure_open()?;
        compaction::compact(&self.storage, CompactionStrategy::Full)
    }

    /// Check if compaction is needed
    pub fn needs_compaction(&self, threshold: f64) -> StoreResult<bool> {
        compaction::needs_compaction(&self.storage, threshold)
    }

    /// Close the database
    pub fn close(&self) {
        let mut closed = self.closed.lock();
        *closed = true;
        self.watcher.clear_all();
    }

    /// Check if database is open
    fn ensure_open(&self) -> StoreResult<()> {
        if *self.closed.lock() {
            Err(StoreError::Closed)
        } else {
            Ok(())
        }
    }
}

/// Deserialize binary fields for secondary indexing
fn deserialize_fields_for_index(data: &[u8]) -> Result<Vec<(String, IndexValue)>, ()> {
    use std::io::Cursor;
    use std::io::Read;

    if data.is_empty() {
        return Ok(Vec::new());
    }

    let mut cursor = Cursor::new(data);
    let mut fields = Vec::new();

    let mut buf4 = [0u8; 4];
    if cursor.read_exact(&mut buf4).is_err() {
        return Err(());
    }
    let num_fields = u32::from_le_bytes(buf4);

    for _ in 0..num_fields {
        let mut buf2 = [0u8; 2];
        if cursor.read_exact(&mut buf2).is_err() {
            break;
        }
        let name_len = u16::from_le_bytes(buf2) as usize;

        let mut name_buf = vec![0u8; name_len];
        if cursor.read_exact(&mut name_buf).is_err() {
            break;
        }
        let name = String::from_utf8(name_buf).map_err(|_| ())?;

        let mut type_buf = [0u8; 1];
        if cursor.read_exact(&mut type_buf).is_err() {
            break;
        }

        let value = match type_buf[0] {
            0 => IndexValue::Null,
            1 => {
                let mut len_buf = [0u8; 4];
                if cursor.read_exact(&mut len_buf).is_err() {
                    break;
                }
                let len = u32::from_le_bytes(len_buf) as usize;
                let mut str_buf = vec![0u8; len];
                if cursor.read_exact(&mut str_buf).is_err() {
                    break;
                }
                IndexValue::String(String::from_utf8(str_buf).map_err(|_| ())?)
            }
            2 => {
                let mut buf = [0u8; 8];
                if cursor.read_exact(&mut buf).is_err() {
                    break;
                }
                IndexValue::Integer(i64::from_le_bytes(buf))
            }
            3 => {
                let mut buf = [0u8; 8];
                if cursor.read_exact(&mut buf).is_err() {
                    break;
                }
                IndexValue::Float(u64::from_le_bytes(buf))
            }
            4 => {
                let mut buf = [0u8; 1];
                if cursor.read_exact(&mut buf).is_err() {
                    break;
                }
                IndexValue::Bool(buf[0] != 0)
            }
            _ => break,
        };

        fields.push((name, value));
    }

    Ok(fields)
}
