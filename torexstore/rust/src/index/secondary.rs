use std::collections::{BTreeMap, HashMap, HashSet};
use std::ops::Bound;
use parking_lot::RwLock;

/// Secondary index value - supports different field types for indexing
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum IndexValue {
    /// String value
    String(String),
    /// Integer value (stored as i64 for sorting)
    Integer(i64),
    /// Float value (stored as bits for HashMap key, ordered via BTreeMap)
    Float(u64),
    /// Boolean value
    Bool(bool),
    /// Null value
    Null,
}

impl IndexValue {
    /// Create from a string
    pub fn from_string(s: &str) -> Self {
        IndexValue::String(s.to_string())
    }

    /// Create from an integer
    pub fn from_int(i: i64) -> Self {
        IndexValue::Integer(i)
    }

    /// Create from a float
    pub fn from_float(f: f64) -> Self {
        IndexValue::Float(f.to_bits())
    }

    /// Create from a boolean
    pub fn from_bool(b: bool) -> Self {
        IndexValue::Bool(b)
    }

    /// Get the float value back
    pub fn as_float(&self) -> Option<f64> {
        match self {
            IndexValue::Float(bits) => Some(f64::from_bits(*bits)),
            _ => None,
        }
    }

    /// Get the integer value back
    pub fn as_int(&self) -> Option<i64> {
        match self {
            IndexValue::Integer(i) => Some(*i),
            _ => None,
        }
    }
}

/// Secondary index: maps (collection, field, value) -> Set<record_id>
///
/// Uses BTreeMap for range query support and HashMap for O(1) exact lookups.
pub struct SecondaryIndex {
    /// Exact lookup: collection -> field -> value -> set of IDs
    exact: RwLock<HashMap<String, HashMap<String, HashMap<IndexValue, HashSet<String>>>>>,
    /// Ordered index for range queries: collection -> field -> (value -> set of IDs)
    ordered: RwLock<HashMap<String, HashMap<String, BTreeMap<IndexValue, HashSet<String>>>>>,
}

impl SecondaryIndex {
    /// Create a new empty secondary index
    pub fn new() -> Self {
        Self {
            exact: RwLock::new(HashMap::new()),
            ordered: RwLock::new(HashMap::new()),
        }
    }

    /// Add a record to the secondary index for a given field and value
    pub fn insert(&self, collection: &str, field: &str, value: IndexValue, id: &str) {
        // Update exact index
        {
            let mut exact = self.exact.write();
            exact
                .entry(collection.to_string())
                .or_insert_with(HashMap::new)
                .entry(field.to_string())
                .or_insert_with(HashMap::new)
                .entry(value.clone())
                .or_insert_with(HashSet::new)
                .insert(id.to_string());
        }

        // Update ordered index
        {
            let mut ordered = self.ordered.write();
            ordered
                .entry(collection.to_string())
                .or_insert_with(HashMap::new)
                .entry(field.to_string())
                .or_insert_with(BTreeMap::new)
                .entry(value)
                .or_insert_with(HashSet::new)
                .insert(id.to_string());
        }
    }

    /// Remove a record from the secondary index
    pub fn remove(&self, collection: &str, field: &str, value: &IndexValue, id: &str) {
        // Remove from exact index
        {
            let mut exact = self.exact.write();
            if let Some(coll) = exact.get_mut(collection) {
                if let Some(field_idx) = coll.get_mut(field) {
                    if let Some(ids) = field_idx.get_mut(value) {
                        ids.remove(id);
                        if ids.is_empty() {
                            field_idx.remove(value);
                        }
                    }
                }
            }
        }

        // Remove from ordered index
        {
            let mut ordered = self.ordered.write();
            if let Some(coll) = ordered.get_mut(collection) {
                if let Some(field_idx) = coll.get_mut(field) {
                    if let Some(ids) = field_idx.get_mut(value) {
                        ids.remove(id);
                        if ids.is_empty() {
                            field_idx.remove(value);
                        }
                    }
                }
            }
        }
    }

    /// Remove all index entries for a specific record ID in a collection
    pub fn remove_id(&self, collection: &str, id: &str) {
        // We need to scan all fields and values to find and remove this ID
        let fields_to_clean: Vec<(String, Vec<IndexValue>)> = {
            let exact = self.exact.read();
            if let Some(coll) = exact.get(collection) {
                coll.iter()
                    .map(|(field, value_map)| {
                        let values: Vec<IndexValue> = value_map
                            .iter()
                            .filter(|(_, ids)| ids.contains(id))
                            .map(|(v, _)| v.clone())
                            .collect();
                        (field.clone(), values)
                    })
                    .filter(|(_, values)| !values.is_empty())
                    .collect()
            } else {
                Vec::new()
            }
        };

        for (field, values) in fields_to_clean {
            for value in values {
                self.remove(collection, &field, &value, id);
            }
        }
    }

