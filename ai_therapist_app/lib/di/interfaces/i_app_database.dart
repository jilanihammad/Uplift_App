// lib/di/interfaces/i_app_database.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
abstract class IAppDatabase {
  Future<Database> get database;
  Future<bool> tableExists(String tableName);
  Future<void> close();
  Future<int> insert(String table, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> query(
    String table, {
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
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]);
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action);
}
