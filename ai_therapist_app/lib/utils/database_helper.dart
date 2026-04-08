import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import '../di/interfaces/i_database_operation_manager.dart';
class DatabaseOperationManager implements IDatabaseOperationManager {
  static final DatabaseOperationManager _instance =
      DatabaseOperationManager._internal();
  factory DatabaseOperationManager() => _instance;
  DatabaseOperationManager._internal();
  final _operationQueue = <_DatabaseOperation>[];
  bool _isProcessingQueue = false;
  bool _potentialDatabaseLock = false;
  @override
  Future<T> queueOperation<T>(
    Future<T> Function() operation, {
    String name = 'unnamed',
    bool isReadOnly = false,
    bool priority = false,
  }) async {
    final completer = Completer<T>();
    final dbOperation = _DatabaseOperation<T>(
      operation: operation,
      completer: completer,
      name: name,
      isReadOnly: isReadOnly,
      priority: priority,
    );
    if (priority) {
      _operationQueue.insert(0, dbOperation);
    } else {
      _operationQueue.add(dbOperation);
    }
    if (!_isProcessingQueue) {
      _processQueue();
    }
    return completer.future;
  }
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    while (_operationQueue.isNotEmpty) {
      final operation = _operationQueue.removeAt(0);
      try {
        if (_potentialDatabaseLock && operation.isReadOnly) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        final result = await _executeWithRetry(operation);
        operation.completer.complete(result);
        _potentialDatabaseLock = false;
      } catch (e) {
        if (e.toString().contains('database is locked') ||
            e.toString().contains('database has been locked')) {
          _potentialDatabaseLock = true;
          _operationQueue.insert(0, operation);
          await Future.delayed(const Duration(seconds: 1));
        } else {
          operation.completer.completeError(e);
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _isProcessingQueue = false;
  }
  Future<T> _executeWithRetry<T>(_DatabaseOperation<T> operation) async {
    int attempts = 0;
    const maxAttempts = 3;
    const baseDelayMs = 200;
    while (true) {
      try {
        return await operation.operation();
      } catch (e) {
        attempts++;
        final isLockError = e.toString().contains('database is locked') ||
            e.toString().contains('database has been locked');
        if (attempts < maxAttempts && isLockError) {
          final delayMs = baseDelayMs * (1 << attempts);
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          rethrow;
        }
      }
    }
  }
  @override
  Future<bool> checkAndRepairDatabaseHealth(AppDatabase database) async {
    try {
      final db = await database.database;
      try {
        final results = await db.rawQuery('PRAGMA integrity_check;');
        final status = results.first.values.first.toString().toLowerCase();
        if (status != 'ok') {
          return false;
        }
        final walMode = await db.rawQuery('PRAGMA journal_mode;');
        final mode = walMode.first.values.first.toString().toLowerCase();
        if (mode != 'wal') {
          await db.rawQuery('PRAGMA journal_mode = WAL;');
        }
        await db.rawQuery('PRAGMA busy_timeout = 5000;');
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  @override
  Future<void> optimizeDatabase(AppDatabase database) async {
    try {
      final db = await database.database;
      await db.execute('VACUUM;');
      await db.execute('ANALYZE;');
    } catch (e) {}
  }
  @override
  Future<void> synchronizeWithServer(
    AppDatabase database,
    ApiClient apiClient,
  ) async {
    Future.delayed(const Duration(seconds: 5), () async {
      try {
      } catch (e) {}
    });
  }
}
class _DatabaseOperation<T> {
  final Future<T> Function() operation;
  final Completer<T> completer;
  final String name;
  final bool isReadOnly;
  final bool priority;
  _DatabaseOperation({
    required this.operation,
    required this.completer,
    required this.name,
    this.isReadOnly = false,
    this.priority = false,
  });
}
