import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    // Optional parameters for testing or DI
    this._llmApiEndpoint = llmApiEndpoint ?? '';
    this._voiceModelEndpoint = voiceModelEndpoint ?? '';
    this._groqApiKey = groqApiKey ?? '';
    this._useMockTranscription = useMockTranscription ?? false;
    this._useMockLlmResponses = useMockLlmResponses ?? false;
    this._isProductionMode = isProductionMode ?? false;
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
    try {
      // Load .env file (for development)
      if (kDebugMode) {
        await dotenv.load(fileName: ".env");
      }
      
      // Base URLs and endpoints
      final envGroqBaseUrl = dotenv.env['GROQ_API_BASE_URL'];
      final envLlmEndpoint = dotenv.env['LLM_API_ENDPOINT'];
      final envVoiceEndpoint = dotenv.env['VOICE_MODEL_ENDPOINT'];
      
      // API Key
      final envGroqApiKey = dotenv.env['GROQ_API_KEY'];
      
      // Model endpoints
      final envLlmModelEndpoint = dotenv.env['LLM_MODEL_ENDPOINT'];
      final envTtsModelEndpoint = dotenv.env['TTS_MODEL_ENDPOINT'];
      final envTranscriptionEndpoint = dotenv.env['TRANSCRIPTION_ENDPOINT'];
      
      // Model IDs
      final envLlmModelId = dotenv.env['LLM_MODEL_ID'];
      final envTtsModelId = dotenv.env['TTS_MODEL_ID'];
      final envTranscriptionModelId = dotenv.env['TRANSCRIPTION_MODEL_ID'];
      
      // Flags
      final envIsProd = dotenv.env['IS_PRODUCTION'] == 'true';
      
      // Set base URLs and endpoints
      if (envGroqBaseUrl != null && envGroqBaseUrl.isNotEmpty) {
        _groqApiBaseUrl = envGroqBaseUrl;
      } else {
        _groqApiBaseUrl = 'https://api.groq.com/openai/v1';
      }
      
      if (envLlmEndpoint != null && envLlmEndpoint.isNotEmpty) {
        _llmApiEndpoint = envLlmEndpoint;
      } else if (_llmApiEndpoint.isEmpty) {
        _llmApiEndpoint = kDebugMode
            ? 'http://10.0.2.2:8000'
            : 'https://api-fuukqlcsha-uc.a.run.app';
      }
      
      if (envVoiceEndpoint != null && envVoiceEndpoint.isNotEmpty) {
        _voiceModelEndpoint = envVoiceEndpoint;
      } else if (_voiceModelEndpoint.isEmpty) {
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
      
      if (envTranscriptionEndpoint != null && envTranscriptionEndpoint.isNotEmpty) {
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
      
      if (envTranscriptionModelId != null && envTranscriptionModelId.isNotEmpty) {
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
    } catch (e) {
      if (kDebugMode) {
        print('Error loading environment variables: $e');
      }
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