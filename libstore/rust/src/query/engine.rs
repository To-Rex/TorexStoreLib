use std::collections::HashSet;

use crate::error::StoreResult;
use crate::index::primary::PrimaryIndex;
use crate::index::secondary::{IndexValue, SecondaryIndex};
use crate::query::condition::{ExecutionPlan, Operator, Query, QueryValue};
use crate::storage::engine::StorageEngine;
use crate::storage::format::Record;

/// Query execution engine
///
/// Executes queries using the execution plan provided by the optimizer.
/// Supports index-based lookups and full collection scans.
pub struct QueryEngine<'a> {
    storage: &'a StorageEngine,
    primary: &'a PrimaryIndex,
    secondary: &'a SecondaryIndex,
}

impl<'a> QueryEngine<'a> {
    /// Create a new query engine with references
    pub fn new(
        storage: &'a StorageEngine,
        primary: &'a PrimaryIndex,
        secondary: &'a SecondaryIndex,
    ) -> Self {
        Self {
            storage,
            primary,
            secondary,
        }
    }

    /// Execute a query on a collection
    pub fn execute(&self, collection: &str, query: &Query, plan: &ExecutionPlan) -> StoreResult<Vec<Record>> {
        let ids = match plan {
            ExecutionPlan::PrimaryLookup { id } => {
                // Direct primary index lookup
                if let Some(offset) = self.primary.get(collection, id) {
                    let record = self.storage.read_at(offset)?;
                    if !record.is_deleted() {
                        return Ok(vec![record]);
                    }
                }
                return Ok(vec![]);
            }

            ExecutionPlan::IndexScan {
                field,
                operator,
                value,
                value2,
            } => {
                self.execute_index_scan(collection, field, operator, value, value2)?
            }

            ExecutionPlan::FullScan => {
                self.execute_full_scan(collection, query)?
            }
        };

        // Fetch records for the matched IDs
        let mut records = Vec::with_capacity(ids.len());
        for id in ids {
            if let Some(offset) = self.primary.get(collection, &id) {
                if let Ok(record) = self.storage.read_at(offset) {
                    if !record.is_deleted() {
                        records.push(record);
                    }
                }
            }
        }

        Ok(records)
    }

    /// Execute an index scan using the secondary index
    fn execute_index_scan(
        &self,
        collection: &str,
        field: &str,
        operator: &Operator,
        value: &IndexValue,
        value2: &Option<IndexValue>,
    ) -> StoreResult<HashSet<String>> {
        let ids = match operator {
            Operator::Equal => self.secondary.find_exact(collection, field, value),

            Operator::NotEqual => {
                let all_ids: HashSet<String> = self
                    .primary
                    .get_collection_ids(collection)
                    .into_iter()
                    .collect();
                let exact = self.secondary.find_exact(collection, field, value);
                all_ids.into_iter().filter(|id| !exact.contains(id)).collect()
            }

            Operator::GreaterThan => self.secondary.find_gt(collection, field, value),

            Operator::LessThan => self.secondary.find_lt(collection, field, value),

            Operator::GreaterThanOrEqual => {
                let gt = self.secondary.find_gt(collection, field, value);
                let eq = self.secondary.find_exact(collection, field, value);
                gt.union(&eq).cloned().collect()
            }

            Operator::LessThanOrEqual => {
                let lt = self.secondary.find_lt(collection, field, value);
                let eq = self.secondary.find_exact(collection, field, value);
                lt.union(&eq).cloned().collect()
            }

            Operator::Range => {
                if let Some(end) = value2 {
                    self.secondary.find_range(collection, field, value, end)
                } else {
                    HashSet::new()
                }
            }
        };

        Ok(ids)
    }

    /// Execute a full collection scan, evaluating each record against the query
    fn execute_full_scan(&self, collection: &str, query: &Query) -> StoreResult<HashSet<String>> {
        let offsets = self.primary.get_collection_offsets(collection);
        let mut matching_ids = HashSet::new();

        for (id, offset) in offsets {
            if let Ok(record) = self.storage.read_at(offset) {
                if record.is_deleted() {
                    continue;
                }

                if self.evaluate_record(&record, query) {
                    matching_ids.insert(id);
                }
            }
        }

        Ok(matching_ids)
    }

