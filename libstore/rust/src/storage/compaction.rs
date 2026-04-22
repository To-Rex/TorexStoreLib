use std::collections::HashMap;

use crate::error::StoreResult;
use crate::storage::engine::StorageEngine;
use crate::storage::format::{Record, RecordType};

/// Compaction strategy for reclaiming disk space
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CompactionStrategy {
    /// Compact all collections
    Full,
    /// Compact only specific collection
    Collection(String),
}

/// Statistics about compaction
#[derive(Debug, Clone)]
pub struct CompactionStats {
    /// Number of records before compaction
    pub records_before: usize,
    /// Number of records after compaction
    pub records_after: usize,
    /// Disk space reclaimed in bytes
    pub space_reclaimed: u64,
    /// Number of tombstones removed
    pub tombstones_removed: usize,
    /// Number of duplicates resolved
    pub duplicates_resolved: usize,
}

/// Run compaction on the storage engine
///
/// Compaction removes:
/// - Tombstone records (deleted entries)
/// - Old versions of updated records (keeps only the latest)
/// - Reclaims disk space by rewriting only live records
pub fn compact(storage: &StorageEngine, strategy: CompactionStrategy) -> StoreResult<CompactionStats> {
    let all_records = storage.scan_all()?;

    // Track latest version of each record by (collection, id)
    let mut latest: HashMap<(String, String), (u64, Record)> = HashMap::new();
    let mut tombstones_removed = 0;
    let mut duplicates_resolved = 0;

    for (offset, record) in &all_records {
        let key = (record.collection.clone(), record.id.clone());

        match record.header.record_type {
            RecordType::Insert | RecordType::Update => {
                if let Some((_, existing)) = latest.get(&key) {
                    // Keep the one with higher offset (newer)
                    if *offset > existing.header.timestamp {
                        duplicates_resolved += 1;
                    }
                }
                latest.insert(key, (*offset, record.clone()));
            }
            RecordType::Delete => {
                // Remove from latest if exists (tombstone overrides)
                if latest.remove(&key).is_some() {
                    tombstones_removed += 1;
                }
                tombstones_removed += 1;
            }
            RecordType::CompactionMarker => {}
        }
    }

    // Filter by collection if needed
    let compacted: Vec<Record> = latest
        .into_values()
        .filter_map(|(_, record)| {
            if let CompactionStrategy::Collection(ref coll) = strategy {
                if record.collection != *coll {
                    return None;
                }
            }
            Some(record)
        })
        .collect();

    let records_before = all_records.len();
    let records_after = compacted.len();

    // Calculate old file size
    let old_size = storage.file_size();

    // Write compacted records
    storage.write_compacted(&compacted)?;
    storage.finalize_compaction()?;

    let new_size = storage.file_size();
    let space_reclaimed = old_size.saturating_sub(new_size);

    Ok(CompactionStats {
        records_before,
        records_after,
        space_reclaimed,
        tombstones_removed,
        duplicates_resolved,
    })
}

/// Check if compaction is needed based on fragmentation ratio
pub fn needs_compaction(storage: &StorageEngine, threshold: f64) -> StoreResult<bool> {
    let all_records = storage.scan_all()?;
    if all_records.is_empty() {
        return Ok(false);
    }

    // Count live records vs total records
    let mut live_count = 0;
    let mut seen_keys = std::collections::HashSet::new();

    for (_, record) in all_records.iter().rev() {
        let key = (record.collection.clone(), record.id.clone());
        if seen_keys.contains(&key) {
            continue;
        }
        seen_keys.insert(key);

        if record.header.record_type == RecordType::Insert
            || record.header.record_type == RecordType::Update
        {
            live_count += 1;
        }
    }

    let total = all_records.len();
    if total == 0 {
        return Ok(false);
    }

    let fragmentation = 1.0 - (live_count as f64 / total as f64);
    Ok(fragmentation > threshold)
}
