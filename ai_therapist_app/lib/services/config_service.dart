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
    // Force update to new URL regardless of what was passed
    this._llmApiEndpoint =
        'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';
    this._voiceModelEndpoint = voiceModelEndpoint ?? this._llmApiEndpoint;
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
            debugPrint(
                '  $key: ${value.substring(0, value.length > 4 ? 4 : value.length)}*****');
          } else {
            debugPrint('  $key: $value');
          }
        });
      }

      // Base URLs and endpoints - always safe get with fallbacks
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

      // Flags
      final envIsProd = _safeGetEnv('IS_PRODUCTION_MODE') == 'true';

      // Set base URLs and endpoints
      if (envGroqBaseUrl.isNotEmpty) {
        _groqApiBaseUrl = envGroqBaseUrl;
      } else {
        _groqApiBaseUrl = 'https://api.groq.com/openai/v1';
      }

      // Simpler logic for LLM endpoint: Use env var in debug, otherwise use production URL
      debugPrint(
          '[RELEASE DEBUG] Evaluating _llmApiEndpoint logic. Current value: "$_llmApiEndpoint"');
      if (kDebugMode && envLlmEndpoint != null && envLlmEndpoint.isNotEmpty) {
        _llmApiEndpoint = envLlmEndpoint; // Use .env value only in debug
        debugPrint(
            '[RELEASE DEBUG] Set _llmApiEndpoint from .env: "$_llmApiEndpoint"');
      } else if (!kDebugMode) {
        _llmApiEndpoint =
            'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app'; // Production URL
        debugPrint(
            '[RELEASE DEBUG] Set _llmApiEndpoint to PRODUCTION URL: "$_llmApiEndpoint"');
      } else {
        // Fallback if debug mode but no .env value (could be empty or set default)
        _llmApiEndpoint = _llmApiEndpoint.isEmpty
            ? 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app'
            : _llmApiEndpoint;
        debugPrint(
            '[RELEASE DEBUG] Set _llmApiEndpoint via fallback: "$_llmApiEndpoint"');
      }

      // Make sure voice endpoint also uses the correct base URL
      if (envVoiceEndpoint != null && envVoiceEndpoint.isNotEmpty) {
        _voiceModelEndpoint = envVoiceEndpoint;
      } else {
        // Use the potentially updated _llmApiEndpoint as the base for voice if not specified
        _voiceModelEndpoint = _llmApiEndpoint;
      }

      // Set model endpoints
      if (envLlmModelEndpoint != null && envLlmModelEndpoint.isNotEmpty) {
        _llmModelEndpoint = envLlmModelEndpoint;
      } else {
        _llmModelEndpoint = 'https://api.groq.com/openai/v1/models';
      }

      if (envTtsModelEndpoint != null && envTtsModelEndpoint.isNotEmpty) {
        _ttsModelEndpoint = envTtsModelEndpoint;
      } else {
        _ttsModelEndpoint = '$_groqApiBaseUrl/audio/speech';
      }

      if (envTranscriptionEndpoint != null &&
          envTranscriptionEndpoint.isNotEmpty) {
        _transcriptionEndpoint = envTranscriptionEndpoint;
      } else {
        _transcriptionEndpoint = '$_groqApiBaseUrl/audio/transcriptions';
      }

      // Set model IDs
      if (envLlmModelId != null && envLlmModelId.isNotEmpty) {
        _llmModelId = envLlmModelId;
      } else {
        _llmModelId = 'meta-llama/llama-4-scout-17b-16e-instruct';
      }

      if (envTtsModelId != null && envTtsModelId.isNotEmpty) {
        _ttsModelId = envTtsModelId;
      } else {
        _ttsModelId = 'playai-tts';
      }

      if (envTranscriptionModelId != null &&
          envTranscriptionModelId.isNotEmpty) {
        _transcriptionModelId = envTranscriptionModelId;
      } else {
        _transcriptionModelId = 'whisper-large-v3-turbo';
      }

      // API Key
      if (envGroqApiKey != null && envGroqApiKey.isNotEmpty) {
        _groqApiKey = envGroqApiKey;
      }

      // Flags
      if (envIsProd) {
        _isProductionMode = true;
      }

      // Disable mocks in production mode
      if (_isProductionMode) {
        _useMockLlmResponses = false;
        _useMockTranscription = false;
      }

      debugPrint(
          '[RELEASE DEBUG] Exiting _loadEnvironmentVariables. Final _llmApiEndpoint: "$_llmApiEndpoint"');
      debugPrint(
          '[ConfigService] Environment variables processed successfully');
    } catch (e) {
      debugPrint('[ConfigService] Error loading environment variables: $e');
      debugPrint('[ConfigService] Continuing with default values');
      // Ensure we have a valid API endpoint, even if environment loading fails
      if (_llmApiEndpoint.isEmpty) {
        _llmApiEndpoint =
            'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';
        debugPrint('[ConfigService] Set fallback API endpoint after error');
      }
    }
  }

  /// Safely get an environment variable with a fallback
  String _safeGetEnv(String key) {
    try {
      return dotenv.env[key] ?? '';
    } catch (e) {
      debugPrint('[ConfigService] Error accessing env var $key: $e');
      return '';
    }
  }

  /// Load API keys from secure storage
  Future<void> _loadApiKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedApiKeys = prefs.getString(_apiKeysPrefsKey);

      if (storedApiKeys != null && storedApiKeys.isNotEmpty) {
        // In a real app, you would decrypt this data
        final apiKeysMap = json.decode(storedApiKeys) as Map<String, dynamic>;

        // Set API keys if found in storage and not already set
        if (_groqApiKey.isEmpty && apiKeysMap.containsKey('groq')) {
          _groqApiKey = apiKeysMap['groq'] as String;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading API keys: $e');
      }
    }
  }

  /// Save API keys to secure storage
  Future<void> saveApiKeys({String? groqApiKey}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Update in-memory values if provided
      if (groqApiKey != null && groqApiKey.isNotEmpty) {
        _groqApiKey = groqApiKey;
      }

      // Prepare data to save
      final apiKeysMap = {
        'groq': _groqApiKey,
      };

      // In a real app, you would encrypt this data
      final storedApiKeys = json.encode(apiKeysMap);

      // Save to storage
      await prefs.setString(_apiKeysPrefsKey, storedApiKeys);

      if (kDebugMode) {
        print('API keys saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving API keys: $e');
      }
    }
  }

  /// Load app version information
  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      _appVersion = 'Unknown';
      if (kDebugMode) {
        print('Error loading app info: $e');
      }
    }
  }
}
