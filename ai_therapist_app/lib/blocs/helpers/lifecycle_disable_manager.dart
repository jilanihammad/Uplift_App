import 'dart:async';

/// Coordinates lifecycle-driven auto-disable requests so that only one
/// graceful shutdown runs at a time and all callers await its completion.
class LifecycleDisableManager {
  Future<void>? _pending;

  /// Ensures [disableFn] runs at most once until it completes. Concurrent
  /// callers receive the same pending future.
  Future<void> ensure(String context, Future<void> Function() disableFn) {
    final existing = _pending;
    if (existing != null) {
      return existing;
    }

    final completer = Completer<void>();
    final future = completer.future;
    _pending = future;

    () async {
      try {
        await disableFn();
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      } finally {
        if (identical(_pending, future)) {
          _pending = null;
        }
      }
    }();

    return future;
  }
}
