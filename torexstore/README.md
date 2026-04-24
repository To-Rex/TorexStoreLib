# TorexStore

**Zero-config, production-ready embedded NoSQL database for Flutter.**

> No init. No open. No close. Just use it.

```dart
final db = TorexStore.instance;

await db.put('users', TorexDocument(id: '1', fields: {'name': 'Alice', 'age': 25}));
final user = await db.get('users', '1');
```

## ✨ Features

- 🚀 **Zero-config** — No initialization, no open/close calls
- 🔄 **Auto-lifecycle** — Opens on first use, closes on background/idle
- 🛡️ **Crash-safe** — Write-Ahead Log (WAL) ensures no data loss
- 📱 **Mobile-optimized** — Flutter app lifecycle integration
- ⚡ **High-performance** — In-memory store with binary persistence
- 🔍 **Query engine** — Filters: eq, ne, gt, lt, gte, lte, range, and, or
- 👁️ **Reactive** — Watch collections for real-time change notifications
- 🗄️ **Singleton** — One instance per app, thread-safe
- 📦 **Lightweight** — Minimal dependencies

## 🚀 Quick Start

### Installation

```yaml
dependencies:
  torexstore: ^1.0.0
```

### Basic Usage

```dart
import 'package:torexstore/torexstore.dart';

// Get the singleton instance
final db = TorexStore.instance;

// Write — auto-opens on first use
await db.put('users', TorexDocument(
  id: db.generateId(),
  fields: {'name': 'Alice', 'age': 25, 'active': true},
));

// Read — always available
final user = await db.get('users', 'user_1');
print(user?['name']); // Alice

// That's it. No close needed.
```

## 📖 API Reference

### CRUD Operations

```dart
final db = TorexStore.instance;

// Create / Update
await db.put('users', TorexDocument(id: '1', fields: {'name': 'Alice'}));

// Read
final doc = await db.get('users', '1');

// Update
await db.update('users', TorexDocument(id: '1', fields: {'name': 'Alice Smith'}));

// Delete
await db.delete('users', '1');

// Check existence
final exists = await db.exists('users', '1');

// Get all documents
final allUsers = await db.getAll('users');

// Count documents
final count = await db.count('users');

// List collections
final collections = await db.collections();
```

### Querying

```dart
// Comparison filters
final adults = await db.query('users', QueryFilter.gt('age', 18));
final alices = await db.query('users', QueryFilter.eq('name', 'Alice'));

// Range filter
final range = await db.query('users', QueryFilter.range('age', 18, 30));

// Logical filters
final activeAdults = await db.query('users', QueryFilter.and([
  QueryFilter.gt('age', 18),
  QueryFilter.eq('active', true),
]));

final youngOrActive = await db.query('users', QueryFilter.or([
  QueryFilter.lt('age', 20),
  QueryFilter.eq('active', true),
]));

// Match all
final all = await db.query('users', QueryFilter.all);
```

### Reactive Watching

```dart
// Watch a collection for real-time changes
db.watch('users').listen((event) {
  switch (event.type) {
    case StoreEventType.insert:
      print('Inserted: ${event.id}');
    case StoreEventType.update:
      print('Updated: ${event.id}');
    case StoreEventType.delete:
      print('Deleted: ${event.id}');
  }
});
```

### ID Generation

```dart
final id = db.generateId(); // UUID v4
```

### Compaction

```dart
// Reclaim disk space
final result = await db.compact();
print(result);

// Check if compaction is needed
if (await db.needsCompaction()) {
  await db.compact();
}
```

## ⚙️ Configuration (Optional)

```dart
void main() {
  // Optional: configure before first use
  TorexStore.configure(const TorexStoreConfig(
    idleTimeout: Duration(minutes: 5),  // Auto-close after 5 min idle
    customPath: '/custom/db/path',       // Custom storage path
  ));

  runApp(MyApp());
}
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `idleTimeout` | 30 seconds | Inactivity duration before auto-close. Set `Duration.zero` to disable. |
| `customPath` | App documents dir | Custom database file path. |

## 🏗️ Architecture

### Auto-Lifecycle System

```
┌─────────────────────────────────────────────────────┐
│                    TorexStore (Singleton)            │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │   Public API  │  │  Lifecycle   │  │    WAL    │ │
│  │ put/get/query │  │  Manager     │  │ (Crash    │ │
│  │ watch/delete  │  │ (Auto-open/  │  │  Safety)  │ │
│  │               │  │  close/      │  │           │ │
│  │               │  │  idle)       │  │           │ │
│  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘ │
│         │                 │                 │       │
│  ┌──────▼─────────────────▼─────────────────▼─────┐ │
│  │              Storage Engine                     │ │
│  │  ┌─────────────┐  ┌──────────────────────────┐ │ │
│  │  │  In-Memory  │  │  Binary File Persistence │ │ │
│  │  │    Store    │  │  (.tdb per collection)   │ │ │
│  │  └─────────────┘  └──────────────────────────┘ │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### How It Works

1. **Lazy Init**: On first `put()`/`get()`, the engine auto-opens
2. **Always-Available**: If the engine was closed (idle/background), it auto-reopens
3. **App Lifecycle**: When app goes to background → auto-persist and close
4. **Idle Timeout**: After 30s of no activity → auto-close to save resources
5. **Crash Safety**: Every write goes to WAL first, then main storage, then WAL is cleared
6. **Recovery**: On next open after crash, WAL entries are replayed

### Write-Ahead Log (WAL)

Every mutation follows this sequence:

```
1. Write to WAL (append-only file)
2. Apply to in-memory store
3. Persist to main storage file
4. Clear WAL entry (commit)
```

If the app crashes between steps 1-4, the WAL entry survives and is
replayed on next open, ensuring zero data loss.

## 🔄 Migration from v0.x

```dart
// Before (v0.x) — manual lifecycle
final db = TorexStorage();
await db.init();
await db.put('users', doc);
await db.close(); // Had to remember this!

// After (v1.x) — zero-config
final db = TorexStore.instance;
await db.put('users', doc);
// No init. No close. Automatic!
```

## 📄 License

BSD-3-Clause
