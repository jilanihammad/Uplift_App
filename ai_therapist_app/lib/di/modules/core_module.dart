// lib/di/modules/core_module.dart

import 'package:get_it/get_it.dart';
import 'dart:typed_data';
import '../interfaces/interfaces.dart';
import '../../services/config_service.dart';
import '../../services/audio_settings.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/prefs_manager.dart';
import '../../data/datasources/local/database_provider.dart';
import '../../utils/connectivity_checker.dart';
import '../../utils/database_helper.dart';
import '../interfaces/i_database_operation_manager.dart';
import '../interfaces/i_app_database.dart';
import '../interfaces/i_audio_settings.dart';

/// Core dependency module
/// Registers fundamental services that other services depend on
class CoreModule {
  static Future<void> register(GetIt locator) async {
    // Prevent duplicate registration
    if (locator.isRegistered<IConfigService>()) {
      return;
    }

    // Register AudioSettings early, before any services that might depend on it
    locator.registerLazySingleton<IAudioSettings>(
      () => AudioSettings(),
    );

    // Register utilities first (no dependencies)
    locator.registerLazySingleton<ConnectivityChecker>(
      () => ConnectivityChecker(),
    );

    // Register data sources (minimal dependencies)
    locator.registerSingleton<AppDatabase>(AppDatabase());

    locator.registerLazySingleton<DatabaseProvider>(
      () => DatabaseProvider(),
    );

    // Register and initialize PrefsManager
    locator.registerLazySingleton<PrefsManager>(() => PrefsManager());
    final prefsManager = locator<PrefsManager>();
    await prefsManager.init();

    // Register config service and initialize
    final configService = ConfigService();
    await configService.init();
    locator.registerSingleton<ConfigService>(configService);

    // Register adapter that bridges ConfigService to IConfigService
    locator.registerSingleton<IConfigService>(
      _ConfigServiceAdapter(configService),
    );

    // Register API client with configService dependency
    final apiClient = ApiClient(configService: configService);
    locator.registerSingleton<ApiClient>(apiClient);

    // Register ApiClient as IApiClient directly (no adapter needed)
    locator.registerSingleton<IApiClient>(apiClient);

    // Register adapter that bridges AppDatabase to IDatabase
    locator.registerSingleton<IDatabase>(
      _DatabaseAdapter(locator<AppDatabase>()),
    );

    // Register AppDatabase as IAppDatabase interface
    locator.registerSingleton<IAppDatabase>(
      locator<AppDatabase>(),
    );

    // Register DatabaseOperationManager and its interface
    locator.registerSingleton<DatabaseOperationManager>(
      DatabaseOperationManager(),
    );
    locator.registerSingleton<IDatabaseOperationManager>(
      locator<DatabaseOperationManager>(),
    );

    // Verify critical registrations succeeded
    assert(locator.isRegistered<IAudioSettings>(),
        'IAudioSettings must be registered in CoreModule');
  }

  static void registerMocks(GetIt locator) {
    // Register mock implementations for testing
    // This will be used during testing to provide mock services

    // Mock config service
    locator.registerSingleton<IConfigService>(_MockConfigService());

    // Mock API client
    locator.registerSingleton<IApiClient>(_MockApiClient());

    // Mock database
    locator.registerSingleton<IDatabase>(_MockDatabase());
  }
}

// Mock implementations for testing
class _MockConfigService implements IConfigService {
  @override
  String get environment => 'test';

  @override
  bool get isProduction => false;

  @override
  bool get isDevelopment => false;

  @override
  bool get isDebug => true;

  @override
  String get apiBaseUrl => 'http://localhost:8000';

  @override
  String get websocketUrl => 'ws://localhost:8000/ws';

  @override
  Duration get apiTimeout => const Duration(seconds: 30);

  @override
  int get maxRetries => 3;

  @override
  String? get googleClientId => 'mock-google-client-id';

  @override
  String? get firebaseApiKey => 'mock-firebase-api-key';

  @override
  String? get firebaseProjectId => 'mock-firebase-project';

  @override
  String? get openAiApiKey => 'mock-openai-key';

  @override
  String? get groqApiKey => 'mock-groq-key';

  @override
  String? get stripePublishableKey => 'mock-stripe-key';

