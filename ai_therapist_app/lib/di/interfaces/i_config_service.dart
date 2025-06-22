// lib/di/interfaces/i_config_service.dart

/// Interface for configuration service
/// Provides contract for app configuration management
abstract class IConfigService {
  // Environment
  String get environment;
  bool get isProduction;
  bool get isDevelopment;
  bool get isDebug;
  
  // API configuration
  String get apiBaseUrl;
  String get websocketUrl;
  Duration get apiTimeout;
  int get maxRetries;
  
  // Authentication
  String? get googleClientId;
  String? get firebaseApiKey;
  String? get firebaseProjectId;
  
  // Third-party services
  String? get openAiApiKey;
  String? get groqApiKey;
  String? get stripePublishableKey;
  
  // Feature flags
  bool get enableVoiceRecording;
  bool get enableOfflineMode;
  bool get enableAnalytics;
  bool get enableCrashReporting;
  bool get enableRNNoise;
  
  // Audio settings
  int get audioSampleRate;
  String get audioFormat;
  int get maxRecordingDuration;
  
  // Session settings
  int get sessionTimeoutMinutes;
  int get maxConcurrentSessions;
  
  // Database settings
  String get databaseName;
  int get databaseVersion;
  bool get enableDatabaseLogging;
  
  // Logging
  String get logLevel;
  bool get enableFileLogging;
  String? get loggingEndpoint;
  
  // Cache settings
  Duration get cacheTimeout;
  int get maxCacheSize;
  
  // Validation
  bool validateConfiguration();
  List<String> getMissingRequiredConfig();
  
  // Dynamic configuration
  Future<void> refreshConfiguration();
  Future<void> updateConfiguration(String key, dynamic value);
  
  // Initialization
  Future<void> initialize();
  bool get isInitialized;
}