import 'dart:async';

/// Event types from the store watcher
enum StoreEventType { insert, update, delete }

/// A store change event
class StoreChangeEvent {
  /// Type of event
  final StoreEventType type;

  /// Collection name
  final String collection;

  /// Record ID
  final String id;

  /// Record data (null for delete events)
  final Map<String, dynamic>? data;

  /// Creates a new store change event.
  ///
  /// [type] is the event type (insert, update, or delete).
  /// [collection] is the name of the collection where the change occurred.
  /// [id] is the document ID affected by the change.
  /// [data] is the document data (null for delete events).
  const StoreChangeEvent({
    required this.type,
    required this.collection,
    required this.id,
    this.data,
  });

  @override
  String toString() =>
      'StoreChangeEvent(type: $type, collection: $collection, id: $id)';
}

/// Watches a collection for changes and emits events via a Stream
class StoreWatcher {
  final String _collection;
  final StreamController<StoreChangeEvent> _controller;
  final void Function(int subscriptionId)? _onCancel;
  int? _subscriptionId;
  bool _active = true;

  /// Creates a new watcher for the given [collection].
  ///
  /// The [onCancel] callback is invoked when the watcher is cancelled,
  /// receiving the native subscription ID for cleanup.
  StoreWatcher({
    required String collection,
    void Function(int subscriptionId)? onCancel,
  })  : _collection = collection,
        _onCancel = onCancel,
        _controller = StreamController<StoreChangeEvent>.broadcast();

  /// The collection being watched
  String get collection => _collection;

  /// Whether this watcher is still active
  bool get isActive => _active && !_controller.isClosed;

  /// Stream of change events
  Stream<StoreChangeEvent> get stream => _controller.stream;

  /// Set the native subscription ID
  set subscriptionId(int id) => _subscriptionId = id;

  /// Emit an insert event
  void emitInsert(String id, Map<String, dynamic>? data) {
    if (!_controller.isClosed) {
      _controller.add(StoreChangeEvent(
        type: StoreEventType.insert,
        collection: _collection,
        id: id,
        data: data,
      ));
    }
  }

  /// Emit an update event
  void emitUpdate(String id, Map<String, dynamic>? data) {
    if (!_controller.isClosed) {
      _controller.add(StoreChangeEvent(
        type: StoreEventType.update,
        collection: _collection,
        id: id,
        data: data,
      ));
    }
  }

  /// Emit a delete event
  void emitDelete(String id) {
    if (!_controller.isClosed) {
      _controller.add(StoreChangeEvent(
        type: StoreEventType.delete,
        collection: _collection,
        id: id,
      ));
    }
  }

  /// Cancel this watcher
  void cancel() {
    _active = false;
    if (_subscriptionId != null && _onCancel != null) {
      _onCancel(_subscriptionId!);
    }
    _controller.close();
  }

  /// Dispose resources
  void dispose() {
    cancel();
  }
}
