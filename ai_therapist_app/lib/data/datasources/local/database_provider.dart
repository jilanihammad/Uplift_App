import 'package:sqflite/sqflite.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/services/user_context_service.dart';
import 'package:ai_therapist_app/utils/database_health_checker.dart';
class DatabaseProvider {
  final AppDatabase _database;
  final UserContextService _userContext;
  static const Set<String> _userScopedTables = {
    'sessions',
    'messages',
    'mood_logs',
    'mood_entries',
    'conversation_memories',
    'conversations',
    'therapy_insights',
    'insights',
    'emotional_states',
    'user_progress',
    'user_anchors',
    'logs',
  };
  DatabaseProvider({AppDatabase? database, UserContextService? userContext})
      : _database = database ?? DependencyContainer().appDatabaseConcrete,
        _userContext = userContext ?? DependencyContainer().userContextService;
  Future<void> init() async {
    try {
      await _database.database;
    } catch (e) {
      rethrow;
    }
  }
  Future<Database> get database async => await _database.database;
  Future<bool> tableExists(String tableName) =>
      _database.tableExists(tableName);
  Future<int> insert(String table, Map<String, dynamic> data) async {
    try {
      final scopedData = Map<String, dynamic>.from(data);
      String? userId;
      if (_userScopedTables.contains(table)) {
        userId = _userContext.getSignedInUserId(
          operation: 'DatabaseProvider.insert.$table',
        );
        if (userId == null) {
          return 0;
        }
        scopedData.putIfAbsent('user_id', () => userId);
      }
      return await _database.insert(table, scopedData);
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        final retryData = Map<String, dynamic>.from(data);
        if (_userScopedTables.contains(table)) {
          final userId = _userContext.getSignedInUserId(
            operation: 'DatabaseProvider.insert.$table.retry',
          );
          if (userId == null) {
            return 0;
          }
          retryData.putIfAbsent('user_id', () => userId);
        }
        return await _database.insert(table, retryData);
      }
      rethrow;
    }
  }
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    try {
      final scope = await _applyUserScope(
        table,
        where,
        whereArgs,
        operation: 'DatabaseProvider.query.$table',
      );
      if (scope == null) {
        return const <Map<String, dynamic>>[];
      }
      return await _database.query(
        table,
        where: scope.where,
        whereArgs: scope.whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        final scope = await _applyUserScope(
          table,
          where,
          whereArgs,
          operation: 'DatabaseProvider.query.$table.retry',
        );
        if (scope == null) {
          return const <Map<String, dynamic>>[];
        }
        return await _database.query(
          table,
          where: scope.where,
          whereArgs: scope.whereArgs,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
        );
      }
      rethrow;
    }
  }
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      final scopedData = Map<String, dynamic>.from(data);
      String? userId;
      if (_userScopedTables.contains(table)) {
        userId = _userContext.getSignedInUserId(
          operation: 'DatabaseProvider.update.$table',
        );
        if (userId == null) {
          return 0;
        }
        scopedData.putIfAbsent('user_id', () => userId);
      }
      final scope = await _applyUserScope(
        table,
        where,
        whereArgs,
        operation: 'DatabaseProvider.update.$table',
        knownUserId: userId,
      );
      if (scope == null) {
        return 0;
      }
      return await _database.update(
        table,
        scopedData,
        where: scope.where,
        whereArgs: scope.whereArgs,
      );
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        final retryData = Map<String, dynamic>.from(data);
        String? userId;
        if (_userScopedTables.contains(table)) {
          userId = _userContext.getSignedInUserId(
            operation: 'DatabaseProvider.update.$table.retry',
          );
          if (userId == null) {
            return 0;
          }
          retryData.putIfAbsent('user_id', () => userId);
        }
        final scope = await _applyUserScope(
          table,
          where,
          whereArgs,
          operation: 'DatabaseProvider.update.$table.retry',
          knownUserId: userId,
        );
        if (scope == null) {
          return 0;
        }
        return await _database.update(
          table,
          retryData,
          where: scope.where,
          whereArgs: scope.whereArgs,
        );
      }
      rethrow;
    }
  }
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      final scope = await _applyUserScope(
        table,
        where,
        whereArgs,
        operation: 'DatabaseProvider.delete.$table',
      );
      if (scope == null) {
        return 0;
      }
      return await _database.delete(
        table,
        where: scope.where,
        whereArgs: scope.whereArgs,
      );
    } catch (e) {
      if (_isNoSuchTableError(e) &&
          DatabaseHealthChecker.requiredTables.containsKey(table)) {
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        final scope = await _applyUserScope(
          table,
          where,
          whereArgs,
          operation: 'DatabaseProvider.delete.$table.retry',
        );
        if (scope == null) {
          return 0;
        }
        return await _database.delete(
          table,
          where: scope.where,
          whereArgs: scope.whereArgs,
        );
      }
      rethrow;
    }
  }
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      return await _database.rawQuery(sql, arguments);
    } catch (e) {
      if (_isNoSuchTableError(e)) {
      }
      rethrow;
    }
  }
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      return await _database.rawExecute(sql, arguments);
    } catch (e) {
      if (_isNoSuchTableError(e)) {
      }
      rethrow;
    }
  }
  Future<T> transaction<T>(Future<T> Function(Transaction) action) =>
      _database.transaction(action);
  Future<void> close() => _database.close();
  bool _isNoSuchTableError(Object e) {
    return e is DatabaseException && e.toString().contains('no such table');
  }
  Future<_ScopedWhere?> _applyUserScope(
    String table,
    String? where,
    List<dynamic>? whereArgs, {
    required String operation,
    String? knownUserId,
  }) async {
    if (!_userScopedTables.contains(table)) {
      return _ScopedWhere(where: where, whereArgs: whereArgs);
    }
    final userId = knownUserId ??
        _userContext.getSignedInUserId(operation: '$operation.resolved');
    if (userId == null || userId.isEmpty) {
      return null;
    }
    if (where != null && where.contains('user_id')) {
      return _ScopedWhere(where: where, whereArgs: whereArgs);
    }
    final scopedWhere =
        where == null ? 'user_id = ?' : '($where) AND user_id = ?';
    final scopedArgs = List<dynamic>.from(whereArgs ?? <dynamic>[])
      ..add(userId);
    return _ScopedWhere(where: scopedWhere, whereArgs: scopedArgs);
  }
}
class _ScopedWhere {
  const _ScopedWhere({this.where, this.whereArgs});
  final String? where;
  final List<dynamic>? whereArgs;
}
