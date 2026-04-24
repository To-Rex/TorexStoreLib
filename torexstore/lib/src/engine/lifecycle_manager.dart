import 'dart:async';

import 'package:flutter/widgets.dart';

/// Callback type for lifecycle events
typedef LifecycleCallback = Future<void> Function();

/// Manages the database lifecycle automatically.
///
/// Integrates with:
/// - Flutter app lifecycle (WidgetsBindingObserver)
/// - Idle timeout (auto-close after inactivity)
/// - Scheduler callbacks (frame-based activity detection)
///
/// The developer never needs to interact with this class.
class LifecycleManager with WidgetsBindingObserver {
  /// Called when the engine should suspend (persist and release resources)
  LifecycleCallback? onSuspend;

  /// Called when the engine should resume (reload if needed)
  LifecycleCallback? onResume;

  /// Idle timeout duration (default: 30 seconds)
  Duration idleTimeout;

  Timer? _idleTimer;
  bool _isSuspended = false;
  bool _isAttached = false;
  DateTime? _lastActivity;

  LifecycleManager({
    this.idleTimeout = const Duration(seconds: 30),
    this.onSuspend,
    this.onResume,
  });

  /// Whether the engine is currently suspended
  bool get isSuspended => _isSuspended;

  /// Time of last activity
  DateTime? get lastActivity => _lastActivity;

  /// Attach to the Flutter binding for lifecycle observation
  void attach() {
    if (_isAttached) return;
    _isAttached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Detach from the Flutter binding
  void detach() {
    if (!_isAttached) return;
    _isAttached = false;
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
  }

  /// Record activity (resets the idle timer)
  void recordActivity() {
    _lastActivity = DateTime.now();

    if (_isSuspended) {
      // Auto-resume on activity
      _resume();
    }

    _resetIdleTimer();
  }

  /// Force suspend (used internally)
  Future<void> suspend() async {
    if (_isSuspended) return;
    _isSuspended = true;
    _idleTimer?.cancel();
    await onSuspend?.call();
  }

  /// Force resume (used internally)
  Future<void> resume() async {
    if (!_isSuspended) return;
    await _resume();
  }

  /// Dispose all resources
  void dispose() {
    detach();
    onSuspend = null;
    onResume = null;
  }

  // ─── WidgetsBindingObserver ────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // App went to background - suspend immediately
        _onAppPaused();
        break;
      case AppLifecycleState.resumed:
        // App came to foreground - will auto-resume on next activity
        break;
      case AppLifecycleState.inactive:
        // App is inactive (e.g., phone call overlay)
        break;
      case AppLifecycleState.detached:
        // App is detached - suspend
        _onAppPaused();
        break;
      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
  }

  // ─── Private Methods ────────────────────────────────────────────────────

  void _onAppPaused() {
    if (_isSuspended) return;
    // Schedule the suspend in the next microtask to avoid blocking the frame
    scheduleMicrotask(() => suspend());
  }

  Future<void> _resume() async {
    _isSuspended = false;
    await onResume?.call();
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _onIdleTimeout);
  }

  void _onIdleTimeout() {
    if (_isSuspended) return;
    // No activity for the timeout period - suspend to save resources
    scheduleMicrotask(() => suspend());
  }
}
