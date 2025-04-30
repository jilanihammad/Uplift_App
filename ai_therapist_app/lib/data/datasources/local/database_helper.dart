// lib/data/datasources/local/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'database_provider.dart';
import '../../../di/service_locator.dart';

/// DatabaseHelper has been deprecated and now acts as an adapter around DatabaseProvider.
/// This class exists for backward compatibility and will eventually be removed.
@Deprecated('Use DatabaseProvider instead')
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  // Reference to the new DatabaseProvider implementation
  late final DatabaseProvider _databaseProvider;

  // Private constructor
  DatabaseHelper._internal() {
    _databaseProvider = serviceLocator<DatabaseProvider>();
    if (kDebugMode) {
      print(
          'Warning: DatabaseHelper is deprecated. Use DatabaseProvider instead.');
    }
  }

  // Factory constructor to return the same instance
  factory DatabaseHelper() => _instance;

  // Adapter methods that forward to DatabaseProvider

  /// Get database instance
  Future<Database> get database async => await _databaseProvider.database;

  /// Insert a record
  Future<int> insert(String table, Map<String, dynamic> data) =>
      _databaseProvider.insert(table, data);

  /// Query records
  Future<List<Map<String, dynamic>>> query(String table) =>
      _databaseProvider.query(table);

  /// Update a record
  Future<int> update(String table, Map<String, dynamic> data,
          String whereClause, List<dynamic> whereArgs) =>
      _databaseProvider.update(table, data,
          where: whereClause, whereArgs: whereArgs);

  /// Delete a record
  Future<int> delete(
          String table, String whereClause, List<dynamic> whereArgs) =>
      _databaseProvider.delete(table, where: whereClause, whereArgs: whereArgs);
}
