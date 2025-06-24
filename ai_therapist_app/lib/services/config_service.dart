import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../di/interfaces/i_config_service.dart';

/// Service for accessing configuration values and API keys
/// Uses environment variables and secure storage
class ConfigService implements IConfigService {
  // Stored API keys (encrypted in a real production app)
  static const String _apiKeysPrefsKey = 'encrypted_api_keys';

  // Default values
  String _groqApiKey = '';
  String _groqApiBaseUrl = '';
  String _llmApiEndpoint = '';
  String _voiceModelEndpoint = '';

  // Model endpoints and IDs
  String _llmModelEndpoint = '';
  String _llmModelId = '';
  String _ttsModelEndpoint = '';
  String _ttsModelId = 'default_tts'; // Generic default
  String _transcriptionEndpoint = '';
  String _transcriptionModelId = 'default_transcription'; // Generic default

  // Firebase configuration
  String _firebaseApiKey = '';
  String _firebaseAppId = '';
  String _firebaseMessagingSenderId = '';
  String _firebaseProjectId = '';
  String _firebaseStorageBucket = '';
  String _firebaseDatabaseId = '';

  // Configuration flags
  bool _isProductionMode = false;
  bool _useMockLlmResponses = false;
  bool _useMockTranscription = false;
  String? _appVersion;

  // ADD THIS FIELD
  bool _directLLMMode = false; // Default to false

  // Getters for config values
  @override
  String get groqApiKey => _groqApiKey;
  String get groqApiBaseUrl => _groqApiBaseUrl;
  // String get llmApiEndpoint => _llmApiEndpoint; // We'll adjust this below
  String get voiceModelEndpoint => _voiceModelEndpoint;

  // Getters for model configurations
  String get llmModelEndpoint =>
      _llmModelEndpoint; // This is the direct model endpoint
  String get llmModelId => _llmModelId;
  String get ttsModelEndpoint => _ttsModelEndpoint;
  String get ttsModelId => _ttsModelId;
  String get transcriptionEndpoint => _transcriptionEndpoint;
  String get transcriptionModelId => _transcriptionModelId;

  // Getters for Firebase configuration
  @override
  String get firebaseApiKey => _firebaseApiKey;
  String get firebaseAppId => _firebaseAppId;
  String get firebaseMessagingSenderId => _firebaseMessagingSenderId;
  @override
  String get firebaseProjectId => _firebaseProjectId;
  String get firebaseStorageBucket => _firebaseStorageBucket;
  String get firebaseDatabaseId => _firebaseDatabaseId;

  // Getters for flags
  bool get isProductionMode => _isProductionMode;
  bool get useMockLlmResponses => _useMockLlmResponses;
  bool get useMockTranscription => _useMockTranscription;
  String get appVersion => _appVersion ?? 'Unknown';

  // ADD THIS GETTER
  bool get directLLMModeEnabled => _directLLMMode;

  // ADJUST llmApiEndpoint GETTER
  // This getter will now decide which endpoint to return based on _directLLMMode
  String get llmApiEndpoint {
    if (_directLLMMode) {
      // In direct mode, use the specific LLM model endpoint
      // This might be _llmModelEndpoint or a more specific one from LLMConfig if you use that elsewhere.
      // For now, let's assume _llmModelEndpoint is the one for direct calls.
      if (kDebugMode) {
        print(
            "[ConfigService] Direct LLM Mode: Using direct endpoint: $_llmModelEndpoint");
      }
      return _llmModelEndpoint; // Or construct it from LLMConfig.currentLLMConfig.endpoint
    } else {
      // In backend mode, use the general backend endpoint that proxies to the LLM
      // Your existing _llmApiEndpoint field was likely intended for this.
      if (kDebugMode) {
        print(
            "[ConfigService] Backend Mode: Using backend proxy endpoint: $_llmApiEndpoint (original private field)");
      }
      return this
          ._llmApiEndpoint; // refers to the original private field intended for backend proxy
    }
  }

