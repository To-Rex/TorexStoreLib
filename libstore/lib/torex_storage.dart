/// TOREX Storage - High-performance embedded database
///
/// Usage:
/// ```dart
/// final db = TorexStorage();
/// await db.init();
///
/// await db.put('users', TorexDocument(id: 'user_1', fields: {'name': 'Alice', 'age': 25}));
/// final user = await db.get('users', 'user_1');
/// final adults = await db.query('users', QueryFilter.gt('age', 18));
///
/// db.watch('users').listen((event) {
///   print('${event.type}: ${event.id}');
/// });
///
/// await db.close();
/// ```
library libstore;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'src/models/document.dart';
import 'src/models/query_filter.dart';
import 'src/reactive/store_watcher.dart';

export 'src/models/document.dart';
export 'src/models/query_filter.dart';
export 'src/reactive/store_watcher.dart';

/// Main database API class
///
/// Provides a clean, developer-friendly API for all database operations.
/// Uses in-memory storage with file persistence using the same binary format
/// as the Rust core engine.
class TorexStorage {
  static const _dbName = 'torex_data';

  bool _initialized = false;
  String? _path;
  final Map<String, Map<String, Map<String, dynamic>>> _store = {};
  final Map<String, StoreWatcher> _watchers = {};
  final _uuid = const Uuid();

  /// Check if the database is initialized
  bool get isInitialized => _initialized;

  /// Get the database path
  String? get path => _path;

