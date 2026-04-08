// lib/di/interfaces/i_database_operation_manager.dart
import 'dart:async';
import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/remote/api_client.dart';
abstract class IDatabaseOperationManager {
  Future<T> queueOperation<T>(
    Future<T> Function() operation, {
    String name = 'unnamed',
    bool isReadOnly = false,
    bool priority = false,
  });
  Future<bool> checkAndRepairDatabaseHealth(AppDatabase database);
  Future<void> optimizeDatabase(AppDatabase database);
  Future<void> synchronizeWithServer(
    AppDatabase database,
    ApiClient apiClient,
  );
}