    /// Exact lookup: find all IDs matching a specific field value
    pub fn find_exact(&self, collection: &str, field: &str, value: &IndexValue) -> HashSet<String> {
        let exact = self.exact.read();
        exact
            .get(collection)
            .and_then(|coll| coll.get(field))
            .and_then(|field_idx| field_idx.get(value))
            .cloned()
            .unwrap_or_default()
    }

    /// Range query: find all IDs where field value is in [start, end)
    pub fn find_range(
        &self,
        collection: &str,
        field: &str,
        start: &IndexValue,
        end: &IndexValue,
    ) -> HashSet<String> {
        let ordered = self.ordered.read();
        let mut result = HashSet::new();

        if let Some(coll) = ordered.get(collection) {
            if let Some(field_idx) = coll.get(field) {
                for (_value, ids) in field_idx.range(start.clone()..end.clone()) {
                    result.extend(ids.iter().cloned());
                }
            }
        }

        result
    }

    /// Greater than query: find all IDs where field value > start
    pub fn find_gt(&self, collection: &str, field: &str, start: &IndexValue) -> HashSet<String> {
        let ordered = self.ordered.read();
        let mut result = HashSet::new();

        if let Some(coll) = ordered.get(collection) {
            if let Some(field_idx) = coll.get(field) {
                for (_value, ids) in field_idx.range((Bound::Excluded(start.clone()), Bound::Unbounded)) {
                    result.extend(ids.iter().cloned());
                }
            }
        }

        result
    }

    /// Less than query: find all IDs where field value < end
    pub fn find_lt(&self, collection: &str, field: &str, end: &IndexValue) -> HashSet<String> {
        let ordered = self.ordered.read();
        let mut result = HashSet::new();

        if let Some(coll) = ordered.get(collection) {
            if let Some(field_idx) = coll.get(field) {
                for (_value, ids) in field_idx.range((Bound::Unbounded, Bound::Excluded(end.clone()))) {
                    result.extend(ids.iter().cloned());
                }
            }
        }

        result
    }

    /// Check if a secondary index exists for a collection field
    pub fn has_index(&self, collection: &str, field: &str) -> bool {
        let exact = self.exact.read();
        exact
            .get(collection)
            .and_then(|coll| coll.get(field))
            .map(|field_idx| !field_idx.is_empty())
            .unwrap_or(false)
    }

    /// Clear all indexes for a collection
    pub fn clear_collection(&self, collection: &str) {
        self.exact.write().remove(collection);
        self.ordered.write().remove(collection);
    }

    /// Clear all indexes
    pub fn clear(&self) {
        self.exact.write().clear();
        self.ordered.write().clear();
    }
}

impl Default for SecondaryIndex {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exact_lookup() {
        let idx = SecondaryIndex::new();
        idx.insert("users", "age", IndexValue::from_int(25), "user_1");
        idx.insert("users", "age", IndexValue::from_int(25), "user_2");
        idx.insert("users", "age", IndexValue::from_int(30), "user_3");

        let result = idx.find_exact("users", "age", &IndexValue::from_int(25));
        assert_eq!(result.len(), 2);
        assert!(result.contains("user_1"));
        assert!(result.contains("user_2"));
    }

    #[test]
    fn test_range_query() {
        let idx = SecondaryIndex::new();
        idx.insert("users", "age", IndexValue::from_int(20), "user_1");
        idx.insert("users", "age", IndexValue::from_int(25), "user_2");
        idx.insert("users", "age", IndexValue::from_int(30), "user_3");
        idx.insert("users", "age", IndexValue::from_int(35), "user_4");

        let result = idx.find_range(
            "users",
            "age",
            &IndexValue::from_int(25),
            &IndexValue::from_int(35),
        );
        assert_eq!(result.len(), 2);
        assert!(result.contains("user_2"));
        assert!(result.contains("user_3"));
    }

    #[test]
    fn test_remove_id() {
        let idx = SecondaryIndex::new();
        idx.insert("users", "name", IndexValue::from_string("Alice"), "user_1");
        idx.insert("users", "name", IndexValue::from_string("Alice"), "user_2");

        idx.remove_id("users", "user_1");

        let result = idx.find_exact("users", "name", &IndexValue::from_string("Alice"));
        assert_eq!(result.len(), 1);
        assert!(result.contains("user_2"));
    }
}
