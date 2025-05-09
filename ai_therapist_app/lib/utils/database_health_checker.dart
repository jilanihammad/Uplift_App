import '../data/datasources/local/database_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHealthChecker {
  final DatabaseProvider dbProvider;
  DatabaseHealthChecker(this.dbProvider);

  // List of required tables and their creation SQL
  static final Map<String, String> requiredTables = {
    'sessions': '''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        title TEXT,
        summary TEXT,
        created_at TEXT,
        last_modified TEXT,
        is_synced INTEGER
      )
    ''',
    'messages': '''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        session_id TEXT,
        content TEXT,
        is_user INTEGER,
        timestamp TEXT,
        audio_url TEXT,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''',
    'conversation_memories': '''
      CREATE TABLE IF NOT EXISTS conversation_memories (
        id TEXT PRIMARY KEY,
        user_message TEXT NOT NULL,
        ai_response TEXT NOT NULL,
        metadata TEXT,
        timestamp TEXT NOT NULL
      )
    ''',
    'therapy_insights': '''
      CREATE TABLE IF NOT EXISTS therapy_insights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        insight TEXT NOT NULL,
        source TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''',
    'emotional_states': '''
      CREATE TABLE IF NOT EXISTS emotional_states (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emotion TEXT NOT NULL,
        intensity REAL NOT NULL,
        trigger TEXT,
        timestamp TEXT NOT NULL
      )
    ''',
    'user_progress': '''
      CREATE TABLE IF NOT EXISTS user_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        current_streak INTEGER,
        longest_streak INTEGER,
        total_points INTEGER,
        current_level INTEGER,
        last_activity_date TEXT
      )
    ''',
    'mood_logs': '''
      CREATE TABLE IF NOT EXISTS mood_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mood TEXT,
        timestamp TEXT,
        notes TEXT
      )
    ''',
    'conversations': '''
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        user_message TEXT NOT NULL,
        ai_response TEXT NOT NULL,
        metadata TEXT,
        timestamp TEXT NOT NULL
      )
    ''',
    'insights': '''
      CREATE TABLE IF NOT EXISTS insights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        insight TEXT NOT NULL,
        source TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''',
    'user_preferences': '''
      CREATE TABLE IF NOT EXISTS user_preferences (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''',
  };

  Future<void> runHealthCheck() async {
    try {
      for (final entry in requiredTables.entries) {
        try {
          final exists = await dbProvider.tableExists(entry.key);
          if (!exists) {
            debugPrint('[DB Health] Table missing: ${entry.key}, creating...');
            await dbProvider.rawExecute(entry.value);
            debugPrint('[DB Health] Table created: ${entry.key}');
          } else {
            debugPrint('[DB Health] Table exists: ${entry.key}');
          }
        } catch (e) {
          // Detect corruption or unrecoverable errors
          if (e is DatabaseException && e.toString().contains('malformed')) {
            debugPrint(
                '[DB Health] Database corruption detected while checking table: ${entry.key}');
            debugPrint('[DB Health] Error: $e');
            return;
          } else {
            debugPrint(
                '[DB Health] Error checking/creating table ${entry.key}: $e');
          }
        }
      }
      debugPrint('[DB Health] All required tables checked.');
    } catch (e, st) {
      debugPrint('[DB Health] Error during health check: $e\n$st');
    }
  }
}
