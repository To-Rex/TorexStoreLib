// Example: torexstore usage
//
// This example demonstrates the core features of the torexstore package:
// - Initializing the database
// - CRUD operations (put, get, update, delete)
// - Querying with filters
// - Watching for changes
// - Compaction

import 'package:torexstore/torexstore.dart';

Future<void> main() async {
  // Create and initialize the database
  final db = TorexStorage();
  await db.init();

  // ─── CRUD Operations ────────────────────────────────────────────────

  // Insert documents
  final doc1 = TorexDocument(
    id: db.generateId(),
    fields: {'name': 'Alice', 'age': 25, 'active': true},
  );
  final doc2 = TorexDocument(
    id: db.generateId(),
    fields: {'name': 'Bob', 'age': 17, 'active': false},
  );
  final doc3 = TorexDocument(
    id: db.generateId(),
    fields: {'name': 'Charlie', 'age': 30, 'active': true},
  );

  await db.put('users', doc1);
  await db.put('users', doc2);
  await db.put('users', doc3);

  // Get a single document
  final user = await db.get('users', doc1.id);
  print('User: ${user?.toMapWithId()}');

  // Update a document
  final updated = TorexDocument(
    id: doc1.id,
    fields: {'name': 'Alice Smith', 'age': 26, 'active': true},
  );
  await db.update('users', updated);

  // Check existence
  final exists = await db.exists('users', doc1.id);
  print('Document exists: $exists');

  // Get all documents
  final allUsers = await db.getAll('users');
  print('All users: ${allUsers.length}');

  // Count documents
  final count = await db.count('users');
  print('User count: $count');

  // ─── Querying ───────────────────────────────────────────────────────

  // Query: users older than 18
  final adults = await db.query('users', QueryFilter.gt('age', 18));
  print('Adults: ${adults.map((d) => d['name']).toList()}');

  // Query: users with name equal to "Bob"
  final bobs = await db.query('users', QueryFilter.eq('name', 'Bob'));
  print('Bobs: ${bobs.length}');

  // Query: range filter (age between 18 and 30)
  final range = await db.query('users', QueryFilter.range('age', 18, 30));
  print('Age 18-30: ${range.map((d) => d['name']).toList()}');

  // Query: AND filter
  final activeAdults = await db.query(
    'users',
    QueryFilter.and([
      QueryFilter.gt('age', 18),
      QueryFilter.eq('active', true),
    ]),
  );
  print('Active adults: ${activeAdults.map((d) => d['name']).toList()}');

  // Query: OR filter
  final youngOrActive = await db.query(
    'users',
    QueryFilter.or([
      QueryFilter.lt('age', 20),
      QueryFilter.eq('active', true),
    ]),
  );
  print('Young or active: ${youngOrActive.map((d) => d['name']).toList()}');

  // ─── Watching for Changes ───────────────────────────────────────────

  final subscription = db.watch('users').listen((event) {
    print('Event: ${event.type} on ${event.collection} -> ${event.id}');
  });

  // Insert a new user (will trigger a watch event)
  final doc4 = TorexDocument(
    id: db.generateId(),
    fields: {'name': 'Diana', 'age': 22, 'active': true},
  );
  await db.put('users', doc4);

  // Wait for the event to be processed
  await Future.delayed(Duration(milliseconds: 100));

  // Cancel the subscription
  await subscription.cancel();

  // ─── Cleanup ────────────────────────────────────────────────────────

  // Delete a document
  await db.delete('users', doc2.id);

  // List all collections
  final collections = await db.collections();
  print('Collections: $collections');

  // Run compaction
  final result = await db.compact();
  print(result);

  // Close the database
  await db.close();
  print('Database closed.');
}