  /// Initialize the database
  ///
  /// If no path is provided, uses the application documents directory.
  /// Loads existing data from disk if available.
  Future<void> init({String? path}) async {
    if (_initialized) return;

    _path = path ?? await _defaultPath();

    // Create directory if it doesn't exist
    final dir = Directory(_path!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Load existing data from disk
    await _loadFromDisk();

    _initialized = true;
  }

  /// Insert a document into a collection
  Future<void> put(String collection, TorexDocument document) async {
    _ensureInitialized();
    _ensureValidCollection(collection);

    final id = document.id;
    final fields = Map<String, dynamic>.from(document.toMap());

    // Store in memory
    _store.putIfAbsent(collection, () => {});
    final isUpdate = _store[collection]!.containsKey(id);
    _store[collection]![id] = fields;

    // Persist to disk
    await _persistCollection(collection);

    // Notify watchers
    final watcher = _watchers[collection];
    if (watcher != null && watcher.isActive) {
      if (isUpdate) {
        watcher.emitUpdate(id, fields);
      } else {
        watcher.emitInsert(id, fields);
      }
    }
  }

  /// Get a document by collection and ID
  Future<TorexDocument?> get(String collection, String id) async {
    _ensureInitialized();

    final fields = _store[collection]?[id];
    if (fields == null) return null;

    return TorexDocument(id: id, fields: Map<String, dynamic>.from(fields));
  }

  /// Update an existing document
  Future<void> update(String collection, TorexDocument document) async {
    _ensureInitialized();

    if (!(_store[collection]?.containsKey(document.id) ?? false)) {
      throw StateError('Document not found: ${document.id}');
    }

    await put(collection, document);
  }

  /// Delete a document
  Future<void> delete(String collection, String id) async {
    _ensureInitialized();

    final removed = _store[collection]?.remove(id);
    if (removed == null) return;

    // Persist changes to disk
    await _persistCollection(collection);

    // Notify watchers
    final watcher = _watchers[collection];
    if (watcher != null && watcher.isActive) {
      watcher.emitDelete(id);
    }
  }

  /// Check if a document exists
  Future<bool> exists(String collection, String id) async {
    _ensureInitialized();
    return _store[collection]?.containsKey(id) ?? false;
  }

  /// Get all documents in a collection
  Future<List<TorexDocument>> getAll(String collection) async {
    _ensureInitialized();

    final collectionData = _store[collection];
    if (collectionData == null || collectionData.isEmpty) return [];

    return collectionData.entries
        .map((e) => TorexDocument(
              id: e.key,
              fields: Map<String, dynamic>.from(e.value),
            ))
        .toList();
  }

  /// Get document count in a collection
  Future<int> count(String collection) async {
    _ensureInitialized();
    return _store[collection]?.length ?? 0;
  }

  /// Get all collection names
  Future<List<String>> collections() async {
    _ensureInitialized();
    return _store.keys
        .where((k) => _store[k]!.isNotEmpty)
        .toList();
  }

  /// Query documents in a collection
  ///
  /// Supports eq, ne, gt, lt, gte, lte, range, and, or, all filter types.
  Future<List<TorexDocument>> query(
    String collection,
    QueryFilter filter,
  ) async {
    _ensureInitialized();

    final allDocs = await getAll(collection);
    return allDocs.where((doc) => _matchesFilter(doc, filter)).toList();
  }

  /// Watch a collection for changes
  Stream<StoreChangeEvent> watch(String collection) {
    _ensureInitialized();

    if (!_watchers.containsKey(collection)) {
      final watcher = StoreWatcher(
        collection: collection,
        onCancel: (subscriptionId) {
          _watchers.remove(collection);
        },
      );

      _watchers[collection] = watcher;
    }

    return _watchers[collection]!.stream;
  }

  /// Run compaction to reclaim disk space
  Future<String> compact() async {
    _ensureInitialized();

    int totalBefore = 0;
    int totalAfter = 0;

    for (final collection in _store.keys.toList()) {
      final data = _store[collection];
      if (data != null && data.isEmpty) {
        // Remove empty collections
        _store.remove(collection);
        final file = _collectionFile(collection);
        if (await file.exists()) {
          await file.delete();
        }
      } else if (data != null) {
        totalBefore += data.length;
        await _persistCollection(collection);
        totalAfter += data.length;
      }
    }

    return 'Compaction complete: $totalAfter records preserved across $totalBefore collections, empty collections removed';
  }

  /// Check if compaction is needed
  Future<bool> needsCompaction({double threshold = 0.3}) async {
    _ensureInitialized();
    // Check if there are empty collections
    return _store.values.any((data) => data.isEmpty);
  }

  /// Generate a new unique ID
  String generateId() => _uuid.v4();

  /// Close the database
  Future<void> close() async {
    if (!_initialized) return;

    // Persist all data before closing
    for (final collection in _store.keys) {
      await _persistCollection(collection);
    }

    // Cancel all watchers
    for (final watcher in _watchers.values) {
      watcher.cancel();
    }
    _watchers.clear();

    _initialized = false;
  }

  // ─── Private Methods ────────────────────────────────────────────────────

  /// Get the default database path
  Future<String> _defaultPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_dbName';
  }

