// Example: TorexStore - Zero-config embedded database
//
// No init. No open. No close.
// Just use the database and it handles everything automatically.

import 'package:flutter/material.dart';
import 'package:torexstore/torexstore.dart';

void main() {
  // Optional: configure before first use (uses sensible defaults if skipped)
  TorexStore.configure(const TorexStoreConfig(
    idleTimeout: Duration(minutes: 5),
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TorexStore Demo',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const DatabaseDemo(),
    );
  }
}

class DatabaseDemo extends StatefulWidget {
  const DatabaseDemo({super.key});

  @override
  State<DatabaseDemo> createState() => _DatabaseDemoState();
}

class _DatabaseDemoState extends State<DatabaseDemo> {
  final db = TorexStore.instance;
  List<TorexDocument> _users = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    _users = await db.getAll('users');
    setState(() => _loading = false);
  }

  Future<void> _addUser(String name, int age) async {
    await db.put('users', TorexDocument(
      id: db.generateId(),
      fields: {'name': name, 'age': age, 'active': true},
    ));
    await _loadUsers();
  }

  Future<void> _deleteUser(String id) async {
    await db.delete('users', id);
    await _loadUsers();
  }

  Future<void> _queryAdults() async {
    final adults = await db.query('users', QueryFilter.gt('age', 18));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adults: ${adults.map((d) => d['name']).join(', ')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TorexStore Demo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  title: Text(user['name'] ?? 'Unknown'),
                  subtitle: Text('Age: ${user['age']}, Active: ${user['active']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteUser(user.id),
                  ),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => _addUser('User ${_users.length + 1}', 20 + _users.length),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'query',
            onPressed: _queryAdults,
            child: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }
}

// ─── Minimal API Demo (non-Flutter) ─────────────────────────────────────

/// Simple demonstration of the zero-config API:
///
/// ```dart
/// final db = TorexStore.instance;
///
/// // Write - no init needed
/// await db.put('users', TorexDocument(
///   id: 'user_1',
///   fields: {'name': 'Alice', 'age': 25},
/// ));
///
/// // Read - always available
/// final user = await db.get('users', 'user_1');
/// print(user?['name']); // Alice
///
/// // Query
/// final adults = await db.query('users', QueryFilter.gt('age', 18));
///
/// // Watch for changes
/// db.watch('users').listen((event) {
///   print('${event.type}: ${event.id}');
/// });
///
/// // No close needed - automatic lifecycle management!
/// ```
///
/// The database:
/// - Auto-opens on first use
/// - Auto-closes when app goes to background
/// - Auto-reopens when app returns to foreground
/// - Auto-closes after 30s idle (configurable)
/// - Never loses data (crash-safe WAL)
/// - Uses singleton pattern (one instance per app)
