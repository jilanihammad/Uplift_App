import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

/// Service for accessing configuration values and API keys
/// Uses environment variables and secure storage
class ConfigService {
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
  String _ttsModelId = '';
  String _transcriptionEndpoint = '';
  String _transcriptionModelId = '';

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

  // Getters for config values
  String get groqApiKey => _groqApiKey;
  String get groqApiBaseUrl => _groqApiBaseUrl;
  String get llmApiEndpoint => _llmApiEndpoint;
  String get voiceModelEndpoint => _voiceModelEndpoint;

  // Getters for model configurations
  String get llmModelEndpoint => _llmModelEndpoint;
  String get llmModelId => _llmModelId;
  String get ttsModelEndpoint => _ttsModelEndpoint;
  String get ttsModelId => _ttsModelId;
  String get transcriptionEndpoint => _transcriptionEndpoint;
  String get transcriptionModelId => _transcriptionModelId;

  // Getters for Firebase configuration
  String get firebaseApiKey => _firebaseApiKey;
  String get firebaseAppId => _firebaseAppId;
  String get firebaseMessagingSenderId => _firebaseMessagingSenderId;
  String get firebaseProjectId => _firebaseProjectId;
  String get firebaseStorageBucket => _firebaseStorageBucket;
  String get firebaseDatabaseId => _firebaseDatabaseId;

  // Getters for flags
  bool get isProductionMode => _isProductionMode;
  bool get useMockLlmResponses => _useMockLlmResponses;
  bool get useMockTranscription => _useMockTranscription;
  String get appVersion => _appVersion ?? 'Unknown';

  // Constructor with dependency injection for testing
  ConfigService({
    String? llmApiEndpoint,
    String? voiceModelEndpoint,
    String? groqApiKey,
    bool? useMockTranscription,
    bool? useMockLlmResponses,
    bool? isProductionMode,
  }) {
    // Initialize with default values
    this._llmApiEndpoint = llmApiEndpoint ?? '';
    this._voiceModelEndpoint = voiceModelEndpoint ?? '';
    this._groqApiKey = groqApiKey ?? '';
    this._useMockTranscription = useMockTranscription ?? false;
    this._useMockLlmResponses = useMockLlmResponses ?? false;
    this._isProductionMode = isProductionMode ?? false;

    // Debug output
    debugPrint(
        '[ConfigService] Initialized with llmApiEndpoint: $_llmApiEndpoint');
  }

  /// Initialize the configuration service
  Future<void> init() async {
    try {
      // Load environment variables
      await _loadEnvironmentVariables();

      // Load API keys from secure storage
      await _loadApiKeys();

      // Get app version information
      await _loadAppInfo();

      if (kDebugMode) {
        print('ConfigService initialized successfully');
        print('LLM API Endpoint: $_llmApiEndpoint');
        print('Voice Model Endpoint: $_voiceModelEndpoint');
        print('LLM Model ID: $_llmModelId');
        print('TTS Model ID: $_ttsModelId');
        print('Transcription Model ID: $_transcriptionModelId');

        // Print Firebase configuration (only in debug mode)
        print('Firebase Project ID: $_firebaseProjectId');
        print('Firebase Storage Bucket: $_firebaseStorageBucket');
        print('Firebase Database ID: $_firebaseDatabaseId');

        // Only print first few characters of API key for debugging
        if (_groqApiKey.isNotEmpty) {
          print('Groq API Key: ${_groqApiKey.substring(0, 5)}...');
        }
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
      final envTtsModelId = _safeGetEnv('TTS_MODEL_ID');
      final envTranscriptionModelId = _safeGetEnv('TRANSCRIPTION_MODEL_ID');

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
          'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';
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
        _llmModelId = 'meta-llama/llama-4-scout-17b-16e-instruct';
      }

      if (envTtsModelId.isNotEmpty) {
        _ttsModelId = envTtsModelId;
      } else {
        _ttsModelId = 'playai-tts';
      }

      if (envTranscriptionModelId.isNotEmpty) {
        _transcriptionModelId = envTranscriptionModelId;
      } else {
        _transcriptionModelId = 'whisper-large-v3-turbo';
      }

      // Set Firebase configuration
      if (envFirebaseApiKey.isNotEmpty) {
        _firebaseApiKey = envFirebaseApiKey;
      } else {
        _firebaseApiKey =
            '***REMOVED***'; // Default from android config
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
}
