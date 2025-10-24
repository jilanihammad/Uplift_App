// lib/utils/disposable.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'disposal_monitor.dart';

/// Marker interface for services that require async disposal.
/// Services implementing this interface should use disposeAsync() instead of dispose().
abstract class AsyncDisposable {}

/// Mixin that provides automatic disposal capabilities for services.
/// Provides standardized disposal pattern with idempotency and error handling.
///
/// Classes that use this mixin should:
/// 1. Call super.dispose() in their dispose method
/// 2. Check disposed flag before performing operations
/// 3. Override performDisposal() with proper resource cleanup
mixin SessionDisposable {
  bool _disposed = false;
  final Completer<void> _disposalCompleter = Completer<void>();

  /// Whether this object has been disposed
  bool get disposed => _disposed;

  /// Future that completes when disposal is finished
  Future<void> get disposalComplete => _disposalCompleter.future;

  /// Disposes resources and marks object as disposed.
  /// Safe to call multiple times - will only dispose once.
  @mustCallSuper
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final stopwatch = Stopwatch()..start();
    String? error;

    try {
      if (kDebugMode) {
        debugPrint('[SessionDisposable] Disposing $runtimeType');
      }

      // For services that need async disposal, call disposeAsync instead
      if (this is AsyncDisposable) {
        // Async disposal will be handled separately
        if (kDebugMode) {
          debugPrint(
              '[SessionDisposable] $runtimeType requires async disposal - use disposeAsync()');
        }
      } else {
        // Synchronous disposal for simple services
        performDisposal();
      }

      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.complete();
      }
    } catch (e) {
      error = e.toString();

      if (kDebugMode) {
        debugPrint('[SessionDisposable] Error disposing $runtimeType: $e');
      }

      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.completeError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();

      // Record disposal metrics (skip async services since they use disposeAsync)
      if (this is! AsyncDisposable) {
        DisposalMonitor().recordDisposal(
          serviceName: runtimeType.toString(),
          durationMs: stopwatch.elapsedMilliseconds,
          isAsync: false,
          error: error,
        );
      }
    }
  }

  /// Async disposal for services that need proper cleanup timing.
  /// AudioPlayerManager and other media services should use this.
  @mustCallSuper
  Future<void> disposeAsync() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    final stopwatch = Stopwatch()..start();
    String? error;

    try {
      if (kDebugMode) {
        debugPrint('[SessionDisposable] Async disposing $runtimeType');
      }

      // Call async disposal with timeout protection
      await Future.any([
        performAsyncDisposal(),
        Future.delayed(const Duration(seconds: 5), () {
          throw TimeoutException(
              'Disposal timeout for $runtimeType', const Duration(seconds: 5));
        }),
      ]);

      if (kDebugMode) {
        debugPrint(
            '[SessionDisposable] $runtimeType async disposal completed in ${stopwatch.elapsedMilliseconds}ms');
      }

      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.complete();
      }
    } catch (e) {
      error = e.toString();

      if (kDebugMode) {
        debugPrint(
            '[SessionDisposable] Error async disposing $runtimeType: $e');
      }

      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.completeError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();

      // Record disposal metrics for monitoring MediaCodec issues
      DisposalMonitor().recordDisposal(
        serviceName: runtimeType.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        isAsync: true,
        error: error,
      );
    }
  }

  /// Override this method to perform actual disposal logic.
  /// Called by dispose() - do not call directly.
  @protected
  void performDisposal() {
    // Default implementation does nothing
    // Subclasses should override this
  }

  /// Override this method to perform async disposal logic.
  /// Called by disposeAsync() - do not call directly.
  @protected
  Future<void> performAsyncDisposal() async {
    // Default implementation calls sync disposal
    performDisposal();
  }

  /// Throws if object is disposed. Use this to guard operations.
  @protected
  void checkNotDisposed([String? operation]) {
    if (_disposed) {
      throw StateError(operation != null
          ? 'Cannot perform $operation on disposed $runtimeType'
          : '$runtimeType has been disposed');
    }
  }

  /// Safe way to check if an object is disposed without throwing
  @protected
  bool get canOperate => !_disposed;
}

/// Extension to make disposal checking easier for streams and futures
extension SessionDisposableOperations on SessionDisposable {
  /// Execute a function only if not disposed
  T? ifNotDisposed<T>(T Function() operation) {
    if (!disposed) {
      return operation();
    }
    return null;
  }

  /// Execute an async function only if not disposed
  Future<T?> ifNotDisposedAsync<T>(Future<T> Function() operation) async {
    if (!disposed) {
      return await operation();
    }
    return null;
  }
}