  @override
  bool get enableVoiceRecording => true;

  @override
  bool get enableOfflineMode => true;

  @override
  bool get enableAnalytics => false;

  @override
  bool get enableCrashReporting => false;

  @override
  bool get enableRNNoise => true;

  @override
  int get audioSampleRate => 16000;

  @override
  String get audioFormat => 'wav';

  @override
  int get maxRecordingDuration => 300;

  @override
  int get sessionTimeoutMinutes => 30;

  @override
  int get maxConcurrentSessions => 5;

  @override
  String get databaseName => 'test_db';

  @override
  int get databaseVersion => 1;

  @override
  bool get enableDatabaseLogging => false;

  @override
  String get logLevel => 'debug';

  @override
  bool get enableFileLogging => false;

  @override
  String? get loggingEndpoint => null;

  @override
  Duration get cacheTimeout => const Duration(minutes: 30);

  @override
  int get maxCacheSize => 100;

  @override
  bool validateConfiguration() => true;

  @override
  List<String> getMissingRequiredConfig() => [];

  @override
  Future<void> refreshConfiguration() async {}

  @override
  Future<void> updateConfiguration(String key, dynamic value) async {}

  @override
  Future<void> initialize() async {}

  @override
  bool get isInitialized => true;
}

class _MockApiClient implements IApiClient {
  @override
  Future<Map<String, dynamic>> get(String endpoint,
      {Map<String, String>? headers, Map<String, dynamic>? queryParams}) async {
    return {'status': 'success', 'data': {}};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data,
      {Map<String, String>? headers}) async {
    return {'status': 'success', 'data': data};
  }

  @override
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data,
      {Map<String, String>? headers}) async {
    return {'status': 'success', 'data': data};
  }

  @override
  Future<Map<String, dynamic>> delete(String endpoint,
      {Map<String, String>? headers}) async {
    return {'status': 'success'};
  }

  @override
  Future<Map<String, dynamic>> uploadFile(
      String endpoint, String fieldName, List<int> fileData, String fileName,
      {Map<String, String>? headers,
      Map<String, String>? additionalFields}) async {
    return {'status': 'success', 'file_url': 'mock://file.url'};
  }

  @override
  Future<Uint8List> downloadFile(String url) async {
    return Uint8List(0);
  }

  @override
  void setAuthToken(String token) {}

  @override
  void clearAuthToken() {}

  @override
  String? get authToken => 'mock-token';

  @override
  String get baseUrl => 'http://localhost:8000';

  @override
  void setBaseUrl(String url) {}

  @override
  void setTimeout(Duration timeout) {}

  @override
  Future<bool> checkConnection() async => true;

  @override
  bool get isConnected => true;

  @override
  Stream<String> get errorStream => Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}
}

class _MockDatabase implements IDatabase {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  bool get isOpen => true;

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    return await action();
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> query(String table,
      {List<String>? columns,
      String? where,
      List<dynamic>? whereArgs,
      String? orderBy,
      int? limit,
      int? offset}) async {
    return [];
  }

  @override
  Future<int> update(String table, Map<String, dynamic> data,
      {String? where, List<dynamic>? whereArgs}) async {
    return 1;
  }

  @override
  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<dynamic>? arguments]) async {
    return [];
  }

  @override
  Future<int> rawInsert(String sql, [List<dynamic>? arguments]) async {
    return 1;
  }

  @override
  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]) async {
    return 1;
  }

  @override
  Future<int> rawDelete(String sql, [List<dynamic>? arguments]) async {
    return 1;
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {}

  @override
  Future<bool> tableExists(String tableName) async => true;

  @override
  Future<List<String>> getTableNames() async => [];

  @override
  Future<void> runMigration(int fromVersion, int toVersion) async {}

  @override
  int get version => 1;

  @override
  Future<void> batch(Future<void> Function() operations) async {
    await operations();
  }

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<Map<String, dynamic>> getStats() async => {};
}

// Adapter classes to bridge existing services to new interfaces
class _ConfigServiceAdapter implements IConfigService {
  final ConfigService _configService;

  _ConfigServiceAdapter(this._configService);

  @override
  String get environment =>
      _configService.isProductionMode ? 'production' : 'development';

