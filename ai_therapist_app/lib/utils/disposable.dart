// lib/utils/disposable.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'disposal_monitor.dart';
abstract class AsyncDisposable {}
mixin SessionDisposable {
  bool _disposed = false;
  final Completer<void> _disposalCompleter = Completer<void>();
  bool get disposed => _disposed;
  Future<void> get disposalComplete => _disposalCompleter.future;
  @mustCallSuper
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final stopwatch = Stopwatch()..start();
    String? error;
    try {
      if (this is AsyncDisposable) {
      } else {
        performDisposal();
      }
      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.complete();
      }
    } catch (e) {
      error = e.toString();
      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.completeError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();
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
  @mustCallSuper
  Future<void> disposeAsync() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final stopwatch = Stopwatch()..start();
    String? error;
    try {
      await Future.any([
        performAsyncDisposal(),
        Future.delayed(const Duration(seconds: 5), () {
          throw TimeoutException(
              'Disposal timeout for $runtimeType', const Duration(seconds: 5));
        }),
      ]);
      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.complete();
      }
    } catch (e) {
      error = e.toString();
      if (!_disposalCompleter.isCompleted) {
        _disposalCompleter.completeError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();
      DisposalMonitor().recordDisposal(
        serviceName: runtimeType.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        isAsync: true,
        error: error,
      );
    }
  }
  @protected
  void performDisposal() {
  }
  @protected
  Future<void> performAsyncDisposal() async {
    performDisposal();
  }
  @protected
  void checkNotDisposed([String? operation]) {
    if (_disposed) {
      throw StateError(operation != null
          ? 'Cannot perform $operation on disposed $runtimeType'
          : '$runtimeType has been disposed');
    }
  }
  @protected
  bool get canOperate => !_disposed;
}
extension SessionDisposableOperations on SessionDisposable {
  T? ifNotDisposed<T>(T Function() operation) {
    if (!disposed) {
      return operation();
    }
    return null;
  }
  Future<T?> ifNotDisposedAsync<T>(Future<T> Function() operation) async {
    if (!disposed) {
      return await operation();
    }
    return null;
  }
}
