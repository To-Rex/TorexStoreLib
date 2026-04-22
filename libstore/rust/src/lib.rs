//! TOREX Storage - High-performance embedded database engine
//!
//! This library provides a production-ready embedded database with:
//! - Append-only binary storage
//! - Primary and secondary indexes
//! - Query engine with optimizer
//! - Reactive change notifications
//! - Compaction and garbage collection

pub mod db;
pub mod error;
pub mod index;
pub mod query;
pub mod reactive;
pub mod storage;

use std::sync::Arc;
use parking_lot::Mutex;

use db::Database;

/// Global database instance
static DB: once_cell::sync::Lazy<Mutex<Option<Arc<Database>>>> =
    once_cell::sync::Lazy::new(|| Mutex::new(None));

// ============================================================================
// Bridge API - Functions exposed to Dart via flutter_rust_bridge
// ============================================================================

/// Initialize the database at the given path
pub fn torex_init(path: String) -> Result<(), String> {
    let db = Database::open(&path).map_err(|e| e.to_string())?;
    let mut guard = DB.lock();
    *guard = Some(Arc::new(db));
    Ok(())
}

/// Close the database
pub fn torex_close() -> Result<(), String> {
    let mut guard = DB.lock();
    if let Some(db) = guard.take() {
        db.close();
    }
    Ok(())
}

/// Insert a record into a collection
pub fn torex_put(collection: String, id: String, data: Vec<u8>) -> Result<(), String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    db.put(&collection, &id, data).map_err(|e| e.to_string())
}

/// Get a record by collection and ID
pub fn torex_get(collection: String, id: String) -> Result<Vec<u8>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    db.get(&collection, &id).map_err(|e| e.to_string())
}

/// Update an existing record
pub fn torex_update(collection: String, id: String, data: Vec<u8>) -> Result<(), String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    db.update(&collection, &id, data).map_err(|e| e.to_string())
}

/// Delete a record
pub fn torex_delete(collection: String, id: String) -> Result<(), String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    db.delete(&collection, &id).map_err(|e| e.to_string())
}

/// Check if a record exists
pub fn torex_exists(collection: String, id: String) -> Result<bool, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    Ok(db.exists(&collection, &id))
}

/// Get all records in a collection
pub fn torex_get_all(collection: String) -> Result<Vec<Vec<u8>>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    db.get_all(&collection).map_err(|e| e.to_string())
}

/// Get record count in a collection
pub fn torex_count(collection: String) -> Result<usize, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    Ok(db.count(&collection))
}

/// Get all collection names
pub fn torex_collections() -> Result<Vec<String>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    Ok(db.collections())
}

/// Query records with a simple equality filter
pub fn torex_query_eq(collection: String, field: String, value: Vec<u8>) -> Result<Vec<Vec<u8>>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    let query = query::condition::Query::eq(&field, query::condition::QueryValue::String(
        String::from_utf8(value).unwrap_or_default()
    ));
    db.query(&collection, query).map_err(|e| e.to_string())
}

/// Query records with a greater-than filter (integer comparison)
pub fn torex_query_gt(collection: String, field: String, value: i64) -> Result<Vec<Vec<u8>>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    let query = query::condition::Query::gt(&field, query::condition::QueryValue::Integer(value));
    db.query(&collection, query).map_err(|e| e.to_string())
}

/// Query records with a less-than filter (integer comparison)
pub fn torex_query_lt(collection: String, field: String, value: i64) -> Result<Vec<Vec<u8>>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    let query = query::condition::Query::lt(&field, query::condition::QueryValue::Integer(value));
    db.query(&collection, query).map_err(|e| e.to_string())
}

/// Query records with a range filter (integer range)
pub fn torex_query_range(
    collection: String,
    field: String,
    start: i64,
    end: i64,
) -> Result<Vec<Vec<u8>>, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    let query = query::condition::Query::range(
        &field,
        query::condition::QueryValue::Integer(start),
        query::condition::QueryValue::Integer(end),
    );
    db.query(&collection, query).map_err(|e| e.to_string())
}

/// Run compaction on the database
pub fn torex_compact() -> Result<String, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    let stats = db.compact().map_err(|e| e.to_string())?;
    Ok(format!(
        "Compacted: {} -> {} records, {} bytes reclaimed",
        stats.records_before, stats.records_after, stats.space_reclaimed
    ))
}

/// Subscribe to collection changes
/// Returns subscription ID
pub fn torex_watch(collection: String) -> Result<u64, String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    let (id, _receiver) = db.watch(&collection);
    Ok(id)
}

/// Unsubscribe from collection changes
pub fn torex_unwatch(subscription_id: u64) -> Result<(), String> {
    let guard = DB.lock();
    let db = guard.as_ref().ok_or("Database not initialized".to_string())?;
    db.unwatch(subscription_id);
    Ok(())
}

/// Serialize a field map to binary format
///
/// Binary format:
/// [num_fields: u32]
/// For each field:
///   [field_name_len: u16][field_name: bytes][value_type: u8][value_data: variable]
///
/// Value types:
/// 0 = Null (no data)
/// 1 = String ([len: u32][data])
/// 2 = Integer ([i64: 8 bytes])
/// 3 = Float ([f64: 8 bytes])
/// 4 = Boolean ([u8])
pub fn torex_serialize_document(fields: Vec<(String, FieldValue)>) -> Vec<u8> {
    let mut buf = Vec::new();
    buf.extend_from_slice(&(fields.len() as u32).to_le_bytes());

    for (name, value) in fields {
        // Field name
        let name_bytes = name.as_bytes();
        buf.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
        buf.extend_from_slice(name_bytes);

        // Value
        match value {
            FieldValue::Null => {
                buf.push(0);
            }
            FieldValue::String(s) => {
                buf.push(1);
                let s_bytes = s.as_bytes();
                buf.extend_from_slice(&(s_bytes.len() as u32).to_le_bytes());
                buf.extend_from_slice(s_bytes);
            }
            FieldValue::Integer(i) => {
                buf.push(2);
                buf.extend_from_slice(&i.to_le_bytes());
            }
            FieldValue::Float(f) => {
                buf.push(3);
                buf.extend_from_slice(&f.to_le_bytes());
            }
            FieldValue::Boolean(b) => {
                buf.push(4);
                buf.push(if b { 1 } else { 0 });
            }
        }
    }

    buf
}

/// Field value types for document serialization
#[derive(Debug, Clone)]
pub enum FieldValue {
    Null,
    String(String),
    Integer(i64),
    Float(f64),
    Boolean(bool),
}
