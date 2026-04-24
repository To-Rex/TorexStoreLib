/// TOREX Store - Zero-config embedded database for Flutter.
///
/// **No init. No open. No close.**
///
/// Usage:
/// ```dart
/// final db = TorexStore.instance;
///
/// await db.put('users', TorexDocument(id: 'user_1', fields: {'name': 'Alice'}));
/// final user = await db.get('users', 'user_1');
/// ```
///
/// The database lifecycle is fully automatic:
/// - Lazy initialization on first use
/// - Auto-reopen if closed (always-available API)
/// - Auto-close on app background (lifecycle integration)
/// - Idle timeout auto-close (resource optimization)
/// - Crash-safe writes via WAL (no data loss)
/// - Singleton instance (prevent multiple DB instances)
library torexstore;

import 'dart:async';

import 'src/engine/lifecycle_manager.dart';
import 'src/engine/storage_engine.dart';
import 'src/models/document.dart';
import 'src/models/query_filter.dart';
import 'src/reactive/store_watcher.dart';

export 'src/models/document.dart';
export 'src/models/query_filter.dart';
export 'src/reactive/store_watcher.dart';

/// Production-ready embedded database with fully automatic lifecycle.
///
/// ## Key Design Principles
///
/// 1. **Zero-config**: No init/open/close required
/// 2. **Always-available**: Auto-reopens if closed
/// 3. **Crash-safe**: WAL ensures no data loss
/// 4. **Resource-efficient**: Auto-closes on idle/background
/// 5. **Singleton**: Single instance prevents conflicts
///
/// ## Usage
///
/// ```dart
/// final db = TorexStore.instance;
///
/// // Just use it - no initialization needed
/// await db.put('key', TorexDocument(id: '1', fields: {'value': 'hello'}));
/// final doc = await db.get('key', '1');
/// ```
class TorexStore {
  // ─── Singleton ──────────────────────────────────────────────────────────

  static TorexStore? _instance;

  /// Configuration for the database instance.
  static TorexStoreConfig _config = const TorexStoreConfig();

  /// Whether the singleton has been configured.
  static bool _configured = false;

  /// Get the singleton database instance.
  ///
  /// On first access, the database is not yet open. It will auto-open
  /// on the first operation (lazy initialization).
  static TorexStore get instance {
    _instance ??= TorexStore._();
    return _instance!;
  }

  /// Short alias for [instance].
  static TorexStore get I => instance;

  /// Configure the database before first use.
  ///
  /// Call this optionally in `main()` to customize behavior.
  /// If not called, sensible defaults are used.
  ///
  /// ```dart
  /// void main() {
  ///   TorexStore.configure(TorexStoreConfig(
  ///     idleTimeout: Duration(minutes: 5),
  ///     customPath: '/path/to/db',
  ///   ));
  ///   runApp(MyApp());
  /// }
  /// ```
  static void configure(TorexStoreConfig config) {
    if (_configured && _instance != null) {
      // Already in use - config change will apply on next reopen
    }
    _config = config;
    _configured = true;
  }

  /// Reset the singleton (for testing only).
  static Future<void> reset() async {
    if (_instance != null) {
      await _instance!._engine.close();
      _instance!._lifecycle.dispose();
      _instance = null;
    }
    _configured = false;
    _config = const TorexStoreConfig();
  }

  // ─── Instance Fields ────────────────────────────────────────────────────

  final StorageEngine _engine = StorageEngine();
  final LifecycleManager _lifecycle;

  /// Mutex for ensuring only one initialization runs at a time.
  Completer<void>? _initCompleter;

  // ─── Private Constructor ────────────────────────────────────────────────

  TorexStore._()
      : _lifecycle = LifecycleManager(
          idleTimeout: _config.idleTimeout,
        ) {
    _lifecycle.onSuspend = _onLifecycleSuspend;
    _lifecycle.onResume = _onLifecycleResume;
    _lifecycle.attach();
  }

  // ─── Always-Available Public API ────────────────────────────────────────

