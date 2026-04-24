import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/document.dart';
import '../models/query_filter.dart';
import '../reactive/store_watcher.dart';
import 'wal.dart';

/// Internal storage engine - handles all low-level storage operations.
///
/// This class is NOT part of the public API. It manages:
/// - In-memory document store
/// - File persistence with binary format
/// - Write-Ahead Log for crash safety
/// - Collection-level file I/O
class StorageEngine {
  static const _dbName = 'torex_data';

  String? _path;
  bool _isOpen = false;
  final Map<String, Map<String, Map<String, dynamic>>> _store = {};
  final Map<String, StoreWatcher> _watchers = {};
  final _uuid = const Uuid();
  WriteAheadLog? _wal;

  /// Whether the engine is currently open and ready
  bool get isOpen => _isOpen;

  /// Get the database path
  String? get path => _path;

  /// Open the storage engine and load data from disk.
  ///
  /// This includes WAL recovery for crash safety.
  Future<void> open({String? path}) async {
    if (_isOpen) return;

    _path = path ?? await _defaultPath();

    final dir = Directory(_path!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Initialize WAL
    _wal = WriteAheadLog(_path!);
    await _wal!.init();

    // Load existing data from disk
    await _loadFromDisk();

    // Recover from WAL (crash recovery)
    await _recoverFromWAL();

    _isOpen = true;
  }

  /// Close the engine, persisting all data first.
  ///
  /// This is internal-only - never exposed to developers.
  Future<void> close() async {
    if (!_isOpen) return;

    // Persist all data before closing
    for (final collection in _store.keys.toList()) {
      await _persistCollection(collection);
    }

    // Clear WAL (all data is persisted)
    await _wal?.clear();

    // Cancel all watchers
    for (final watcher in _watchers.values) {
      watcher.cancel();
    }
    _watchers.clear();

    _isOpen = false;
  }

  /// Insert or update a document
  Future<void> put(String collection, TorexDocument document) async {
    _ensureOpen();
    _ensureValidCollection(collection);

    final id = document.id;
    final fields = Map<String, dynamic>.from(document.toMap());

    // Write to WAL first (crash safety)
    final seq = await _wal!.logWrite(collection, id, fields);

    // Store in memory
    _store.putIfAbsent(collection, () => {});
    final isUpdate = _store[collection]!.containsKey(id);
    _store[collection]![id] = fields;

    // Persist to disk
    await _persistCollection(collection);

    // Commit WAL entry
    await _wal!.commit(seq);

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
    _ensureOpen();
    final fields = _store[collection]?[id];
    if (fields == null) return null;
    return TorexDocument(id: id, fields: Map<String, dynamic>.from(fields));
  }

  /// Update an existing document
  Future<void> update(String collection, TorexDocument document) async {
    _ensureOpen();
    if (!(_store[collection]?.containsKey(document.id) ?? false)) {
      throw StateError('Document not found: ${document.id}');
    }
    await put(collection, document);
  }

  /// Delete a document
  Future<void> delete(String collection, String id) async {
    _ensureOpen();

    final removed = _store[collection]?.remove(id);
    if (removed == null) return;

    // WAL log the delete
    final seq = await _wal!.logDelete(collection, id);

    // Persist changes
    await _persistCollection(collection);

    // Commit WAL
    await _wal!.commit(seq);

    // Notify watchers
    final watcher = _watchers[collection];
    if (watcher != null && watcher.isActive) {
      watcher.emitDelete(id);
    }
  }

  /// Check if a document exists
  Future<bool> exists(String collection, String id) async {
    _ensureOpen();
    return _store[collection]?.containsKey(id) ?? false;
  }

  /// Get all documents in a collection
  Future<List<TorexDocument>> getAll(String collection) async {
    _ensureOpen();
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
    _ensureOpen();
    return _store[collection]?.length ?? 0;
  }

  /// Get all collection names
  Future<List<String>> collections() async {
    _ensureOpen();
    return _store.keys.where((k) => _store[k]!.isNotEmpty).toList();
  }

  /// Query documents with a filter
  Future<List<TorexDocument>> query(
    String collection,
    QueryFilter filter,
  ) async {
    _ensureOpen();
    final allDocs = await getAll(collection);
    return allDocs.where((doc) => _matchesFilter(doc, filter)).toList();
  }

  /// Watch a collection for changes
  Stream<StoreChangeEvent> watch(String collection) {
    _ensureOpen();
    if (!_watchers.containsKey(collection)) {
      _watchers[collection] = StoreWatcher(
        collection: collection,
        onCancel: (_) => _watchers.remove(collection),
      );
    }
    return _watchers[collection]!.stream;
  }

  /// Run compaction
  Future<String> compact() async {
    _ensureOpen();
    int totalAfter = 0;

    for (final collection in _store.keys.toList()) {
      final data = _store[collection];
      if (data != null && data.isEmpty) {
        _store.remove(collection);
        final file = _collectionFile(collection);
        if (await file.exists()) await file.delete();
      } else if (data != null) {
        totalAfter += data.length;
        await _persistCollection(collection);
      }
    }

    return 'Compaction complete: $totalAfter records preserved, empty collections removed';
  }

  /// Check if compaction is needed
  Future<bool> needsCompaction() async {
    _ensureOpen();
    return _store.values.any((data) => data.isEmpty);
  }

  /// Generate a unique ID
  String generateId() => _uuid.v4();

  // ─── Private Methods ────────────────────────────────────────────────────

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('StorageEngine is not open');
    }
  }

  void _ensureValidCollection(String collection) {
    if (collection.isEmpty) {
      throw ArgumentError('Collection name cannot be empty');
    }
    if (collection.length > 255) {
      throw ArgumentError('Collection name too long (max 255 chars)');
    }
  }

  Future<String> _defaultPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_dbName';
  }

  File _collectionFile(String collection) => File('$_path/$collection.tdb');

  /// Recover from WAL after a crash.
  /// Replays any uncommitted WAL entries into the in-memory store.
  Future<void> _recoverFromWAL() async {
    final count = await _wal!.replay((collection, docId, op, fields) {
      _store.putIfAbsent(collection, () => {});

      if (op == WalOperation.put && fields != null) {
        _store[collection]![docId] = Map.from(fields);
      } else if (op == WalOperation.delete) {
        _store[collection]?.remove(docId);
      }
    });

    if (count > 0) {
      // Persist recovered data
      for (final collection in _store.keys.toList()) {
        await _persistCollection(collection);
      }
    }
  }

  Future<void> _loadFromDisk() async {
    final dir = Directory(_path!);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.tdb')) {
        final collectionName =
            entity.path.split('/').last.replaceAll('.tdb', '');
        try {
          final bytes = await entity.readAsBytes();
          if (bytes.isEmpty) continue;
          _store[collectionName] = _deserializeCollection(bytes);
        } catch (_) {
          continue; // Skip corrupted files
        }
      }
    }
  }

  Future<void> _persistCollection(String collection) async {
    final data = _store[collection];
    if (data == null || data.isEmpty) {
      final file = _collectionFile(collection);
      if (await file.exists()) await file.delete();
      return;
    }
    final bytes = _serializeCollection(data);
    await _collectionFile(collection).writeAsBytes(bytes, flush: true);
  }

  /// Serialize collection to binary format
  Uint8List _serializeCollection(Map<String, Map<String, dynamic>> data) {
    final buffer = BytesBuilder();
    buffer.add(_uint32ToBytes(data.length));

    for (final entry in data.entries) {
      final idBytes = Uint8List.fromList(entry.key.codeUnits);
      buffer.add(_uint16ToBytes(idBytes.length));
      buffer.add(idBytes);

      final doc = TorexDocument(id: entry.key, fields: entry.value);
      final fieldsBytes = doc.toBytes();
      buffer.add(_uint32ToBytes(fieldsBytes.length));
      buffer.add(fieldsBytes);
    }

    return buffer.toBytes();
  }

  /// Deserialize collection from binary format
  Map<String, Map<String, dynamic>> _deserializeCollection(Uint8List bytes) {
    final result = <String, Map<String, dynamic>>{};
    int offset = 0;

    final numDocs = _bytesToUint32(bytes, offset);
    offset += 4;

    for (int i = 0; i < numDocs; i++) {
      final idLen = _bytesToUint16(bytes, offset);
      offset += 2;
      final id = String.fromCharCodes(bytes.sublist(offset, offset + idLen));
      offset += idLen;

      final fieldsLen = _bytesToUint32(bytes, offset);
      offset += 4;
      final fieldsBytes = bytes.sublist(offset, offset + fieldsLen);
      offset += fieldsLen;

      result[id] = TorexDocument.fromBytes(Uint8List.fromList(fieldsBytes));
    }

    return result;
  }

  /// Check if a document matches a query filter
  bool _matchesFilter(TorexDocument doc, QueryFilter filter) {
    switch (filter.type) {
      case 'all':
        return true;
      case 'eq':
        return _compareValues(doc[filter.field!], filter.value) == 0;
      case 'ne':
        return _compareValues(doc[filter.field!], filter.value) != 0;
      case 'gt':
        return _compareValues(doc[filter.field!], filter.value) > 0;
      case 'lt':
        return _compareValues(doc[filter.field!], filter.value) < 0;
      case 'gte':
        return _compareValues(doc[filter.field!], filter.value) >= 0;
      case 'lte':
        return _compareValues(doc[filter.field!], filter.value) <= 0;
      case 'range':
        return _compareValues(doc[filter.field!], filter.value) >= 0 &&
            _compareValues(doc[filter.field!], filter.value2) < 0;
      case 'and':
        return filter.conditions?.every((f) => _matchesFilter(doc, f)) ?? true;
      case 'or':
        return filter.conditions?.any((f) => _matchesFilter(doc, f)) ?? false;
      default:
        return true;
    }
  }

  int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
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
