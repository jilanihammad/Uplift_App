import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ai_therapist_app/data/models/log_entry.dart';
import 'package:ai_therapist_app/data/datasources/local/app_database.dart';
import 'package:ai_therapist_app/services/user_context_service.dart';

class LogRepository {
  final AppDatabase _database;
  final UserContextService _userContextService;
  final _uuid = const Uuid();
  final int _maxLogEntries = 1000; // Maximum number of log entries to keep

  LogRepository({
    required AppDatabase database,
    UserContextService? userContextService,
  })  : _database = database,
        _userContextService = userContextService ?? UserContextService();

  Future<String> _requireUserId() async {
    final userId = await _userContextService.getActiveUserId();
    if (userId.isEmpty) {
      throw Exception('No user ID available for log persistence');
    }
    return userId;
  }

  Future<void> log({
    required LogLevel level,
    required String message,
    required String source,
    Map<String, dynamic>? data,
  }) async {
    try {
      // In debug mode, print to console
      if (kDebugMode) {
        debugPrint(
            '${level.toString().split('.').last.toUpperCase()}: $message');
      }

      // Create log entry
      final entry = LogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        level: level,
        message: message,
        source: source,
        data: data,
      );

      // Save to database
      await _saveLogEntry(entry);

      // Clean up old logs periodically
      if (entry.id.hashCode % 20 == 0) {
        // Randomly cleanup ~5% of the time
        _cleanupOldLogs();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving log entry: $e');
      }
    }
  }

  Future<void> _saveLogEntry(LogEntry entry) async {
    final db = await _database.database;
    final userId = await _requireUserId();
    await db.insert('logs', {
      'id': entry.id,
      'user_id': userId,
      'timestamp': entry.timestamp.toIso8601String(),
      'level': entry.level.toString().split('.').last,
      'message': entry.message,
      'source': entry.source,
      'data': entry.data != null ? jsonEncode(entry.data) : null,
    });
  }

  Future<void> _cleanupOldLogs() async {
    try {
      final db = await _database.database;
      final userId = await _requireUserId();
      final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM logs WHERE user_id = ?',
            [userId],
          )) ??
          0;

      if (count > _maxLogEntries) {
        // Delete oldest logs keeping only _maxLogEntries
        final deleteCount = count - _maxLogEntries;
        await db.rawDelete('''
          DELETE FROM logs
          WHERE user_id = ? AND id IN (
            SELECT id FROM logs
            WHERE user_id = ?
            ORDER BY timestamp ASC
            LIMIT ?
          )
        ''', [userId, userId, deleteCount]);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error cleaning up logs: $e');
      }
    }
  }

  Future<List<LogEntry>> getRecentLogs({int limit = 100}) async {
    try {
      final db = await _database.database;
      final userId = await _requireUserId();
      final logs = await db.query(
        'logs',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
        limit: limit,
      );

      return logs.map((log) {
        return LogEntry(
          id: log['id'] as String,
          timestamp: DateTime.parse(log['timestamp'] as String),
          level: LogLevel.values.firstWhere(
            (l) => l.toString().split('.').last == log['level'],
            orElse: () => LogLevel.info,
          ),
          message: log['message'] as String,
          source: log['source'] as String,
          data: log['data'] != null ? jsonDecode(log['data'] as String) : null,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting logs: $e');
      }
      return [];
    }
  }

  // Clear all logs
  Future<void> clearLogs() async {
    try {
      final db = await _database.database;
      final userId = await _requireUserId();
      await db.delete('logs', where: 'user_id = ?', whereArgs: [userId]);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error clearing logs: $e');
      }
    }
  }
}
