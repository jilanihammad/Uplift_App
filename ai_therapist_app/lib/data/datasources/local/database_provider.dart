import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/di/service_locator.dart';

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

  /// Insert a record
  Future<int> insert(String table, Map<String, dynamic> data) =>
      _database.insert(table, data);

  /// Query records
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _database.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

  /// Update records
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) =>
      _database.update(
        table,
        data,
        where: where,
        whereArgs: whereArgs,
      );

  /// Delete records
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) =>
      _database.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );

  /// Execute a raw SQL query
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) =>
      _database.rawQuery(sql, arguments);

  /// Execute a raw SQL command
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]) =>
      _database.rawExecute(sql, arguments);

  /// Execute operations in a transaction
  Future<T> transaction<T>(Future<T> Function(Transaction) action) =>
      _database.transaction(action);

  /// Close the database connection
  Future<void> close() => _database.close();
}