    /// Evaluate a record against a query condition
    fn evaluate_record(&self, record: &Record, query: &Query) -> bool {
        match query {
            Query::All => true,

            Query::Condition(cond) => {
                if let Ok(fields) = deserialize_fields(&record.data) {
                    if let Some(field_value) = fields.get(&cond.field) {
                        compare_values(field_value, &cond.operator, &cond.value, &cond.value2)
                    } else {
                        false
                    }
                } else {
                    false
                }
            }

            Query::And(conditions) => conditions
                .iter()
                .all(|q| self.evaluate_record(record, q)),

            Query::Or(conditions) => conditions
                .iter()
                .any(|q| self.evaluate_record(record, q)),
        }
    }

    /// Get all records in a collection
    pub fn get_all(&self, collection: &str) -> StoreResult<Vec<Record>> {
        let offsets = self.primary.get_collection_offsets(collection);
        let mut records = Vec::with_capacity(offsets.len());

        for (_, offset) in offsets {
            if let Ok(record) = self.storage.read_at(offset) {
                if !record.is_deleted() {
                    records.push(record);
                }
            }
        }

        Ok(records)
    }
}

/// Deserialize binary payload into a field map
///
/// The binary format for fields is:
/// [num_fields: u32]
/// For each field:
///   [field_name_len: u16][field_name: bytes][value_type: u8][value_data: variable]
fn deserialize_fields(data: &[u8]) -> Result<std::collections::HashMap<String, QueryValue>, ()> {
    use std::io::Cursor;
    use std::io::Read;

    if data.is_empty() {
        return Ok(std::collections::HashMap::new());
    }

    let mut cursor = Cursor::new(data);
    let mut map = std::collections::HashMap::new();

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
            0 => QueryValue::Null,
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
                QueryValue::String(String::from_utf8(str_buf).map_err(|_| ())?)
            }
            2 => {
                let mut buf = [0u8; 8];
                if cursor.read_exact(&mut buf).is_err() {
                    break;
                }
                QueryValue::Integer(i64::from_le_bytes(buf))
            }
            3 => {
                let mut buf = [0u8; 8];
                if cursor.read_exact(&mut buf).is_err() {
                    break;
                }
                QueryValue::Float(f64::from_le_bytes(buf))
            }
            4 => {
                let mut buf = [0u8; 1];
                if cursor.read_exact(&mut buf).is_err() {
                    break;
                }
                QueryValue::Boolean(buf[0] != 0)
            }
            _ => break,
        };

        map.insert(name, value);
    }

    Ok(map)
}

/// Compare a field value against a query condition
fn compare_values(
    field_value: &QueryValue,
    operator: &Operator,
    query_value: &QueryValue,
    query_value2: &Option<QueryValue>,
) -> bool {
    match operator {
        Operator::Equal => field_value == query_value,
        Operator::NotEqual => field_value != query_value,

        Operator::GreaterThan | Operator::LessThan
        | Operator::GreaterThanOrEqual | Operator::LessThanOrEqual => {
            match (field_value, query_value) {
                (QueryValue::Integer(a), QueryValue::Integer(b)) => {
                    match operator {
                        Operator::GreaterThan => a > b,
                        Operator::LessThan => a < b,
                        Operator::GreaterThanOrEqual => a >= b,
                        Operator::LessThanOrEqual => a <= b,
                        _ => false,
                    }
                }
                (QueryValue::Float(a), QueryValue::Float(b)) => {
                    match operator {
                        Operator::GreaterThan => a > b,
                        Operator::LessThan => a < b,
                        Operator::GreaterThanOrEqual => a >= b,
                        Operator::LessThanOrEqual => a <= b,
                        _ => false,
                    }
                }
                (QueryValue::String(a), QueryValue::String(b)) => {
                    match operator {
                        Operator::GreaterThan => a > b,
                        Operator::LessThan => a < b,
                        Operator::GreaterThanOrEqual => a >= b,
                        Operator::LessThanOrEqual => a <= b,
                        _ => false,
                    }
                }
                _ => false,
            }
        }

        Operator::Range => {
            if let Some(end) = query_value2 {
                compare_values(field_value, &Operator::GreaterThanOrEqual, query_value, &None)
                    && compare_values(field_value, &Operator::LessThan, end, &None)
            } else {
                false
            }
        }
    }
}
