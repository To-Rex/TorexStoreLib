# TOREX Storage

[![pub package](https://img.shields.io/pub/v/torexstore.svg)](https://pub.dev/packages/torexstore)

High-performance, production-ready embedded NoSQL database for Flutter, powered by Rust via `flutter_rust_bridge`.

TOREX Storage provides a clean, developer-friendly Dart API for all database operations — CRUD, queries, reactive watching, and compaction — with a Rust core engine that guarantees memory safety, thread safety, and minimal disk I/O.

## Features

- **CRUD Operations** — `put`, `get`, `update`, `delete` with O(1) primary lookups
- **Binary Storage** — Append-only log file with custom binary format and CRC32 checksums
- **Primary Index** — HashMap-based `(collection, id) → offset` for O(1) lookups
- **Secondary Indexes** — BTreeMap-based for range queries and sorted access
- **Query Engine** — Supports `==`, `!=`, `>`, `<`, `>=`, `<=`, range queries
- **Query Optimizer** — Automatically selects best execution plan (index scan vs full scan)
- **Reactive System** — Watch collections with Dart `Stream` for real-time updates
- **Compaction** — Reclaims disk space by removing tombstones and old versions
- **Thread Safety** — All operations are thread-safe using `parking_lot` locks

## Installation

Add `torexstore` to your `pubspec.yaml`:

```yaml
dependencies:
  torexstore: ^0.0.1
```

Then run:

```bash
flutter pub get
```

### Prerequisites

- **Flutter** >= 3.11.5
- **Rust** — Install via [rustup](https://rustup.rs/)
- **flutter_rust_bridge** CLI:

```bash
cargo install flutter_rust_bridge_codegen
```

### Build Steps

After adding the dependency, generate the bridge code and build the Rust library:

```bash
# Generate flutter_rust_bridge code
cd torexstore
flutter_rust_bridge_codegen generate

# Build the Rust native library
cd rust
cargo build --release
```

Then run your Flutter app:

```bash
flutter run
```

## Quick Start

### 1. Import and Initialize

```dart
import 'package:torexstore/torexstore.dart';

void main() async {
  final db = TorexStorage();
  await db.init();

  // ... use the database ...

  await db.close();
}
```

> **Note:** `init()` must be called before any other operation. If no custom path is provided, data is stored in the application documents directory.

### 2. CRUD Operations

#### Insert a Document

```dart
final user = TorexDocument(id: 'user_1', fields: {
  'name': 'Alice',
  'age': 25,
  'city': 'Tashkent',
  'active': true,
});
await db.put('users', user);
```

#### Get a Document

```dart
final doc = await db.get('users', 'user_1');
if (doc != null) {
  print(doc['name']); // Alice
  print(doc['age']);  // 25
}
```

#### Update a Document

```dart
final updated = TorexDocument(id: 'user_1', fields: {
  'name': 'Alice Smith',
  'age': 26,
  'city': 'Tashkent',
  'active': true,
});
await db.update('users', updated);
```

> **Note:** `update()` throws a `StateError` if the document does not exist.

#### Delete a Document

```dart
await db.delete('users', 'user_1');
```

#### Check Existence

```dart
final exists = await db.exists('users', 'user_1');
print(exists); // true or false
```

### 3. Query Documents

The `QueryFilter` class provides a fluent API for constructing queries:

#### Equality Filter

```dart
final results = await db.query('users', QueryFilter.eq('city', 'Tashkent'));
```

#### Comparison Filters

```dart
// Greater than
final adults = await db.query('users', QueryFilter.gt('age', 18));

// Less than
final minors = await db.query('users', QueryFilter.lt('age', 18));

// Greater than or equal
final eligible = await db.query('users', QueryFilter.gte('age', 18));

// Less than or equal
final seniors = await db.query('users', QueryFilter.lte('age', 65));

// Not equal
final nonLocal = await db.query('users', QueryFilter.ne('city', 'Tashkent'));
```

#### Range Query

```dart
// age >= 18 AND age < 30
final youngAdults = await db.query('users',
  QueryFilter.range('age', 18, 30));
```

#### Combined Filters (AND / OR)

```dart
// AND — all conditions must match
final results = await db.query('users', QueryFilter.and([
  QueryFilter.gt('age', 18),
  QueryFilter.eq('city', 'Tashkent'),
]));

// OR — at least one condition must match
final results = await db.query('users', QueryFilter.or([
  QueryFilter.eq('city', 'Tashkent'),
  QueryFilter.eq('city', 'Samarkand'),
]));
```

#### Match All Documents

```dart
final allUsers = await db.query('users', QueryFilter.all);
```

### 4. Collection Operations

#### Get All Documents

```dart
final allDocs = await db.getAll('users');
for (final doc in allDocs) {
  print('${doc.id}: ${doc['name']}');
}
```

#### Count Documents

```dart
final count = await db.count('users');
print('Total users: $count');
```

#### List All Collections

```dart
final names = await db.collections();
print('Collections: $names'); // ['users', 'products', ...]
```

### 5. Watch Collection Changes

Use `watch()` to get a `Stream<StoreChangeEvent>` that emits real-time events when documents are inserted, updated, or deleted:

```dart
db.watch('users').listen((event) {
  switch (event.type) {
    case StoreEventType.insert:
      print('Inserted: ${event.id}, data: ${event.data}');
      break;
    case StoreEventType.update:
      print('Updated: ${event.id}, data: ${event.data}');
      break;
    case StoreEventType.delete:
      print('Deleted: ${event.id}');
      break;
  }
});
```

> **Note:** `event.data` is `null` for delete events.

### 6. Maintenance

#### Compaction

Reclaim disk space by removing empty collections and rewriting data files:

```dart
final result = await db.compact();
print(result);

// Check if compaction is needed
final needed = await db.needsCompaction(threshold: 0.3);
```

#### Generate Unique IDs

```dart
final id = db.generateId(); // UUID v4
```

#### Close the Database

```dart
await db.close(); // Persists all data and cancels watchers
```

## API Reference

### `TorexStorage`

| Method | Return Type | Description |
|--------|-------------|-------------|
| `init({String? path})` | `Future<void>` | Initialize the database. Loads existing data from disk. |
| `put(String collection, TorexDocument doc)` | `Future<void>` | Insert or overwrite a document. |
| `get(String collection, String id)` | `Future<TorexDocument?>` | Get a document by ID. Returns `null` if not found. |
| `update(String collection, TorexDocument doc)` | `Future<void>` | Update an existing document. Throws if not found. |
| `delete(String collection, String id)` | `Future<void>` | Delete a document by ID. |
| `exists(String collection, String id)` | `Future<bool>` | Check if a document exists. |
| `getAll(String collection)` | `Future<List<TorexDocument>>` | Get all documents in a collection. |
| `count(String collection)` | `Future<int>` | Get the number of documents in a collection. |
| `collections()` | `Future<List<String>>` | Get all non-empty collection names. |
| `query(String collection, QueryFilter filter)` | `Future<List<TorexDocument>>` | Query documents with a filter. |
| `watch(String collection)` | `Stream<StoreChangeEvent>` | Watch a collection for real-time changes. |
| `compact()` | `Future<String>` | Run compaction to reclaim disk space. |
| `needsCompaction({double threshold})` | `Future<bool>` | Check if compaction is recommended. |
| `generateId()` | `String` | Generate a new UUID v4. |
| `close()` | `Future<void>` | Persist data, cancel watchers, and close the database. |

### `TorexDocument`

| Property / Method | Type | Description |
|---|---|---|
| `id` | `String` | Unique document identifier. |
| `fields` | `Map<String, dynamic>` | Document field data (via constructor). |
| `operator [](String key)` | `dynamic` | Get a field value by name. |
| `keys` | `Iterable<String>` | All field names. |
| `values` | `Iterable<dynamic>` | All field values. |
| `entries` | `Iterable<MapEntry>` | All field entries. |
| `containsKey(String key)` | `bool` | Check if a field exists. |
| `length` | `int` | Number of fields. |
| `isEmpty` | `bool` | Whether the document has no fields. |
| `toMap()` | `Map<String, dynamic>` | Convert to a plain map (without `id`). |
| `toMapWithId()` | `Map<String, dynamic>` | Convert to a map including `id`. |
| `toBytes()` | `Uint8List` | Serialize to binary format. |
| `TorexDocument.fromMap(id, map)` | `TorexDocument` | Create from a map. |
| `TorexDocument.fromBytes(data)` | `Map<String, dynamic>` | Deserialize fields from binary. |

### `QueryFilter`

| Factory Constructor | Description |
|---|---|
| `QueryFilter.eq(field, value)` | Equal to |
| `QueryFilter.ne(field, value)` | Not equal to |
| `QueryFilter.gt(field, value)` | Greater than |
| `QueryFilter.lt(field, value)` | Less than |
| `QueryFilter.gte(field, value)` | Greater than or equal |
| `QueryFilter.lte(field, value)` | Less than or equal |
| `QueryFilter.range(field, start, end)` | Range (inclusive start, exclusive end) |
| `QueryFilter.and(List<QueryFilter>)` | Logical AND |
| `QueryFilter.or(List<QueryFilter>)` | Logical OR |
| `QueryFilter.all` | Match all documents |

### `StoreChangeEvent`

| Property | Type | Description |
|---|---|---|
| `type` | `StoreEventType` | `insert`, `update`, or `delete` |
| `collection` | `String` | Collection name |
| `id` | `String` | Document ID |
| `data` | `Map<String, dynamic>?` | Document data (`null` for delete) |

### `StoreEventType`

```dart
enum StoreEventType { insert, update, delete }
```

## Supported Field Types

`TorexDocument` fields support the following Dart types:

| Dart Type | Binary Type ID | Storage Size |
|-----------|---------------|--------------|
| `null` | 0 | 1 byte |
| `String` | 1 | 4 + len bytes |
| `int` | 2 | 8 bytes (i64) |
| `double` | 3 | 8 bytes (f64) |
| `bool` | 4 | 1 byte |

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| `put` | O(1) + disk write | Append to log + update index |
| `get` | O(1) | Primary index lookup + single disk read |
| `update` | O(1) + disk write | Append new version + update index |
| `delete` | O(1) + disk write | Write tombstone + remove from index |
| `query` (indexed) | O(log n) | Secondary index BTreeMap lookup |
| `query` (full scan) | O(n) | Scan all records in collection |
| `watch` | O(k) | k = number of watchers for collection |

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:torexstore/torexstore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = TorexStorage();
  await db.init();

  // Generate unique ID
  final userId = db.generateId();

  // Insert
  await db.put('users', TorexDocument(id: userId, fields: {
    'name': 'Alice',
    'age': 25,
    'city': 'Tashkent',
  }));

  // Read
  final user = await db.get('users', userId);
  print('User: ${user?['name']}');

  // Query
  final locals = await db.query('users', QueryFilter.eq('city', 'Tashkent'));
  print('Local users: ${locals.length}');

  // Watch changes
  db.watch('users').listen((event) {
    print('${event.type}: ${event.id}');
  });

  // Update
  await db.update('users', TorexDocument(id: userId, fields: {
    'name': 'Alice Smith',
    'age': 26,
    'city': 'Samarkand',
  }));

  // Delete
  await db.delete('users', userId);

  // Compact and close
  await db.compact();
  await db.close();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('TOREX Storage Example')),
      ),
    );
  }
}
```

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Core Engine | Rust |
| Bridge | flutter_rust_bridge ^2.12.0 |
| Serialization | Custom binary (bincode-compatible) |
| Checksums | CRC32 (crc32fast) |
| Concurrency | parking_lot, dashmap, crossbeam-channel |
| Flutter | Dart, path_provider, uuid |

## License

BSD-3-Clause