  @override
  bool get isProduction => _configService.isProductionMode;

  @override
  bool get isDevelopment => !_configService.isProductionMode;

  @override
  bool get isDebug => !_configService.isProductionMode;

  @override
  String get apiBaseUrl => _configService.llmApiEndpoint;

  @override
  String get websocketUrl =>
      _configService.llmApiEndpoint.replaceFirst('http', 'ws');

  @override
  Duration get apiTimeout => const Duration(seconds: 30);

  @override
  int get maxRetries => 3;

  @override
  String? get googleClientId => null; // Add to ConfigService if needed

  @override
  String? get firebaseApiKey => _configService.firebaseApiKey;

  @override
  String? get firebaseProjectId => _configService.firebaseProjectId;

  @override
  String? get openAiApiKey => null; // Add to ConfigService if needed

  @override
  String? get groqApiKey => _configService.groqApiKey;

  @override
  String? get stripePublishableKey => null; // Add to ConfigService if needed

  @override
  bool get enableVoiceRecording =>
      true; // Default values for features not in ConfigService

  @override
  bool get enableOfflineMode => false;

  @override
  bool get enableAnalytics => false;

  @override
  bool get enableCrashReporting => false;

  @override
  bool get enableRNNoise => true;

  @override
  int get audioSampleRate => 16000;

  @override
  String get audioFormat => 'wav';

  @override
  int get maxRecordingDuration => 300;

  @override
  int get sessionTimeoutMinutes => 30;

  @override
  int get maxConcurrentSessions => 5;

  @override
  String get databaseName => 'ai_therapist.db';

  @override
  int get databaseVersion => 1;

  @override
  bool get enableDatabaseLogging => false;

  @override
  String get logLevel => 'info';

  @override
  bool get enableFileLogging => false;

  @override
  String? get loggingEndpoint => null;

  @override
  Duration get cacheTimeout => const Duration(minutes: 30);

  @override
  int get maxCacheSize => 100;

  @override
  bool validateConfiguration() => true;

  @override
  List<String> getMissingRequiredConfig() => [];

  @override
  Future<void> refreshConfiguration() async {
    await _configService.init();
  }

  @override
  Future<void> updateConfiguration(String key, dynamic value) async {
    // Not implemented in original ConfigService
  }

  @override
  Future<void> initialize() async {
    await _configService.init();
  }

  @override
  bool get isInitialized => true; // Assume initialized after creation
}

class _DatabaseAdapter implements IDatabase {
  final AppDatabase _database;

  _DatabaseAdapter(this._database);

  @override
  Future<void> initialize() async {
    await _database.database; // This will initialize the database
  }

  @override
  Future<void> close() async {
    // AppDatabase doesn't expose close method directly
  }

  @override
  bool get isOpen => true; // Assume open after initialization

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    final db = await _database.database;
    return await db.transaction((txn) async {
      return await action();
    });
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await _database.database;
    return await db.insert(table, data);
  }

  @override
  Future<List<Map<String, dynamic>>> query(String table,
      {List<String>? columns,
      String? where,
      List<dynamic>? whereArgs,
      String? orderBy,
      int? limit,
      int? offset}) async {
    final db = await _database.database;
    return await db.query(table,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
  }

  @override
  Future<int> update(String table, Map<String, dynamic> data,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await _database.database;
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  @override
  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await _database.database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawInsert(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawUpdate(sql, arguments);
  }

  @override
  Future<int> rawDelete(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    return await db.rawDelete(sql, arguments);
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {
    final db = await _database.database;
    await db.execute(sql, arguments);
  }

  @override
  Future<bool> tableExists(String tableName) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  @override
  Future<List<String>> getTableNames() async {
    final db = await _database.database;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return result.map((row) => row['name'] as String).toList();
  }

  @override
  Future<void> runMigration(int fromVersion, int toVersion) async {
    // Delegate to AppDatabase migration logic
    // This would need to be implemented based on AppDatabase's migration system
  }

  @override
  int get version => 1; // Default version

  @override
  Future<void> batch(Future<void> Function() operations) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await operations();
    });
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final db = await _database.database;
      await db.rawQuery('SELECT 1');
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    return {
      'isOpen': isOpen,
      'version': version,
    };
  }
}
