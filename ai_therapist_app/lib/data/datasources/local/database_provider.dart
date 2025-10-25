import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/services/user_context_service.dart';
import 'package:ai_therapist_app/utils/database_health_checker.dart';

/// DatabaseProvider abstracts database access and adds an additional layer
/// for potential mocking in tests and better dependency management
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

  /// Create a new DatabaseProvider with the given database
  /// or use the dependency container if not provided
  DatabaseProvider({AppDatabase? database, UserContextService? userContext})
      : _database = database ?? DependencyContainer().appDatabaseConcrete,
        _userContext = userContext ?? DependencyContainer().userContextService;

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
        debugPrint(
            '[DB Provider] Table $table missing on insert, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
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
        debugPrint(
            '[DB Provider] Table $table missing on query, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
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

  /// Update records with error handling and retry
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
        debugPrint(
            '[DB Provider] Table $table missing on update, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
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

  /// Delete records with error handling and retry
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
        debugPrint(
            '[DB Provider] Table $table missing on delete, creating and retrying...');
        await rawExecute(DatabaseHealthChecker.requiredTables[table]!);
        // Retry once
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
