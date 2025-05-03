// lib/data/datasources/local/app_database.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// App database class using singleton pattern for SQLite database access
///
/// This class manages the local SQLite database with proper migration paths
/// when database schema changes are needed.
class AppDatabase {
  // Singleton pattern implementation
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  // Database instance
  static Database? _database;

  // Current database version - increment when schema changes
  static const int _databaseVersion = 4;

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
        onOpen: (db) {
          debugPrint('Database opened successfully');
        },
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
            title TEXT,
            summary TEXT,
            created_at TEXT,
            last_modified TEXT,
            is_synced INTEGER
          )
        ''');

        // Create messages table
        await txn.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            content TEXT,
            is_user INTEGER,
            timestamp TEXT,
            audio_url TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
          )
        ''');

        // Create user progress table
        await txn.execute('''
          CREATE TABLE user_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            current_streak INTEGER,
            longest_streak INTEGER,
            total_points INTEGER,
            current_level INTEGER,
            last_activity_date TEXT
          )
        ''');

        // Create mood logs table
        await txn.execute('''
          CREATE TABLE mood_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mood TEXT,
            timestamp TEXT,
            notes TEXT
          )
        ''');

        // Create conversations table (previously in DatabaseHelper)
        await txn.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            user_message TEXT NOT NULL,
            ai_response TEXT NOT NULL,
            metadata TEXT,
            timestamp TEXT NOT NULL
          )
        ''');

        // Create insights table (previously in DatabaseHelper)
        await txn.execute('''
          CREATE TABLE insights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            insight TEXT NOT NULL,
            source TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');

        // Create emotional_states table (previously in DatabaseHelper)
        await txn.execute('''
          CREATE TABLE emotional_states (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            emotion TEXT NOT NULL,
            intensity REAL NOT NULL,
            trigger TEXT,
            timestamp TEXT NOT NULL
          )
        ''');

        // Create user_preferences table (previously in DatabaseHelper)
        await txn.execute('''
          CREATE TABLE user_preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
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

        // Add future migrations here:
        // if (oldVersion < 5) await _migrateToV5(txn);
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

  /// Check if a table exists in the database
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
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      debugPrint('Database closed');
    }
  }

  // CRUD operations

  /// Insert a row into a table
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
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    try {
      final db = await database;
      return await db.transaction(action);
    } catch (e, stackTrace) {
      debugPrint('Transaction error: $e');
      _onError(e, stackTrace);
      rethrow;
    }
  }
}
