## 0.1.0

- Initial release.
- CRUD operations: `put`, `get`, `update`, `delete`, `exists`.
- Collection operations: `getAll`, `count`, `collections`.
- Query engine with filters: `eq`, `ne`, `gt`, `lt`, `gte`, `lte`, `range`, `and`, `or`, `all`.
- Reactive watching via Dart `Stream` (`watch`).
- Binary storage with custom format and CRC32 checksums.
- Primary index (HashMap) for O(1) lookups.
- Secondary indexes (BTreeMap) for range queries.
- Query optimizer (index scan vs full scan).
- Compaction for disk space reclamation.
- Thread-safe operations via `parking_lot` locks.
