// lib/data/datasources/local/app_database.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../di/interfaces/i_app_database.dart';
class AppDatabase implements IAppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();
  static Database? _database;
  static const int _databaseVersion = 9;
  static const String _databaseName = 'app_database.db';
  bool _isInitializing = false;
  final _onError = (e, stackTrace) {
  };
  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    // CRITICAL: Wait for up to 500ms to see if database becomes available
    for (int i = 0; i < 5; i++) {
      if (_database != null) return _database!;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_isInitializing) {
      int attempts = 0;
      while (_database == null && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
        if (attempts % 5 == 0) {
        }
      }
      if (_database != null) {
        return _database!;
      }
      _isInitializing = false;
    }
    _isInitializing = true;
    try {
      _database = await _initDatabase();
      return _database!;
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      _isInitializing = false;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }
  Future<Database> _initDatabase() async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _databaseName);
      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        onDowngrade:
            onDatabaseDowngradeDelete, // For development: delete and recreate on downgrade
        onConfigure: _onConfigureDatabase,
        onOpen: (db) {
        },
        singleInstance: true,
      );
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  Future<void> _createDatabase(Database db, int version) async {
    try {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT,
            summary TEXT,
            action_items TEXT,
            created_at TEXT,
            last_modified TEXT,
            is_synced INTEGER
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)');
        await txn.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            user_id TEXT NOT NULL,
            content TEXT,
            is_user INTEGER,
            timestamp TEXT,
            audio_url TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id)');
        await txn.execute('''
          CREATE TABLE user_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            current_streak INTEGER,
            longest_streak INTEGER,
            total_points INTEGER,
            current_level INTEGER,
            last_activity_date TEXT
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_user_progress_user_id ON user_progress(user_id)');
        await txn.execute('''
          CREATE TABLE mood_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            mood TEXT,
            timestamp TEXT,
            notes TEXT
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_mood_logs_user_id ON mood_logs(user_id)');
        await txn.execute('''
          CREATE TABLE mood_entries (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            client_entry_id TEXT NOT NULL,
            mood INTEGER NOT NULL,
            notes TEXT,
            logged_at TEXT NOT NULL,
            server_id TEXT,
            updated_at TEXT NOT NULL,
            is_pending INTEGER NOT NULL DEFAULT 1,
            last_synced_at TEXT,
            sync_error TEXT,
            UNIQUE(user_id, client_entry_id)
          )
        ''');
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_mood_entries_user_logged_at ON mood_entries (user_id, logged_at DESC)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_mood_entries_pending ON mood_entries (is_pending)',
        );
        await txn.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            user_message TEXT NOT NULL,
            ai_response TEXT NOT NULL,
            metadata TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id)');
        await txn.execute('''
          CREATE TABLE insights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            insight TEXT NOT NULL,
            source TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_insights_user_id ON insights(user_id)');
        await txn.execute('''
          CREATE TABLE emotional_states (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            emotion TEXT NOT NULL,
            intensity REAL NOT NULL,
            trigger TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_emotional_states_user_id ON emotional_states(user_id)');
        await txn.execute('''
          CREATE TABLE user_preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await txn.execute('''
          CREATE TABLE user_anchors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            anchor_text TEXT NOT NULL,
            normalized_text TEXT NOT NULL,
            anchor_type TEXT,
            confidence REAL DEFAULT 0.0,
            mention_count INTEGER NOT NULL DEFAULT 1,
            first_seen_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            first_session_index INTEGER NOT NULL DEFAULT 0,
            last_session_index INTEGER NOT NULL DEFAULT 0,
            last_prompted_session INTEGER NOT NULL DEFAULT -1,
            server_id TEXT,
            client_anchor_id TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(user_id, normalized_text),
            UNIQUE(user_id, client_anchor_id)
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_user_anchors_user_id ON user_anchors(user_id)');
        await txn.execute('''
          CREATE TABLE logs (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            level TEXT NOT NULL,
            message TEXT NOT NULL,
            source TEXT NOT NULL,
            data TEXT
          )
        ''');
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_logs_user_id ON logs(user_id)');
      });
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    try {
      await db.transaction((txn) async {
        if (oldVersion < 2) {
          await _migrateToV2(txn);
        }
        if (oldVersion < 3) {
          await _migrateToV3(txn);
        }
        if (oldVersion < 4) {
          await _migrateToV4(txn);
        }
        if (oldVersion < 5) {
          await _migrateToV5(txn);
        }
        if (oldVersion < 6) {
          await _migrateToV6(txn);
        }
        if (oldVersion < 7) {
          await _migrateToV7(txn);
        }
        if (oldVersion < 8) {
          await _migrateToV8(txn);
        }
        if (oldVersion < 9) {
          await _migrateToV9(txn);
        }
      });
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  Future<void> _migrateToV2(Transaction txn) async {
    await txn.execute('''
      ALTER TABLE messages ADD COLUMN audio_duration INTEGER DEFAULT 0
    ''');
    await txn.execute('''
      ALTER TABLE sessions ADD COLUMN is_archived INTEGER DEFAULT 0
    ''');
  }
  Future<void> _migrateToV3(Transaction txn) async {
    final convMemExists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['conversation_memories'],
    );
    if (convMemExists.isEmpty) {
      await txn.execute('''
        CREATE TABLE conversation_memories (
          id TEXT PRIMARY KEY,
          user_message TEXT NOT NULL,
          ai_response TEXT NOT NULL,
          metadata TEXT,
          timestamp TEXT NOT NULL
        )
      ''');
      final convExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['conversations'],
      );
      if (convExists.isNotEmpty) {
        await txn.execute('''
          INSERT INTO conversation_memories (id, user_message, ai_response, metadata, timestamp)
          SELECT id, user_message, ai_response, metadata, timestamp FROM conversations
        ''');
      }
    }
    final insightsExists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['therapy_insights'],
    );
    if (insightsExists.isEmpty) {
      await txn.execute('''
        CREATE TABLE therapy_insights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          insight TEXT NOT NULL,
          source TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');
      final oldInsightsExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['insights'],
      );
      if (oldInsightsExists.isNotEmpty) {
        await txn.execute('''
          INSERT INTO therapy_insights (id, insight, source, timestamp)
          SELECT id, insight, source, timestamp FROM insights
        ''');
      }
    }
    final emotionalStatesExists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['emotional_states'],
    );
    if (emotionalStatesExists.isEmpty) {
      await txn.execute('''
        CREATE TABLE emotional_states (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          emotion TEXT NOT NULL,
          intensity REAL NOT NULL,
          trigger TEXT,
          timestamp TEXT NOT NULL
        )
      ''');
    }
  }
  Future<void> _migrateToV4(Transaction txn) async {
    try {
      final convMemExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['conversation_memories'],
      );
      if (convMemExists.isNotEmpty) {
        await txn.execute(
            'ALTER TABLE conversation_memories RENAME TO conversation_memories_old');
        await txn.execute('''
          CREATE TABLE conversation_memories (
            id TEXT PRIMARY KEY,
            user_message TEXT NOT NULL,
            ai_response TEXT NOT NULL,
            metadata TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
        await txn.execute('''
          INSERT INTO conversation_memories 
            SELECT id, user_message, ai_response, metadata, timestamp 
            FROM conversation_memories_old
        ''');
        await txn.execute('DROP TABLE conversation_memories_old');
      } else {
        await txn.execute('''
          CREATE TABLE conversation_memories (
            id TEXT PRIMARY KEY,
            user_message TEXT NOT NULL,
            ai_response TEXT NOT NULL,
            metadata TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
      }
      final convExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['conversations'],
      );
      if (convExists.isNotEmpty) {
        final columns = await txn.rawQuery('PRAGMA table_info(conversations)');
        bool needsMigration = true;
        for (var column in columns) {
          if (column['name'] == 'user_message' ||
              column['name'] == 'ai_response') {
            needsMigration = false;
            break;
          }
        }
        if (needsMigration) {
          await txn
              .execute('ALTER TABLE conversations RENAME TO conversations_old');
          await txn.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              user_message TEXT NOT NULL,
              ai_response TEXT NOT NULL,
              metadata TEXT,
              timestamp TEXT NOT NULL
            )
          ''');
          await txn.execute('''
            INSERT INTO conversations 
              SELECT id, user_message, ai_response, metadata, timestamp 
              FROM conversations_old
          ''');
          await txn.execute('DROP TABLE conversations_old');
        }
      }
    } catch (e) {
      rethrow;
    }
  }
  Future<void> _migrateToV5(Transaction txn) async {
    try {
      await txn.execute('''
        ALTER TABLE sessions ADD COLUMN action_items TEXT
      ''');
    } catch (e) {
      rethrow;
    }
  }
  Future<void> _migrateToV6(Transaction txn) async {
    try {
      final anchorsExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['user_anchors'],
      );
      if (anchorsExists.isEmpty) {
        await txn.execute('''
          CREATE TABLE user_anchors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            anchor_text TEXT NOT NULL,
            normalized_text TEXT NOT NULL,
            anchor_type TEXT,
            confidence REAL DEFAULT 0.0,
            mention_count INTEGER NOT NULL DEFAULT 1,
            first_seen_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            first_session_index INTEGER NOT NULL DEFAULT 0,
            last_session_index INTEGER NOT NULL DEFAULT 0,
            last_prompted_session INTEGER NOT NULL DEFAULT -1,
            server_id TEXT,
            client_anchor_id TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            UNIQUE(normalized_text),
            UNIQUE(client_anchor_id)
          )
        ''');
      }
    } catch (e) {
      rethrow;
    }
  }
  Future<void> _migrateToV7(Transaction txn) async {
    Future<void> safeAlter(String statement) async {
      try {
        await txn.execute(statement);
      } catch (_) {}
    }
    try {
      await safeAlter('ALTER TABLE user_anchors ADD COLUMN server_id TEXT');
      await safeAlter(
          'ALTER TABLE user_anchors ADD COLUMN client_anchor_id TEXT');
      await safeAlter('ALTER TABLE user_anchors ADD COLUMN updated_at TEXT');
      await safeAlter(
          'ALTER TABLE user_anchors ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
      await txn.execute('''
        UPDATE user_anchors
        SET client_anchor_id = CASE
              WHEN client_anchor_id IS NULL OR client_anchor_id = '' THEN normalized_text
              ELSE client_anchor_id
            END,
            updated_at = CASE
              WHEN updated_at IS NULL OR updated_at = '' THEN last_seen_at
              ELSE updated_at
            END
      ''');
      await txn.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_user_anchors_client_id ON user_anchors(client_anchor_id)');
      await txn.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_user_anchors_normalized ON user_anchors(normalized_text)');
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<bool> tableExists(String tableName) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [tableName]);
      return result.isNotEmpty;
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      return false; // Safer to return false than throw
    }
  }
  @override
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    try {
      final db = await database;
      return await db.insert(
        table,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    try {
      final db = await database;
      return await db.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  @override
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      final db = await database;
      return await db.update(
        table,
        data,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  @override
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    try {
      final db = await database;
      return await db.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      final db = await database;
      return await db.rawQuery(sql, arguments);
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  @override
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      final db = await database;
      return await db.rawUpdate(sql, arguments);
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    try {
      final db = await database;
      int retries = 0;
      const maxRetries = 3;
      const retryDelay = Duration(milliseconds: 500);
      while (true) {
        try {
          return await db.transaction(action);
        } catch (e) {
          if (e.toString().contains('database is locked') &&
              retries < maxRetries) {
            retries++;
            await Future.delayed(retryDelay);
          } else {
            rethrow;
          }
        }
      }
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }
  Future<void> _onConfigureDatabase(Database db) async {
    try {
      await db.execute('PRAGMA foreign_keys = ON;');
      try {
        await db.rawQuery(
            'PRAGMA busy_timeout = 10000;'); // Note: rawQuery usually expects a result
      } catch (e) {
        try {
          await db.execute('PRAGMA busy_timeout = 10000;');
        } catch (_) {}
      }
      try {
        final List<Map<String, dynamic>> journalModeResult =
            await db.rawQuery('PRAGMA journal_mode');
        if (journalModeResult.isNotEmpty &&
            journalModeResult.first.values.first.toString().toLowerCase() ==
                'wal') {
        } else {
          await db.rawQuery('PRAGMA journal_mode = WAL;');
        }
      } catch (_) {}
      await db.execute('PRAGMA synchronous = NORMAL;');
      await db.execute('PRAGMA cache_size = 10000;');
      await db.execute('PRAGMA temp_store = MEMORY;');
    } catch (e, stackTrace) {
      debugPrintStack(
          label: 'Stack trace for _onConfigureDatabase error',
          stackTrace: stackTrace);
      rethrow;
    }
  }
  Future<void> _migrateToV8(Transaction txn) async {
    final tableExists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['mood_entries'],
    );
    if (tableExists.isEmpty) {
      await txn.execute('''
        CREATE TABLE mood_entries (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          client_entry_id TEXT NOT NULL,
          mood INTEGER NOT NULL,
          notes TEXT,
          logged_at TEXT NOT NULL,
          server_id TEXT,
          updated_at TEXT NOT NULL,
          is_pending INTEGER NOT NULL DEFAULT 1,
          last_synced_at TEXT,
          sync_error TEXT,
          UNIQUE(user_id, client_entry_id)
        )
      ''');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_mood_entries_user_logged_at ON mood_entries (user_id, logged_at DESC)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_mood_entries_pending ON mood_entries (is_pending)',
      );
    }
  }
  Future<void> _migrateToV9(Transaction txn) async {
    const tableDefinitions = <String, String>{
      'sessions': '''
        CREATE TABLE sessions (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          title TEXT,
          summary TEXT,
          action_items TEXT,
          created_at TEXT,
          last_modified TEXT,
          is_synced INTEGER
        )
      ''',
      'messages': '''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          session_id TEXT,
          user_id TEXT NOT NULL,
          content TEXT,
          is_user INTEGER,
          timestamp TEXT,
          audio_url TEXT,
          FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
        )
      ''',
      'mood_logs': '''
        CREATE TABLE mood_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          mood TEXT,
          timestamp TEXT,
          notes TEXT
        )
      ''',
      'mood_entries': '''
        CREATE TABLE mood_entries (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          client_entry_id TEXT NOT NULL,
          mood INTEGER NOT NULL,
          notes TEXT,
          logged_at TEXT NOT NULL,
          server_id TEXT,
          updated_at TEXT NOT NULL,
          is_pending INTEGER NOT NULL DEFAULT 1,
          last_synced_at TEXT,
          sync_error TEXT,
          UNIQUE(user_id, client_entry_id)
        )
      ''',
      'conversation_memories': '''
        CREATE TABLE conversation_memories (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          user_message TEXT NOT NULL,
          ai_response TEXT NOT NULL,
          metadata TEXT,
          timestamp TEXT NOT NULL
        )
      ''',
      'conversations': '''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          user_message TEXT NOT NULL,
          ai_response TEXT NOT NULL,
          metadata TEXT,
          timestamp TEXT NOT NULL
        )
      ''',
      'therapy_insights': '''
        CREATE TABLE therapy_insights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          insight TEXT NOT NULL,
          source TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''',
      'insights': '''
        CREATE TABLE insights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          insight TEXT NOT NULL,
          source TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''',
      'emotional_states': '''
        CREATE TABLE emotional_states (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          emotion TEXT NOT NULL,
          intensity REAL NOT NULL,
          trigger TEXT,
          timestamp TEXT NOT NULL
        )
      ''',
      'user_progress': '''
        CREATE TABLE user_progress (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          current_streak INTEGER,
          longest_streak INTEGER,
          total_points INTEGER,
          current_level INTEGER,
          last_activity_date TEXT
        )
      ''',
      'user_anchors': '''
        CREATE TABLE user_anchors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          anchor_text TEXT NOT NULL,
          normalized_text TEXT NOT NULL,
          anchor_type TEXT,
          confidence REAL DEFAULT 0.0,
          mention_count INTEGER NOT NULL DEFAULT 1,
          first_seen_at TEXT NOT NULL,
          last_seen_at TEXT NOT NULL,
          first_session_index INTEGER NOT NULL DEFAULT 0,
          last_session_index INTEGER NOT NULL DEFAULT 0,
          last_prompted_session INTEGER NOT NULL DEFAULT -1,
          server_id TEXT,
          client_anchor_id TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          UNIQUE(user_id, normalized_text),
          UNIQUE(user_id, client_anchor_id)
        )
      ''',
      'logs': '''
        CREATE TABLE logs (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          level TEXT NOT NULL,
          message TEXT NOT NULL,
          source TEXT NOT NULL,
          data TEXT
        )
      ''',
    };
    for (final tableName in tableDefinitions.keys) {
      await txn.execute('DROP TABLE IF EXISTS $tableName');
    }
    for (final entry in tableDefinitions.entries) {
      await txn.execute(entry.value);
    }
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_mood_logs_user_id ON mood_logs(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_mood_entries_user_logged_at ON mood_entries (user_id, logged_at DESC)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_mood_entries_pending ON mood_entries (is_pending)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_conversation_memories_user_id ON conversation_memories(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_therapy_insights_user_id ON therapy_insights(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_insights_user_id ON insights(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_emotional_states_user_id ON emotional_states(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_user_progress_user_id ON user_progress(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_user_anchors_user_id ON user_anchors(user_id)');
    await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_logs_user_id ON logs(user_id)');
  }
}
