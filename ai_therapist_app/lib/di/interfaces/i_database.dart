// lib/di/interfaces/i_database.dart

import 'dart:async';

/// Interface for database operations
/// Provides contract for data persistence
abstract class IDatabase {
  // Connection management
  Future<void> initialize();
  Future<void> close();
  bool get isOpen;
  
  // Transaction management
  Future<T> transaction<T>(Future<T> Function() action);
  
  // CRUD operations
  Future<int> insert(String table, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  });
  
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  });
  
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  });
  
  // Raw SQL operations
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]);
  
  Future<int> rawInsert(String sql, [List<dynamic>? arguments]);
  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]);
  Future<int> rawDelete(String sql, [List<dynamic>? arguments]);
  
  // Schema management
  Future<void> execute(String sql, [List<dynamic>? arguments]);
  Future<bool> tableExists(String tableName);
  Future<List<String>> getTableNames();
  
  // Migration support
  Future<void> runMigration(int fromVersion, int toVersion);
  int get version;
  
  // Batch operations
  Future<void> batch(Future<void> Function() operations);
  
  // Health check
  Future<bool> healthCheck();
  Future<Map<String, dynamic>> getStats();
}