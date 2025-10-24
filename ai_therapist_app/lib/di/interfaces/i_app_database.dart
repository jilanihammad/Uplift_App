// lib/di/interfaces/i_app_database.dart

import 'dart:async';
import 'package:sqflite/sqflite.dart';

/// Interface for AppDatabase operations
/// Provides contract for SQLite database access with app-specific schema
///
/// This interface defines all public methods that the AppDatabase class exposes,
/// enabling dependency injection and testing through mocks.
abstract class IAppDatabase {
  // Database instance management

  /// Get the database instance
  /// Returns the active SQLite database instance
  Future<Database> get database;

  /// Check if a table exists in the database
  ///
  /// [tableName] - Name of the table to check
  /// Returns true if the table exists, false otherwise
  Future<bool> tableExists(String tableName);

  /// Close the database connection
  /// Properly closes the database connection and cleans up resources
  Future<void> close();

  // CRUD Operations

  /// Insert a row into a table
  ///
  /// [table] - Target table name
  /// [data] - Map of column names to values
  /// Returns the row ID of the inserted record
  Future<int> insert(String table, Map<String, dynamic> data);

  /// Query rows from a table
  ///
  /// [table] - Table name to query
  /// [where] - Optional WHERE clause
  /// [whereArgs] - Optional arguments for WHERE clause
  /// [orderBy] - Optional ORDER BY clause
  /// [limit] - Optional LIMIT clause
  /// [offset] - Optional OFFSET clause
  /// Returns a list of maps representing the query results
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  });

  /// Update a row in a table
  ///
  /// [table] - Target table name
  /// [data] - Map of column names to new values
  /// [where] - Optional WHERE clause to specify which rows to update
  /// [whereArgs] - Optional arguments for WHERE clause
  /// Returns the number of rows affected
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  });

  /// Delete a row from a table
  ///
  /// [table] - Target table name
  /// [where] - Optional WHERE clause to specify which rows to delete
  /// [whereArgs] - Optional arguments for WHERE clause
  /// Returns the number of rows affected
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  });

  // Raw SQL Operations

  /// Execute a raw SQL query
  ///
  /// [sql] - SQL query string
  /// [arguments] - Optional list of arguments for parameterized queries
  /// Returns a list of maps representing the query results
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]);

  /// Execute a raw SQL command
  ///
  /// [sql] - SQL command string (INSERT, UPDATE, DELETE)
  /// [arguments] - Optional list of arguments for parameterized queries
  /// Returns the number of rows affected
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]);

  // Transaction Management

  /// Execute multiple operations in a transaction
  ///
  /// [action] - Function containing the operations to execute atomically
  /// Returns the result of the action function
  ///
  /// All operations within the action are executed atomically.
  /// If any operation fails, the entire transaction is rolled back.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action);
}
