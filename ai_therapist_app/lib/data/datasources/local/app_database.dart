// lib/data/datasources/local/app_database.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  
  AppDatabase._internal();
  
  static Database? _database;
  
  // Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    
    // Initialize database
    _database = await _initDatabase();
    return _database!;
  }
  
  // Initialize database
  Future<Database> _initDatabase() async {
    // Initialize the appropriate database factory based on platform
    if (Platform.isWindows || Platform.isLinux) {
      // Initialize FFI for Windows/Linux
      sqfliteFfiInit();
      // Use the global variable, not a method of this class
      databaseFactory = databaseFactoryFfi;
    }
    
    // Get the database path
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'app_database.db');
    
    // Create database if it doesn't exist
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }
  
  // Create database tables
  Future<void> _createDatabase(Database db, int version) async {
    // Create sessions table
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE mood_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mood TEXT,
        timestamp TEXT,
        notes TEXT
      )
    ''');
  }
  
  // Insert a row into a table
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(
      table,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  // Query rows from a table
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    final db = await database;
    return await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
  }
  
  // Update a row in a table
  Future<int> update(
    String table,
    Map<String, dynamic> data, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(
      table,
      data,
      where: where,
      whereArgs: whereArgs,
    );
  }
  
  // Delete a row from a table
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }
  
  // Execute a raw SQL query
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }
}