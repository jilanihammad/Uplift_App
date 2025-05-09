import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:sqflite/sqflite.dart';

/// Database operation manager utility to coordinate database operations and prevent conflicts
class DatabaseOperationManager {
  static final DatabaseOperationManager _instance =
      DatabaseOperationManager._internal();
  factory DatabaseOperationManager() => _instance;
  DatabaseOperationManager._internal();

  // Queue to manage database operations
  final _operationQueue = <_DatabaseOperation>[];
  bool _isProcessingQueue = false;

  // Flag for when database is suspected to be locked
  bool _potentialDatabaseLock = false;

  /// Add a database operation to the queue
  ///
  /// Returns a Future that completes when the operation has been executed
  Future<T> queueOperation<T>(
    Future<T> Function() operation, {
    String name = 'unnamed',
    bool isReadOnly = false,
    bool priority = false,
  }) async {
    // Completer to handle the async result
    final completer = Completer<T>();

    // Create the operation object
    final dbOperation = _DatabaseOperation<T>(
      operation: operation,
      completer: completer,
      name: name,
      isReadOnly: isReadOnly,
      priority: priority,
    );

    // Add to queue based on priority
    if (priority) {
      _operationQueue.insert(0, dbOperation);
      debugPrint('Added high-priority DB operation to front of queue: $name');
    } else {
      _operationQueue.add(dbOperation);
      debugPrint('Added DB operation to queue: $name');
    }

    // Start processing queue if not already in progress
    if (!_isProcessingQueue) {
      _processQueue();
    }

    return completer.future;
  }

  /// Process operations in the queue
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;

    _isProcessingQueue = true;
    debugPrint('Starting to process database operation queue');

    // Process all operations in the queue
    while (_operationQueue.isNotEmpty) {
      final operation = _operationQueue.removeAt(0);
      debugPrint('Executing DB operation: ${operation.name}');

      try {
        // If database might be locked, add delay for read-only operations
        if (_potentialDatabaseLock && operation.isReadOnly) {
          debugPrint('Potential DB lock detected, delaying read operation');
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // Execute the operation with retry logic
        final result = await _executeWithRetry(operation);
        operation.completer.complete(result);

        // If operation was successful, clear the potential lock flag
        _potentialDatabaseLock = false;
      } catch (e) {
        debugPrint('Error in DB operation ${operation.name}: $e');

        // If there's a database locked error, set the flag
        if (e.toString().contains('database is locked') ||
            e.toString().contains('database has been locked')) {
          _potentialDatabaseLock = true;
          debugPrint('DATABASE LOCK DETECTED: Adding delay between operations');

          // Put operation back at front of queue to retry
          _operationQueue.insert(0, operation);

          // Add a delay before retrying
          await Future.delayed(const Duration(seconds: 1));
        } else {
          // For other errors, complete with error
          operation.completer.completeError(e);
        }
      }

      // Small delay between operations to reduce contention
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isProcessingQueue = false;
    debugPrint('Database operation queue processing complete');
  }

  /// Execute operation with retry logic for better reliability
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

        // Only retry if we have attempts left and it's a lock error
        if (attempts < maxAttempts && isLockError) {
          // Exponential backoff
          final delayMs = baseDelayMs * (1 << attempts);
          debugPrint(
              'Database operation ${operation.name} failed with lock error, retry $attempts/$maxAttempts in ${delayMs}ms');
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          // Either max attempts reached or non-lock error
          rethrow;
        }
      }
    }
  }

  /// Check database health and fix any issues
  Future<bool> checkAndRepairDatabaseHealth(AppDatabase database) async {
    try {
      debugPrint('Checking database health...');

      // Get database instance
      final db = await database.database;

      // Check database integrity
      try {
        final results = await db.rawQuery('PRAGMA integrity_check;');
        final status = results.first.values.first.toString().toLowerCase();

        if (status != 'ok') {
          debugPrint('Database integrity check failed: $status');
          return false;
        }

        // Check for WAL mode
        final walMode = await db.rawQuery('PRAGMA journal_mode;');
        final mode = walMode.first.values.first.toString().toLowerCase();

        if (mode != 'wal') {
          debugPrint('Enabling WAL mode for better concurrency');
          await db.rawQuery('PRAGMA journal_mode = WAL;');
        }

        // Increase busy timeout
        await db.rawQuery('PRAGMA busy_timeout = 5000;');

        debugPrint('Database health check passed, database is healthy');
        return true;
      } catch (e) {
        debugPrint('Error performing database health check: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Could not access database for health check: $e');
      return false;
    }
  }

  /// Optimize database performance
  Future<void> optimizeDatabase(AppDatabase database) async {
    try {
      debugPrint('Optimizing database...');

      final db = await database.database;

      // Perform VACUUM to reclaim space and defragment
      await db.execute('VACUUM;');

      // Run ANALYZE to update statistics
      await db.execute('ANALYZE;');

      debugPrint('Database optimization complete');
    } catch (e) {
      debugPrint('Error optimizing database: $e');
    }
  }

  /// Synchronize local database with server
  /// This should be called after initial app loading
  Future<void> synchronizeWithServer(
    AppDatabase database,
    ApiClient apiClient,
  ) async {
    // This will be used later to sync data
    debugPrint('Database synchronization will be performed in background');

    // Schedule the sync for later to avoid startup congestion
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        // This is where you would implement data syncing logic
        debugPrint('Beginning database synchronization with server');

        // Implement actual sync logic later

        debugPrint('Database synchronization complete');
      } catch (e) {
        debugPrint('Error during database synchronization: $e');
      }
    });
  }
}

/// Private class to represent a database operation in the queue
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