  /// Insert or update a document in a collection.
  ///
  /// ```dart
  /// await db.put('users', TorexDocument(id: '1', fields: {'name': 'Alice'}));
  /// ```
  Future<void> put(String collection, TorexDocument document) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    await _engine.put(collection, document);
  }

  /// Get a document by collection and ID.
  ///
  /// Returns `null` if the document doesn't exist.
  ///
  /// ```dart
  /// final user = await db.get('users', '1');
  /// ```
  Future<TorexDocument?> get(String collection, String id) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.get(collection, id);
  }

  /// Update an existing document.
  ///
  /// Throws [StateError] if the document doesn't exist.
  Future<void> update(String collection, TorexDocument document) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    await _engine.update(collection, document);
  }

  /// Delete a document from a collection.
  Future<void> delete(String collection, String id) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    await _engine.delete(collection, id);
  }

  /// Check if a document exists.
  Future<bool> exists(String collection, String id) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.exists(collection, id);
  }

  /// Get all documents in a collection.
  Future<List<TorexDocument>> getAll(String collection) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.getAll(collection);
  }

  /// Get the number of documents in a collection.
  Future<int> count(String collection) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.count(collection);
  }

  /// Get all collection names.
  Future<List<String>> collections() async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.collections();
  }

  /// Query documents with a filter.
  ///
  /// ```dart
  /// final adults = await db.query('users', QueryFilter.gt('age', 18));
  /// final activeAdults = await db.query('users',
  ///   QueryFilter.and([QueryFilter.gt('age', 18), QueryFilter.eq('active', true)]),
  /// );
  /// ```
  Future<List<TorexDocument>> query(
    String collection,
    QueryFilter filter,
  ) async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.query(collection, filter);
  }

  /// Watch a collection for real-time change notifications.
  ///
  /// Returns a broadcast [Stream] of [StoreChangeEvent]s.
  ///
  /// ```dart
  /// db.watch('users').listen((event) {
  ///   print('${event.type}: ${event.id}');
  /// });
  /// ```
  Stream<StoreChangeEvent> watch(String collection) async* {
    await _ensureReady();
    _lifecycle.recordActivity();
    yield* _engine.watch(collection);
  }

  /// Run compaction to reclaim disk space.
  Future<String> compact() async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.compact();
  }

  /// Check if compaction is recommended.
  Future<bool> needsCompaction() async {
    await _ensureReady();
    _lifecycle.recordActivity();
    return _engine.needsCompaction();
  }

  /// Generate a new unique document ID.
  String generateId() => _engine.generateId();

  /// Check if the database is currently open and ready.
  bool get isReady => _engine.isOpen;

  /// Get the database file path (null if not yet opened).
  String? get path => _engine.path;

  // ─── Auto-Lifecycle Engine ──────────────────────────────────────────────

  /// Ensures the database is open and ready for operations.
  ///
  /// This is the core of the "always-available" guarantee:
  /// - If the engine is open, returns immediately
  /// - If the engine is closed, auto-reopens it
  /// - If initialization is in progress, waits for it to complete
  /// - On first call, performs lazy initialization
  Future<void> _ensureReady() async {
    if (_engine.isOpen) return;

    // If another call is already opening the engine, wait for it
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      await _initCompleter!.future;
      return;
    }

    // We are the one to open it
    _initCompleter = Completer<void>();

    try {
      await _engine.open(path: _config.customPath);
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  /// Called by LifecycleManager when app goes to background or idle timeout.
  Future<void> _onLifecycleSuspend() async {
    if (_engine.isOpen) {
      await _engine.close();
    }
  }

  /// Called by LifecycleManager when resuming from suspend.
  Future<void> _onLifecycleResume() async {
    // Engine will auto-reopen on next _ensureReady() call
  }

  // ─── Backward Compatibility ─────────────────────────────────────────────

  /// @deprecated Use [TorexStore.instance] instead.
  /// This is provided for backward compatibility only.
  static TorexStorageCompat get storage => TorexStorageCompat._();
}

/// Backward-compatible wrapper that mimics the old TorexStorage API.
///
/// @deprecated Use [TorexStore.instance] directly instead.
class TorexStorageCompat {
  TorexStorageCompat._();

  TorexStore get _db => TorexStore.instance;

  /// @deprecated Database auto-initializes. No need to call this.
  Future<void> init({String? path}) async {
    if (path != null) {
      TorexStore.configure(TorexStoreConfig(customPath: path));
    }
    // Trigger lazy init
    await _db.collections();
  }

  Future<void> put(String collection, TorexDocument document) =>
      _db.put(collection, document);

  Future<TorexDocument?> get(String collection, String id) =>
      _db.get(collection, id);

  Future<void> update(String collection, TorexDocument document) =>
      _db.update(collection, document);

  Future<void> delete(String collection, String id) =>
      _db.delete(collection, id);

  Future<bool> exists(String collection, String id) =>
      _db.exists(collection, id);

  Future<List<TorexDocument>> getAll(String collection) =>
      _db.getAll(collection);

  Future<int> count(String collection) => _db.count(collection);

  Future<List<String>> collections() => _db.collections();

  Future<List<TorexDocument>> query(
    String collection,
    QueryFilter filter,
  ) =>
      _db.query(collection, filter);

  Stream<StoreChangeEvent> watch(String collection) => _db.watch(collection);

  Future<String> compact() => _db.compact();

  String generateId() => _db.generateId();

  /// @deprecated Database auto-closes. No need to call this.
  Future<void> close() async {
    // No-op: lifecycle is automatic
  }

  bool get isInitialized => _db.isReady;

  String? get path => _db.path;
}

/// Configuration for [TorexStore].
///
/// Pass to [TorexStore.configure] before first use (optional).
class TorexStoreConfig {
  /// Duration of inactivity before auto-closing the database.
  ///
  /// Default: 30 seconds. Set to [Duration.zero] to disable idle timeout.
  final Duration idleTimeout;

  /// Custom database file path.
  ///
  /// If null, uses the default application documents directory.
  final String? customPath;

  const TorexStoreConfig({
    this.idleTimeout = const Duration(seconds: 30),
    this.customPath,
  });
}
