// lib/di/interfaces/i_database.dart
import 'dart:async';
abstract class IDatabase {
  Future<void> initialize();
  Future<void> close();
  bool get isOpen;
  Future<T> transaction<T>(Future<T> Function() action);
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
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]);
  Future<int> rawInsert(String sql, [List<dynamic>? arguments]);
  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]);
  Future<int> rawDelete(String sql, [List<dynamic>? arguments]);
  Future<void> execute(String sql, [List<dynamic>? arguments]);
  Future<bool> tableExists(String tableName);
  Future<List<String>> getTableNames();
  Future<void> runMigration(int fromVersion, int toVersion);
  int get version;
  Future<void> batch(Future<void> Function() operations);
  Future<bool> healthCheck();
  Future<Map<String, dynamic>> getStats();
}
