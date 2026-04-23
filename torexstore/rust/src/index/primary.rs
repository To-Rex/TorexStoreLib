use std::collections::HashMap;
use parking_lot::RwLock;

/// Primary index: maps (collection, id) -> file_offset
///
/// Provides O(1) lookups for records by their primary key.
/// Thread-safe using read-write locks.
pub struct PrimaryIndex {
    /// Inner index storage: collection -> (id -> offset)
    index: RwLock<HashMap<String, HashMap<String, u64>>>,
}

impl PrimaryIndex {
    /// Create a new empty primary index
    pub fn new() -> Self {
        Self {
            index: RwLock::new(HashMap::new()),
        }
    }

    /// Insert or update a record's offset in the index
    pub fn insert(&self, collection: &str, id: &str, offset: u64) {
        let mut index = self.index.write();
        index
            .entry(collection.to_string())
            .or_insert_with(HashMap::new)
            .insert(id.to_string(), offset);
    }

    /// Get the file offset for a record
    pub fn get(&self, collection: &str, id: &str) -> Option<u64> {
        let index = self.index.read();
        index
            .get(collection)
            .and_then(|coll| coll.get(id))
            .copied()
    }

    /// Remove a record from the index
    pub fn remove(&self, collection: &str, id: &str) -> Option<u64> {
        let mut index = self.index.write();
        index
            .get_mut(collection)
            .and_then(|coll| coll.remove(id))
    }

    /// Check if a record exists
    pub fn contains(&self, collection: &str, id: &str) -> bool {
        let index = self.index.read();
        index
            .get(collection)
            .map(|coll| coll.contains_key(id))
            .unwrap_or(false)
    }

    /// Get all IDs in a collection
    pub fn get_collection_ids(&self, collection: &str) -> Vec<String> {
        let index = self.index.read();
        index
            .get(collection)
            .map(|coll| coll.keys().cloned().collect())
            .unwrap_or_default()
    }

    /// Get all offsets in a collection (for full scan)
    pub fn get_collection_offsets(&self, collection: &str) -> Vec<(String, u64)> {
        let index = self.index.read();
        index
            .get(collection)
            .map(|coll| coll.iter().map(|(k, &v)| (k.clone(), v)).collect())
            .unwrap_or_default()
    }

    /// Get the number of records in a collection
    pub fn collection_count(&self, collection: &str) -> usize {
        let index = self.index.read();
        index
            .get(collection)
            .map(|coll| coll.len())
            .unwrap_or(0)
    }

    /// Get total number of records across all collections
    pub fn total_count(&self) -> usize {
        let index = self.index.read();
        index.values().map(|coll| coll.len()).sum()
    }

    /// Get all collection names
    pub fn collections(&self) -> Vec<String> {
        let index = self.index.read();
        index.keys().cloned().collect()
    }

    /// Clear the entire index
    pub fn clear(&self) {
        let mut index = self.index.write();
        index.clear();
    }

    /// Clear a specific collection from the index
    pub fn clear_collection(&self, collection: &str) {
        let mut index = self.index.write();
        index.remove(collection);
    }

    /// Rebuild index from a list of (offset, collection, id, is_deleted) tuples
    pub fn rebuild_from(&self, entries: Vec<(u64, String, String, bool)>) {
        let mut index = self.index.write();
        index.clear();

        for (offset, collection, id, is_deleted) in entries {
            if is_deleted {
                // Remove if exists
                if let Some(coll) = index.get_mut(&collection) {
                    coll.remove(&id);
                }
            } else {
                index
                    .entry(collection)
                    .or_insert_with(HashMap::new)
                    .insert(id, offset);
            }
        }
    }
}

impl Default for PrimaryIndex {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_insert_and_get() {
        let index = PrimaryIndex::new();
        index.insert("users", "user_1", 100);
        index.insert("users", "user_2", 250);

        assert_eq!(index.get("users", "user_1"), Some(100));
        assert_eq!(index.get("users", "user_2"), Some(250));
        assert_eq!(index.get("users", "user_3"), None);
    }

    #[test]
    fn test_remove() {
        let index = PrimaryIndex::new();
        index.insert("users", "user_1", 100);
        assert!(index.contains("users", "user_1"));

        index.remove("users", "user_1");
        assert!(!index.contains("users", "user_1"));
    }

    #[test]
    fn test_collection_count() {
        let index = PrimaryIndex::new();
        index.insert("users", "user_1", 100);
        index.insert("users", "user_2", 200);
        index.insert("products", "prod_1", 300);

        assert_eq!(index.collection_count("users"), 2);
        assert_eq!(index.collection_count("products"), 1);
        assert_eq!(index.total_count(), 3);
    }
}
