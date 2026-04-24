## 1.0.0

**Breaking Changes: Complete API Redesign — Zero-Config Auto-Lifecycle**

- **NEW**: `TorexStore.instance` — Singleton database instance
- **NEW**: Auto-lifecycle management (no init/open/close needed)
- **NEW**: Write-Ahead Log (WAL) for crash-safe writes
- **NEW**: App lifecycle integration (auto-close on background)
- **NEW**: Idle timeout auto-close (resource optimization)
- **NEW**: `TorexStoreConfig` for optional configuration
- **NEW**: `TorexStore.I` short alias for instance
- **DEPRECATED**: `TorexStorage` class (use `TorexStore.instance`)
- **DEPRECATED**: Manual `init()` and `close()` calls (automatic now)

### Migration Guide

```dart
// Before (v0.x)
final db = TorexStorage();
await db.init();
await db.put('users', doc);
await db.close();

// After (v1.0)
final db = TorexStore.instance;
await db.put('users', doc);
// No init. No close. Automatic!
```

## 0.0.1

- Initial release with basic CRUD operations
- Document-based NoSQL storage
- Binary serialization format
- Query filters (eq, ne, gt, lt, gte, lte, range, and, or)
- Collection watchers with real-time streams
- Compaction support
