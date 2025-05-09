import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/utils/database_health_checker.dart';

/// DatabaseProvider abstracts database access and adds an additional layer
/// for potential mocking in tests and better dependency management
class DatabaseProvider {
  final AppDatabase _database;

  /// Create a new DatabaseProvider with the given database
  /// or use the service locator if not provided
  DatabaseProvider({AppDatabase? database})
      : _database = database ?? serviceLocator<AppDatabase>();

  /// Initialize the database
  Future<void> init() async {
    try {
      // Access the database to ensure it's initialized
      await _database.database;
      debugPrint('DatabaseProvider initialized');
    } catch (e) {
      debugPrint('Error initializing DatabaseProvider: $e');
      rethrow;
    }
  }

  /// Get the database instance
  Future<Database> get database async => await _database.database;

  /// Check if a table exists
  Future<bool> tableExists(String tableName) =>
      _database.tableExists(tableName);

  /// Insert a record with error handling and retry
  Future<int> insert(String table, Map<String, dynamic> data) async {
    try {
      return await _database.insert(table, data);
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        debugPrint(
            '[DB Provider] Table $table missing on insert, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
        return await _database.insert(table, data);
      }
      rethrow;
    }
  }

  /// Query records with error handling and retry
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    try {
      return await _database.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        debugPrint(
            '[DB Provider] Table $table missing on query, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
        return await _database.query(
          table,
          where: where,
          whereArgs: whereArgs,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
        );
      }
      rethrow;
    }
  }

  /// Update records with error handling and retry
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      return await _database.update(
        table,
        data,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        debugPrint(
            '[DB Provider] Table $table missing on update, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
        return await _database.update(
          table,
          data,
          where: where,
          whereArgs: whereArgs,
        );
      }
      rethrow;
    }
  }

  /// Delete records with error handling and retry
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      return await _database.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        debugPrint(
            '[DB Provider] Table $table missing on delete, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
        return await _database.delete(
          table,
          where: where,
          whereArgs: whereArgs,
        );
      }
      rethrow;
    }
  }

  /// Execute a raw SQL query with error handling and retry
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      return await _database.rawQuery(sql, arguments);
    } catch (e) {
      if (_isNoSuchTableError(e)) {
        debugPrint(
            '[DB Provider] Table missing on rawQuery, cannot auto-recover. SQL: $sql');
      }
      rethrow;
    }
  }

  /// Execute a raw SQL command with error handling and retry
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      return await _database.rawExecute(sql, arguments);
    } catch (e) {
      if (_isNoSuchTableError(e)) {
        debugPrint(
            '[DB Provider] Table missing on rawExecute, cannot auto-recover. SQL: $sql');
      }
      rethrow;
    }
  }

  /// Execute operations in a transaction
  Future<T> transaction<T>(Future<T> Function(Transaction) action) =>
      _database.transaction(action);

  /// Close the database connection
  Future<void> close() => _database.close();

  bool _isNoSuchTableError(Object e) {
    return e is DatabaseException && e.toString().contains('no such table');
  }
}