  // Constructor with dependency injection for testing
  ConfigService({
    String? llmApiEndpoint, // This will now be the backend proxy endpoint
    String? voiceModelEndpoint,
    String? groqApiKey,
    bool? useMockTranscription,
    bool? useMockLlmResponses,
    bool? isProductionMode,
    // ADD directLLMMode to constructor if you want to set it during instantiation for tests
    bool? directLLMMode,
  }) {
    // Initialize with default values
    this._llmApiEndpoint =
        llmApiEndpoint ?? ''; // This is the backend proxy URL
    this._voiceModelEndpoint = voiceModelEndpoint ?? '';
    this._groqApiKey = groqApiKey ?? '';
    this._useMockTranscription = useMockTranscription ?? false;
    this._useMockLlmResponses = useMockLlmResponses ?? false;
    this._isProductionMode = isProductionMode ?? false;
    this._directLLMMode =
        directLLMMode ?? false; // Initialize from constructor or default

    // Debug output
    debugPrint(
        '[ConfigService] Initialized with BACKEND llmApiEndpoint: ${this._llmApiEndpoint}');
    if (this._directLLMMode) {
      debugPrint(
          '[ConfigService] Initialized in DIRECT LLM MODE. Effective endpoint will be: ${this.llmApiEndpoint}');
    }
  }

  /// Initialize the configuration service
  @override
  Future<void> initialize() async {
    await init();
  }

  /// Legacy initialization method - use initialize() instead
  Future<void> init() async {
    try {
      // Load environment variables
      await _loadEnvironmentVariables();

      // Load API keys from secure storage
      await _loadApiKeys();

      // Get app version information
      await _loadAppInfo();

      // ADD THIS CALL to load the preference
      await _loadDirectLLMModePreference();

      if (kDebugMode) {
        print('ConfigService initialized successfully');
        print(
            'Effective LLM API Endpoint (used by ApiClient): $llmApiEndpoint'); // Use the getter
        print(
            'Backend Proxy LLM API Endpoint (private field): $_llmApiEndpoint');
        print('Direct LLM Model Endpoint (private field): $_llmModelEndpoint');
        print('Direct LLM Mode Enabled: $_directLLMMode');
        // ... other prints ...
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing ConfigService: $e');
      }
    }
  }

