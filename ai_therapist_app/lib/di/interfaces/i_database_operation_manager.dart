// lib/di/interfaces/i_database_operation_manager.dart

import 'dart:async';
import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/remote/api_client.dart';

/// Interface for database operation management
/// Provides contract for coordinating database operations and preventing conflicts
abstract class IDatabaseOperationManager {
  /// Add a database operation to the queue
  ///
  /// Returns a Future that completes when the operation has been executed
  Future<T> queueOperation<T>(
    Future<T> Function() operation, {
    String name = 'unnamed',
    bool isReadOnly = false,
    bool priority = false,
  });

  /// Check database health and fix any issues
  Future<bool> checkAndRepairDatabaseHealth(AppDatabase database);

  /// Optimize database performance
  Future<void> optimizeDatabase(AppDatabase database);

  /// Synchronize local database with server
  /// This should be called after initial app loading
  Future<void> synchronizeWithServer(
    AppDatabase database,
    ApiClient apiClient,
  );
}