  /// Ensure database is initialized
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'TorexStorage is not initialized. Call init() first.',
      );
    }
  }

  /// Validate collection name
  void _ensureValidCollection(String collection) {
    if (collection.isEmpty) {
      throw ArgumentError('Collection name cannot be empty');
    }
    if (collection.length > 255) {
      throw ArgumentError('Collection name too long (max 255 chars)');
    }
  }

  /// Get file path for a collection
  File _collectionFile(String collection) {
    return File('$_path/$collection.tdb');
  }

  /// Load all data from disk
  Future<void> _loadFromDisk() async {
    final dir = Directory(_path!);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.tdb')) {
        final collectionName = entity.path
            .split('/')
            .last
            .replaceAll('.tdb', '');

        try {
          final bytes = await entity.readAsBytes();
          if (bytes.isEmpty) continue;

          final documents = _deserializeCollection(bytes);
          _store[collectionName] = documents;
        } catch (e) {
          // Skip corrupted files
          continue;
        }
      }
    }
  }

  /// Persist a collection to disk
  Future<void> _persistCollection(String collection) async {
    final data = _store[collection];
    if (data == null || data.isEmpty) {
      // Delete file if collection is empty
      final file = _collectionFile(collection);
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    final bytes = _serializeCollection(data);
    final file = _collectionFile(collection);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// Serialize a collection to binary format
  ///
  /// Format:
  /// [num_docs: u32]
  /// For each doc:
  ///   [id_len: u16][id: bytes][fields_data: bytes with length prefix]
  Uint8List _serializeCollection(Map<String, Map<String, dynamic>> data) {
    final buffer = BytesBuilder();

    // Number of documents
    buffer.add(_uint32ToBytes(data.length));

    for (final entry in data.entries) {
      final id = entry.key;
      final fields = entry.value;

      // Document ID
      final idBytes = Uint8List.fromList(id.codeUnits);
      buffer.add(_uint16ToBytes(idBytes.length));
      buffer.add(idBytes);

      // Fields as binary (using TorexDocument format)
      final doc = TorexDocument(id: id, fields: fields);
      final fieldsBytes = doc.toBytes();
      buffer.add(_uint32ToBytes(fieldsBytes.length));
      buffer.add(fieldsBytes);
    }

    return buffer.toBytes();
  }

  /// Deserialize a collection from binary format
  Map<String, Map<String, dynamic>> _deserializeCollection(Uint8List bytes) {
    final result = <String, Map<String, dynamic>>{};
    int offset = 0;

    // Read number of documents
    final numDocs = _bytesToUint32(bytes, offset);
    offset += 4;

    for (int i = 0; i < numDocs; i++) {
      // Read document ID
      final idLen = _bytesToUint16(bytes, offset);
      offset += 2;

      final id = String.fromCharCodes(bytes.sublist(offset, offset + idLen));
      offset += idLen;

      // Read fields data length
      final fieldsLen = _bytesToUint32(bytes, offset);
      offset += 4;

      // Read and deserialize fields
      final fieldsBytes = bytes.sublist(offset, offset + fieldsLen);
      offset += fieldsLen;

      final fields = TorexDocument.fromBytes(Uint8List.fromList(fieldsBytes));
      result[id] = fields;
    }

    return result;
  }

  /// Check if a document matches a query filter
  bool _matchesFilter(TorexDocument doc, QueryFilter filter) {
    switch (filter.type) {
      case 'all':
        return true;

      case 'eq':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) == 0;

      case 'ne':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) != 0;

      case 'gt':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) > 0;

      case 'lt':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) < 0;

      case 'gte':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) >= 0;

      case 'lte':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) <= 0;

      case 'range':
        final fieldValue = doc[filter.field!];
        return _compareValues(fieldValue, filter.value) >= 0 &&
            _compareValues(fieldValue, filter.value2) < 0;

      case 'and':
        return filter.conditions?.every((f) => _matchesFilter(doc, f)) ?? true;

      case 'or':
        return filter.conditions?.any((f) => _matchesFilter(doc, f)) ?? false;

      default:
        return true;
    }
  }

  /// Compare two dynamic values
  /// Returns negative if a < b, 0 if equal, positive if a > b
  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    // Handle numeric comparisons
    if (a is num && b is num) {
      return a.compareTo(b);
    }

    // Handle string comparisons
    if (a is String && b is String) {
      return a.compareTo(b);
    }

    // Handle bool comparisons
    if (a is bool && b is bool) {
      if (a == b) return 0;
      return a ? 1 : -1;
    }

    // Try to convert to comparable types
    if (a is num && b is num) {
      return a.compareTo(b);
    }

    // Convert int/double for comparison
    if (a is int && b is double) return a.toDouble().compareTo(b);
    if (a is double && b is int) return a.compareTo(b.toDouble());

    return 0;
  }

  // ─── Byte helpers ─────────────────────────────────────────────────────

  static Uint8List _uint32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setUint32(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static int _bytesToUint32(Uint8List data, int offset) {
    return ByteData.sublistView(data, offset, offset + 4)
        .getUint32(0, Endian.little);
  }

  static Uint8List _uint16ToBytes(int value) {
    final bytes = ByteData(2);
    bytes.setUint16(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static int _bytesToUint16(Uint8List data, int offset) {
    return ByteData.sublistView(data, offset, offset + 2)
        .getUint16(0, Endian.little);
  }
}