  /// Load environment variables from .env file or environment
  Future<void> _loadEnvironmentVariables() async {
    debugPrint('[ConfigService] Loading environment variables...');

    try {
      bool envFileLoaded = false;

      // Load .env file - try both standard locations
      try {
        // Try loading from project root first
        await dotenv.load(fileName: ".env");
        envFileLoaded = true;
        debugPrint('[ConfigService] .env file loaded successfully');
      } catch (e) {
        debugPrint('[ConfigService] Error loading .env from project root: $e');

        // Try loading with absolute path as fallback
        try {
          // Get app directory
          final Directory appDir = Directory.current;
          final String envPath = path.join(appDir.path, '.env');
          debugPrint('[ConfigService] Trying to load .env from: $envPath');

          if (await File(envPath).exists()) {
            await dotenv.load(fileName: envPath);
            envFileLoaded = true;
            debugPrint(
                '[ConfigService] .env file loaded successfully from absolute path');
          } else {
            debugPrint('[ConfigService] .env file does not exist at: $envPath');
          }
        } catch (absPathError) {
          debugPrint(
              '[ConfigService] Error loading .env from absolute path: $absPathError');
        }
      }

      if (!envFileLoaded) {
        debugPrint(
            '[ConfigService] Could not load .env file, using default configuration values');
      } else {
        // Log loaded environment variables for debugging (masking sensitive values)
        final envVars = dotenv.env;
        debugPrint(
            '[ConfigService] Loaded ${envVars.length} environment variables:');
        envVars.forEach((key, value) {
          if (key.toLowerCase().contains('key') ||
              key.toLowerCase().contains('secret')) {
            // Mask sensitive values
            if (value.length > 4) {
              debugPrint('  $key: ${value.substring(0, 4)}*****');
            } else {
              debugPrint('  $key: ****');
            }
          } else {
            debugPrint('  $key: $value');
          }
        });
      }

      // Base URLs and endpoints - always safe get with fallbacks
      final envBackendUrl = _safeGetEnv('BACKEND_URL');
      final envGroqBaseUrl = _safeGetEnv('GROQ_API_BASE_URL');
      final envLlmEndpoint = _safeGetEnv('LLM_API_ENDPOINT');
      final envVoiceEndpoint = _safeGetEnv('VOICE_MODEL_ENDPOINT');
      final envGroqApiKey = _safeGetEnv('GROQ_API_KEY');

      // Model endpoints
      final envLlmModelEndpoint = _safeGetEnv('LLM_MODEL_ENDPOINT');
      final envTtsModelEndpoint = _safeGetEnv('TTS_MODEL_ENDPOINT');
      final envTranscriptionEndpoint = _safeGetEnv('TRANSCRIPTION_ENDPOINT');

      // Model IDs
      final envLlmModelId = _safeGetEnv('LLM_MODEL_ID');
      final String envLoadedTtsModelId = _safeGetEnv('TTS_MODEL_ID');
      final String envLoadedTranscriptionModelId =
          _safeGetEnv('TRANSCRIPTION_MODEL_ID');

      // Firebase configuration
      final envFirebaseApiKey = _safeGetEnv('FIREBASE_API_KEY');
      final envFirebaseAppId = _safeGetEnv('FIREBASE_APP_ID');
      final envFirebaseMessagingSenderId =
          _safeGetEnv('FIREBASE_MESSAGING_SENDER_ID');
      final envFirebaseProjectId = _safeGetEnv('FIREBASE_PROJECT_ID');
      final envFirebaseStorageBucket = _safeGetEnv('FIREBASE_STORAGE_BUCKET');
      final envFirebaseDatabaseId = _safeGetEnv('FIREBASE_DATABASE_ID');

      // Flags
      final envIsProd = _safeGetEnv('IS_PRODUCTION_MODE') == 'true';
      final envUseVoiceFeatures = _safeGetEnv('USE_VOICE_FEATURES') == 'true';
      final envEnableAnalytics = _safeGetEnv('ENABLE_ANALYTICS') == 'true';

      // Set base URLs and endpoints
      if (envGroqBaseUrl.isNotEmpty) {
        _groqApiBaseUrl = envGroqBaseUrl;
      } else {
        _groqApiBaseUrl = 'https://api.groq.com/openai/v1';
      }

      // For backend URL
      String effectiveBackendUrl =
          'https://ai-therapist-backend-385290373302.us-central1.run.app';
      if (envBackendUrl.isNotEmpty) {
        effectiveBackendUrl = envBackendUrl;
      }

      // For LLM API endpoint
      if (envLlmEndpoint.isNotEmpty) {
        _llmApiEndpoint = envLlmEndpoint;
      } else {
        _llmApiEndpoint = effectiveBackendUrl;
      }

      // For voice endpoint
      if (envVoiceEndpoint.isNotEmpty) {
        _voiceModelEndpoint = envVoiceEndpoint;
      } else {
        _voiceModelEndpoint = _llmApiEndpoint;
      }

      // Set model endpoints
      if (envLlmModelEndpoint.isNotEmpty) {
        _llmModelEndpoint = envLlmModelEndpoint;
      } else {
        _llmModelEndpoint = 'https://api.groq.com/openai/v1/models';
      }

      if (envTtsModelEndpoint.isNotEmpty) {
        _ttsModelEndpoint = envTtsModelEndpoint;
      } else {
        _ttsModelEndpoint = '$_groqApiBaseUrl/audio/speech';
      }

      if (envTranscriptionEndpoint.isNotEmpty) {
        _transcriptionEndpoint = envTranscriptionEndpoint;
      } else {
        _transcriptionEndpoint = '$_groqApiBaseUrl/audio/transcriptions';
      }

      // Set model IDs
      if (envLlmModelId.isNotEmpty) {
        _llmModelId = envLlmModelId;
      } else {
        _llmModelId = 'gpt-4o-mini';
      }

      _ttsModelId =
          envLoadedTtsModelId.isNotEmpty ? envLoadedTtsModelId : 'default_tts';
      _transcriptionModelId = envLoadedTranscriptionModelId.isNotEmpty
          ? envLoadedTranscriptionModelId
          : 'default_transcription';

      // Set Firebase configuration
      if (envFirebaseApiKey.isNotEmpty) {
        _firebaseApiKey = envFirebaseApiKey;
      } else {
        _firebaseApiKey =
            'AIzaSyA1M8XMCbxCVLQokGcZ8RIwKMtJ_xxxxxx'; // Default from android config
      }

      if (envFirebaseAppId.isNotEmpty) {
        _firebaseAppId = envFirebaseAppId;
      } else {
        _firebaseAppId =
            '1:123456789012:android:abcdef0123456789'; // Default from android config
      }

      if (envFirebaseMessagingSenderId.isNotEmpty) {
        _firebaseMessagingSenderId = envFirebaseMessagingSenderId;
      } else {
        _firebaseMessagingSenderId =
            '123456789012'; // Default from android config
      }

      if (envFirebaseProjectId.isNotEmpty) {
        _firebaseProjectId = envFirebaseProjectId;
      } else {
        _firebaseProjectId = 'upliftapp-cd86e'; // Default from android config
      }

      if (envFirebaseStorageBucket.isNotEmpty) {
        _firebaseStorageBucket = envFirebaseStorageBucket;
      } else {
        _firebaseStorageBucket =
            'upliftapp-cd86e.appspot.com'; // Default from android config
      }

      if (envFirebaseDatabaseId.isNotEmpty) {
        _firebaseDatabaseId = envFirebaseDatabaseId;
      } else {
        _firebaseDatabaseId = 'upliftdb'; // Default from FirebaseService
      }

      // Set flags
      _isProductionMode = envIsProd;
      _useMockTranscription = !envUseVoiceFeatures;

      debugPrint(
          '[ConfigService] Environment variables processed successfully');
    } catch (e) {
      debugPrint('[ConfigService] Error loading environment variables: $e');
    }
  }

