# TOREX Store

Flutter application demonstrating the TOREX Storage embedded database library.

## Overview

This project uses **torexstore** — a high-performance embedded database library built with **Rust** and **flutter_rust_bridge**. The main Flutter app contains only UI logic; all database operations are handled by the torexstore library.

## Project Structure

```
torexstore/
├── lib/
│   └── main.dart              # UI only - uses TorexStorage API
├── torexstore/                  # Embedded database library
│   ├── rust/                  # Rust core engine
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs         # Bridge API
│   │       ├── db.rs          # Database facade
│   │       ├── error.rs       # Error types
│   │       ├── storage/       # Append-only binary storage
│   │       ├── index/         # Primary & secondary indexes
│   │       ├── query/         # Query engine & optimizer
│   │       └── reactive/      # Watch/stream system
│   ├── lib/                   # Dart API layer
│   │   ├── torex_storage.dart # Main public API
│   │   └── src/
│   │       ├── models/        # Document & query models
│   │       ├── reactive/      # Stream-based watcher
│   │       └── bridge/        # Generated bridge code
│   ├── pubspec.yaml
│   └── README.md              # Detailed documentation
├── pubspec.yaml
└── README.md                  # This file
```

## Getting Started

1. Install Rust: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
2. Install flutter_rust_bridge: `cargo install flutter_rust_bridge_codegen`
3. Generate bridge code: `cd torexstore && flutter_rust_bridge_codegen generate`
4. Run the app: `flutter run`

## Usage Example

```dart
import 'package:torexstore/torexstore.dart';

final db = TorexStorage();
await db.init();

// CRUD
await db.put('users', TorexDocument(id: 'user_1', fields: {'name': 'Alice', 'age': 25}));
final user = await db.get('users', 'user_1');
await db.delete('users', 'user_1');

// Query
final adults = await db.query('users', QueryFilter.gt('age', 18));

// Watch changes
db.watch('users').listen((event) {
  print('${event.type}: ${event.id}');
});

await db.close();
```

See [torexstore/README.md](torexstore/README.md) for full documentation.
