// lib/data/datasources/local/app_database.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../di/interfaces/i_app_database.dart';

/// App database class using singleton pattern for SQLite database access
///
/// This class manages the local SQLite database with proper migration paths
/// when database schema changes are needed.
class AppDatabase implements IAppDatabase {
  // Singleton pattern implementation
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  // Database instance
  static Database? _database;

  // Current database version - increment when schema changes
  static const int _databaseVersion = 9;

  // Database file name
  static const String _databaseName = 'app_database.db';

  // Flag to prevent concurrent initialization
  bool _isInitializing = false;

  // Error handling callback
  final _onError = (e, stackTrace) {
    debugPrint('Database error: $e');
    debugPrint('Stack trace: $stackTrace');
  };

  /// Get the database instance
  @override
  Future<Database> get database async {
    if (_database != null) return _database!;

    // CRITICAL: Wait for up to 500ms to see if database becomes available
    // This should help avoid database locked errors
    for (int i = 0; i < 5; i++) {
      if (_database != null) return _database!;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Prevent concurrent initialization with better timeout handling
    if (_isInitializing) {
      debugPrint(
          'WARNING: Database initialization already in progress, waiting...');
      // Wait until initialization is complete or timeout
      int attempts = 0;
      while (_database == null && attempts < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
        if (attempts % 5 == 0) {
          debugPrint(
              'Still waiting for database initialization... ($attempts/20)');
        }
      }

      if (_database != null) {
        debugPrint('Database initialization completed while waiting');
        return _database!;
      }

      debugPrint(
          'ERROR: Database initialization timed out after ${attempts * 100}ms');
      // Don't throw an exception - instead create a new instance
      _isInitializing = false;
    }

    // Initialize database
    _isInitializing = true;
    try {
      debugPrint('Initializing database...');
      _database = await _initDatabase();
      debugPrint('Database initialization completed successfully');
      return _database!;
    } catch (e, stackTrace) {
      debugPrint('ERROR initializing database: $e');
      _onError(e, stackTrace);
      _isInitializing = false;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    try {
      // Initialize the appropriate database factory based on platform
      if (Platform.isWindows || Platform.isLinux) {
        debugPrint('Initializing FFI for Windows/Linux');
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // Get the database path
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _databaseName);

      debugPrint('Opening database at $path (version $_databaseVersion)');

      // Open database with versioning and migrations
      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        onDowngrade:
            onDatabaseDowngradeDelete, // For development: delete and recreate on downgrade
        onConfigure: _onConfigureDatabase,
        onOpen: (db) {
          debugPrint('Database opened successfully. Path: ${db.path}');
        },
        singleInstance: true,
      );
    } catch (e, stackTrace) {
      debugPrint('Failed to initialize database: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Create initial database schema (version 1)
  Future<void> _createDatabase(Database db, int version) async {
    debugPrint('Creating database schema (version: $version)');

    try {
      // Start a transaction for atomicity
      await db.transaction((txn) async {
        // Create sessions table
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

        // Create messages table
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

        // Create user progress table
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

        // Create mood logs table (legacy)
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

        // Create mood entries table for persistence + sync
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

        // Create conversations table (previously in DatabaseHelper)
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

        // Create insights table (previously in DatabaseHelper)
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

        // Create emotional_states table (previously in DatabaseHelper)
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

        // Create user_preferences table (previously in DatabaseHelper)
        await txn.execute('''
          CREATE TABLE user_preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        // Create user_anchors table for key personal anchors
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

        // Create logs table for diagnostics
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

      debugPrint('Database schema created successfully');
    } catch (e, stackTrace) {
      debugPrint('Error creating database schema: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Upgrade database schema when version changes
  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    debugPrint('Upgrading database from version $oldVersion to $newVersion');

    try {
      // Run migrations in a transaction for atomicity
      await db.transaction((txn) async {
        // Apply migrations sequentially
        if (oldVersion < 2) {
          // Migration to version 2
          await _migrateToV2(txn);
        }

        // Migration to version 3
        if (oldVersion < 3) {
          await _migrateToV3(txn);
        }

        // Migration to version 4
        if (oldVersion < 4) {
          await _migrateToV4(txn);
        }

        // Migration to version 5: Add action_items column to sessions table
        if (oldVersion < 5) {
          await _migrateToV5(txn);
        }

        // Migration to version 6: Add user_anchors table
        if (oldVersion < 6) {
          await _migrateToV6(txn);
        }

        // Migration to version 7: Extend user_anchors for backend sync metadata
        if (oldVersion < 7) {
          await _migrateToV7(txn);
        }

        // Migration to version 8: Create mood_entries table for sync persistence
        if (oldVersion < 8) {
          await _migrateToV8(txn);
        }

        // Migration to version 9: Add user_id columns and reset local data
        if (oldVersion < 9) {
          await _migrateToV9(txn);
        }
      });

      debugPrint('Database upgraded successfully to version $newVersion');
    } catch (e, stackTrace) {
      debugPrint('Error upgrading database: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Migration to version 2: Add audio_duration field to messages table
  Future<void> _migrateToV2(Transaction txn) async {
    debugPrint('Applying migration to version 2...');

    // Add audio_duration column to messages table
    await txn.execute('''
      ALTER TABLE messages ADD COLUMN audio_duration INTEGER DEFAULT 0
    ''');

    // Add is_archived column to sessions table with a default value of 0 (false)
    await txn.execute('''
      ALTER TABLE sessions ADD COLUMN is_archived INTEGER DEFAULT 0
    ''');

    debugPrint('Migration to version 2 completed');
  }

  /// Migration to version 3: Add conversation_memories, therapy_insights tables for MemoryService
  Future<void> _migrateToV3(Transaction txn) async {
    debugPrint('Applying migration to version 3...');

    // Check if conversation_memories table already exists
    final convMemExists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['conversation_memories'],
    );

    // Create conversation_memories table if it doesn't exist
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
      debugPrint('Created conversation_memories table');

      // Copy data from conversations to conversation_memories (if conversations exists)
      final convExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['conversations'],
      );

      if (convExists.isNotEmpty) {
        await txn.execute('''
          INSERT INTO conversation_memories (id, user_message, ai_response, metadata, timestamp)
          SELECT id, user_message, ai_response, metadata, timestamp FROM conversations
        ''');
        debugPrint('Migrated data from conversations to conversation_memories');
      }
    }

    // Check if therapy_insights table already exists
    final insightsExists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['therapy_insights'],
    );

    // Create therapy_insights table if it doesn't exist
    if (insightsExists.isEmpty) {
      await txn.execute('''
        CREATE TABLE therapy_insights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          insight TEXT NOT NULL,
          source TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');
      debugPrint('Created therapy_insights table');

      // Copy data from insights to therapy_insights (if insights exists)
      final oldInsightsExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['insights'],
      );

      if (oldInsightsExists.isNotEmpty) {
        await txn.execute('''
          INSERT INTO therapy_insights (id, insight, source, timestamp)
          SELECT id, insight, source, timestamp FROM insights
        ''');
        debugPrint('Migrated data from insights to therapy_insights');
      }
    }

    // Ensure emotional_states table exists
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
      debugPrint('Created emotional_states table');
    }

    debugPrint('Migration to version 3 completed');
  }

  /// Migration to version 4: Fix column names in conversation_memories table
  Future<void> _migrateToV4(Transaction txn) async {
    debugPrint('Applying migration to version 4...');

    try {
      // Check if conversation_memories table exists
      final convMemExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['conversation_memories'],
      );

      if (convMemExists.isNotEmpty) {
        // Rename the existing table
        await txn.execute(
            'ALTER TABLE conversation_memories RENAME TO conversation_memories_old');

        // Create the new table with correct column names
        await txn.execute('''
          CREATE TABLE conversation_memories (
            id TEXT PRIMARY KEY,
            user_message TEXT NOT NULL,
            ai_response TEXT NOT NULL,
            metadata TEXT,
            timestamp TEXT NOT NULL
          )
        ''');

        // Copy data from old table to new table
        await txn.execute('''
          INSERT INTO conversation_memories 
            SELECT id, user_message, ai_response, metadata, timestamp 
            FROM conversation_memories_old
        ''');

        // Drop the old table
        await txn.execute('DROP TABLE conversation_memories_old');

        debugPrint('Fixed column names in conversation_memories table');
      } else {
        // Create the table with correct column names if it doesn't exist
        await txn.execute('''
          CREATE TABLE conversation_memories (
            id TEXT PRIMARY KEY,
            user_message TEXT NOT NULL,
            ai_response TEXT NOT NULL,
            metadata TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
        debugPrint(
            'Created conversation_memories table with correct column names');
      }

      // Similarly for the conversations table (legacy table)
      final convExists = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['conversations'],
      );

      if (convExists.isNotEmpty) {
        // Check column names in conversations table
        final columns = await txn.rawQuery('PRAGMA table_info(conversations)');
        bool needsMigration = true;

        // Check if user_message and ai_response columns already exist
        for (var column in columns) {
          if (column['name'] == 'user_message' ||
              column['name'] == 'ai_response') {
            needsMigration = false;
            break;
          }
        }

        if (needsMigration) {
          // Rename the existing table
          await txn
              .execute('ALTER TABLE conversations RENAME TO conversations_old');

          // Create the new table with correct column names
          await txn.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              user_message TEXT NOT NULL,
              ai_response TEXT NOT NULL,
              metadata TEXT,
              timestamp TEXT NOT NULL
            )
          ''');

          // Copy data from old table to new table
          await txn.execute('''
            INSERT INTO conversations 
              SELECT id, user_message, ai_response, metadata, timestamp 
              FROM conversations_old
          ''');

          // Drop the old table
          await txn.execute('DROP TABLE conversations_old');

          debugPrint('Fixed column names in conversations table');
        }
      }
    } catch (e) {
      debugPrint('Error during migration to version 4: $e');
      rethrow;
    }

    debugPrint('Migration to version 4 completed');
  }

  /// Migration to version 5: Add action_items column to sessions table
  Future<void> _migrateToV5(Transaction txn) async {
    debugPrint('Applying migration to version 5...');

    try {
      // Add action_items column to sessions table
      await txn.execute('''
        ALTER TABLE sessions ADD COLUMN action_items TEXT
      ''');
      debugPrint('Added action_items column to sessions table');
    } catch (e) {
      debugPrint('Error during migration to version 5: $e');
      rethrow;
    }

    debugPrint('Migration to version 5 completed');
  }

  /// Migration to version 6: Create user_anchors table if missing
  Future<void> _migrateToV6(Transaction txn) async {
    debugPrint('Applying migration to version 6...');

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
        debugPrint('Created user_anchors table');
      }
    } catch (e) {
      debugPrint('Error during migration to version 6: $e');
      rethrow;
    }

    debugPrint('Migration to version 6 completed');
  }

  /// Migration to version 7: Extend user_anchors with sync metadata columns
  Future<void> _migrateToV7(Transaction txn) async {
    debugPrint('Applying migration to version 7...');

    Future<void> safeAlter(String statement) async {
      try {
        await txn.execute(statement);
      } catch (e) {
        debugPrint('Migration v7: ignoring alter error for "$statement": $e');
      }
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

      debugPrint('Migration to version 7 completed');
    } catch (e) {
      debugPrint('Error during migration to version 7: $e');
      rethrow;
    }
  }

  /// Check if a table exists in the database
  @override
  Future<bool> tableExists(String tableName) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [tableName]);
      return result.isNotEmpty;
    } catch (e, stackTrace) {
      debugPrint('Error checking if table $tableName exists: $e');
      _onError(e, stackTrace);
      return false; // Safer to return false than throw
    }
  }

  /// Close the database connection
  @override
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      debugPrint('Database closed');
    }
  }

  // CRUD operations

  /// Insert a row into a table
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
      debugPrint('Error inserting into $table: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Query rows from a table
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
      debugPrint('Error querying $table: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Update a row in a table
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
      debugPrint('Error updating $table: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Delete a row from a table
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
      debugPrint('Error deleting from $table: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Execute a raw SQL query
  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      final db = await database;
      return await db.rawQuery(sql, arguments);
    } catch (e, stackTrace) {
      debugPrint('Error executing raw query: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Execute a raw SQL command
  @override
  Future<int> rawExecute(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    try {
      final db = await database;
      return await db.rawUpdate(sql, arguments);
    } catch (e, stackTrace) {
      debugPrint('Error executing raw command: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Execute multiple operations in a transaction
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    try {
      final db = await database;

      // Add retry logic for transactions to handle database locks
      int retries = 0;
      const maxRetries = 3;
      const retryDelay = Duration(milliseconds: 500);

      while (true) {
        try {
          return await db.transaction(action);
        } catch (e) {
          // If this is a database locked error and we haven't exceeded max retries
          if (e.toString().contains('database is locked') &&
              retries < maxRetries) {
            retries++;
            debugPrint(
                'Database locked, retrying transaction (attempt $retries/$maxRetries)...');
            await Future.delayed(retryDelay);
          } else {
            // If it's not a lock error or we've exceeded retries, rethrow
            rethrow;
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Transaction error: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }

  Future<void> _onConfigureDatabase(Database db) async {
    debugPrint('Configuring database...');
    try {
      await db.execute('PRAGMA foreign_keys = ON;');
      debugPrint('PRAGMA foreign_keys = ON executed.');

      // Try setting busy_timeout using rawQuery, and catch potential errors
      try {
        await db.rawQuery(
            'PRAGMA busy_timeout = 10000;'); // Note: rawQuery usually expects a result
        debugPrint(
            'PRAGMA busy_timeout = 10000 attempt via rawQuery successful (or did not throw).');
      } catch (e) {
        debugPrint(
            'Error attempting to set PRAGMA busy_timeout via rawQuery: $e. Trying execute as fallback.');
        // Fallback to execute if rawQuery fails for a set-only PRAGMA (less likely to work if rawQuery failed)
        try {
          await db.execute('PRAGMA busy_timeout = 10000;');
          debugPrint(
              'PRAGMA busy_timeout = 10000 attempt via execute successful.');
        } catch (e2) {
          debugPrint(
              'Error attempting to set PRAGMA busy_timeout via execute: $e2. This PRAGMA might not be settable this way or is not supported.');
        }
      }

      // PRAGMA journal_mode = WAL
      try {
        final List<Map<String, dynamic>> journalModeResult =
            await db.rawQuery('PRAGMA journal_mode');
        if (journalModeResult.isNotEmpty &&
            journalModeResult.first.values.first.toString().toLowerCase() ==
                'wal') {
          debugPrint('PRAGMA journal_mode is WAL.');
        } else {
          await db.execute('PRAGMA journal_mode = WAL;');
          debugPrint('Attempted to set PRAGMA journal_mode = WAL explicitly.');
          final List<Map<String, dynamic>> journalModeResultAfterSet =
              await db.rawQuery('PRAGMA journal_mode');
          debugPrint(
              'PRAGMA journal_mode after explicit set: $journalModeResultAfterSet');
        }
      } catch (e) {
        debugPrint(
            'Error setting/checking PRAGMA journal_mode: $e. This might be okay if singleInstance=true handles it.');
      }

      await db.execute('PRAGMA synchronous = NORMAL;');
      debugPrint('PRAGMA synchronous = NORMAL executed.');

      await db.execute('PRAGMA cache_size = 10000;');
      debugPrint('PRAGMA cache_size = 10000 executed.');

      await db.execute('PRAGMA temp_store = MEMORY;');
      debugPrint('PRAGMA temp_store = MEMORY executed.');
    } catch (e, stackTrace) {
      debugPrint('!!! Critical error during _onConfigureDatabase: $e');
      debugPrintStack(
          label: 'Stack trace for _onConfigureDatabase error',
          stackTrace: stackTrace);
      // It's important to rethrow if configuration fails fundamentally,
      // otherwise the app might proceed with a misconfigured database.
      rethrow;
    }
    debugPrint('Database configuration complete (or attempted).');
  }

  /// Migration to version 8: Create mood_entries table for persistent mood tracking
  Future<void> _migrateToV8(Transaction txn) async {
    debugPrint('Applying migration to version 8...');

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
      debugPrint('Created mood_entries table');
    } else {
      debugPrint('mood_entries table already exists, skipping creation');
    }

    debugPrint('Migration to version 8 completed');
  }

  /// Migration to version 9: add user_id scoping and reset local caches
  Future<void> _migrateToV9(Transaction txn) async {
    debugPrint('Applying migration to version 9 (user data isolation)...');

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
      await txn.execute('DROP TABLE IF EXISTS ' + tableName);
    }

    for (final entry in tableDefinitions.entries) {
      await txn.execute(entry.value);
    }

    // Recreate indexes for user-scoped lookups
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

    debugPrint('Migration to version 9 completed; local caches were reset.');
  }
}