  // Helper method to safely get environment variable
  String _safeGetEnv(String key) {
    return dotenv.env[key] ?? '';
  }

  /// Load API keys from secure storage
  Future<void> _loadApiKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storedKeys = prefs.getString(_apiKeysPrefsKey);

      if (storedKeys != null && storedKeys.isNotEmpty) {
        final Map<String, dynamic> keyMap = json.decode(storedKeys);

        // In a real app, these would be encrypted/decrypted
        if (keyMap.containsKey('groq_api_key')) {
          _groqApiKey = keyMap['groq_api_key'];
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading API keys: $e');
      }
    }
  }

  /// Save API keys to secure storage
  Future<void> saveApiKey(String keyName, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storedKeys = prefs.getString(_apiKeysPrefsKey);
      Map<String, dynamic> keyMap = {};

      if (storedKeys != null && storedKeys.isNotEmpty) {
        keyMap = json.decode(storedKeys);
      }

      // In a real app, this would be encrypted
      keyMap[keyName] = value;

      await prefs.setString(_apiKeysPrefsKey, json.encode(keyMap));

      // Update in-memory API key if it's one we use
      if (keyName == 'groq_api_key') {
        _groqApiKey = value;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving API key: $e');
      }
    }
  }

  /// Load app info from package_info
  Future<void> _loadAppInfo() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } catch (e) {
      if (kDebugMode) {
        print('Error loading app info: $e');
      }
    }
  }

  // ADD THESE METHODS for loading and setting the preference

  Future<void> _loadDirectLLMModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Load the value, defaulting to false if not found
      _directLLMMode = prefs.getBool('directLLMModeEnabled') ??
          _safeGetEnv('DIRECT_LLM_MODE_ENABLED') == 'true' ??
          false;
      if (kDebugMode) {
        print(
            '[ConfigService] Direct LLM Mode loaded from prefs/env: $_directLLMMode');
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '[ConfigService] Error loading directLLMModeEnabled preference: $e. Defaulting to false.');
      }
      _directLLMMode = false; // Fallback
    }
  }

  Future<void> setDirectLLMModePreference(bool enabled) async {
    _directLLMMode = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('directLLMModeEnabled', enabled);
      if (kDebugMode) {
        print('[ConfigService] Direct LLM Mode preference saved: $enabled');
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '[ConfigService] Error saving directLLMModeEnabled preference: $e');
      }
    }
  }

  // Interface implementation methods
  @override
  String get environment => _isProductionMode ? 'production' : 'development';

  @override
  bool get isProduction => _isProductionMode;

  @override
  bool get isDevelopment => !_isProductionMode;

  @override
  bool get isDebug => !_isProductionMode;

  @override
  String get apiBaseUrl => llmApiEndpoint;

  @override
  String get websocketUrl => llmApiEndpoint.replaceFirst('http', 'ws');

  @override
  Duration get apiTimeout => const Duration(seconds: 30);

  @override
  int get maxRetries => 3;

  @override
  String? get googleClientId => null; // Add to env if needed

  @override
  String? get openAiApiKey => null; // Add to env if needed

  @override
  String? get stripePublishableKey => null; // Add to env if needed

  @override
  bool get enableVoiceRecording => true;

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
  int get databaseVersion => 4;

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
  bool validateConfiguration() {
    return groqApiKey.isNotEmpty && llmApiEndpoint.isNotEmpty;
  }

  @override
  List<String> getMissingRequiredConfig() {
    final missing = <String>[];
    if (groqApiKey.isEmpty) missing.add('GROQ_API_KEY');
    if (llmApiEndpoint.isEmpty) missing.add('LLM_API_ENDPOINT');
    return missing;
  }

  @override
  Future<void> refreshConfiguration() async {
    await init();
  }

  @override
  Future<void> updateConfiguration(String key, dynamic value) async {
    // Not implemented in original ConfigService
    debugPrint('updateConfiguration not implemented: $key = $value');
  }

  @override
  bool get isInitialized => _appVersion != null;
}
