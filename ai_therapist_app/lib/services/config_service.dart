import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../di/interfaces/i_config_service.dart';
class ConfigService implements IConfigService {
  static const String _apiKeysPrefsKey = 'encrypted_api_keys';
  String _groqApiKey = '';
  String _groqApiBaseUrl = '';
  String _llmApiEndpoint = '';
  String _voiceModelEndpoint = '';
  String _llmModelEndpoint = '';
  String _llmModelId = '';
  String _ttsModelEndpoint = '';
  String _ttsModelId = 'default_tts'; // Generic default
  String _transcriptionEndpoint = '';
  String _transcriptionModelId = 'default_transcription'; // Generic default
  String _firebaseApiKey = '';
  String _firebaseAppId = '';
  String _firebaseMessagingSenderId = '';
  String _firebaseProjectId = '';
  String _firebaseStorageBucket = '';
  String _firebaseDatabaseId = '';
  bool _isProductionMode = false;
  bool _useMockLlmResponses = false;
  bool _useMockTranscription = false;
  String? _appVersion;
  bool _directLLMMode = false; // Default to false
  bool _geminiLiveDuplexEnabled = false; // Default to false
  @override
  String get groqApiKey => _groqApiKey;
  String get groqApiBaseUrl => _groqApiBaseUrl;
  String get voiceModelEndpoint => _voiceModelEndpoint;
  String get llmModelEndpoint =>
      _llmModelEndpoint; // This is the direct model endpoint
  String get llmModelId => _llmModelId;
  String get ttsModelEndpoint => _ttsModelEndpoint;
  String get ttsModelId => _ttsModelId;
  String get transcriptionEndpoint => _transcriptionEndpoint;
  String get transcriptionModelId => _transcriptionModelId;
  @override
  String get firebaseApiKey => _firebaseApiKey;
  String get firebaseAppId => _firebaseAppId;
  String get firebaseMessagingSenderId => _firebaseMessagingSenderId;
  @override
  String get firebaseProjectId => _firebaseProjectId;
  String get firebaseStorageBucket => _firebaseStorageBucket;
  String get firebaseDatabaseId => _firebaseDatabaseId;
  bool get isProductionMode => _isProductionMode;
  bool get useMockLlmResponses => _useMockLlmResponses;
  bool get useMockTranscription => _useMockTranscription;
  String get appVersion => _appVersion ?? 'Unknown';
  bool get directLLMModeEnabled => _directLLMMode;
  bool get geminiLiveDuplexEnabled => _geminiLiveDuplexEnabled;
  String get llmApiEndpoint {
    if (_directLLMMode) {
      return _llmModelEndpoint; // Or construct it from LLMConfig.currentLLMConfig.endpoint
    } else {
      return _llmApiEndpoint; // refers to the original private field intended for backend proxy
    }
  }
  ConfigService({
    String? llmApiEndpoint, // This will now be the backend proxy endpoint
    String? voiceModelEndpoint,
    String? groqApiKey,
    bool? useMockTranscription,
    bool? useMockLlmResponses,
    bool? isProductionMode,
    bool? directLLMMode,
    bool? geminiLiveDuplexEnabled,
  }) {
    _llmApiEndpoint =
        llmApiEndpoint ?? ''; // This is the backend proxy URL
    _voiceModelEndpoint = voiceModelEndpoint ?? '';
    _groqApiKey = groqApiKey ?? '';
    _useMockTranscription = useMockTranscription ?? false;
    _useMockLlmResponses = useMockLlmResponses ?? false;
    _isProductionMode = isProductionMode ?? false;
    _directLLMMode = directLLMMode ?? false;
    _geminiLiveDuplexEnabled = geminiLiveDuplexEnabled ?? false;
  }
  @override
  Future<void> initialize() async {
    await init();
  }
  Future<void> init() async {
    try {
      await _loadEnvironmentVariables();
      await _loadApiKeys();
      await _loadAppInfo();
      await _loadDirectLLMModePreference();
      await _loadGeminiLiveDuplexFlag();
    } catch (e) {}
  }
  Future<void> _loadEnvironmentVariables() async {
    try {
      bool envFileLoaded = false;
      try {
        await dotenv.load(fileName: ".env");
        envFileLoaded = true;
      } catch (e) {
        try {
          final Directory appDir = Directory.current;
          final String envPath = path.join(appDir.path, '.env');
          if (await File(envPath).exists()) {
            await dotenv.load(fileName: envPath);
            envFileLoaded = true;
          }
        } catch (_) {}}
      final envBackendUrl = _safeGetEnv('BACKEND_URL');
      final envGroqBaseUrl = _safeGetEnv('GROQ_API_BASE_URL');
      final envLlmEndpoint = _safeGetEnv('LLM_API_ENDPOINT');
      final envVoiceEndpoint = _safeGetEnv('VOICE_MODEL_ENDPOINT');
      final envGroqApiKey = _safeGetEnv('GROQ_API_KEY');
      final envLlmModelEndpoint = _safeGetEnv('LLM_MODEL_ENDPOINT');
      final envTtsModelEndpoint = _safeGetEnv('TTS_MODEL_ENDPOINT');
      final envTranscriptionEndpoint = _safeGetEnv('TRANSCRIPTION_ENDPOINT');
      final envLlmModelId = _safeGetEnv('LLM_MODEL_ID');
      final String envLoadedTtsModelId = _safeGetEnv('TTS_MODEL_ID');
      final String envLoadedTranscriptionModelId =
          _safeGetEnv('TRANSCRIPTION_MODEL_ID');
      final envFirebaseApiKey = _safeGetEnv('FIREBASE_API_KEY');
      final envFirebaseAppId = _safeGetEnv('FIREBASE_APP_ID');
      final envFirebaseMessagingSenderId =
          _safeGetEnv('FIREBASE_MESSAGING_SENDER_ID');
      final envFirebaseProjectId = _safeGetEnv('FIREBASE_PROJECT_ID');
      final envFirebaseStorageBucket = _safeGetEnv('FIREBASE_STORAGE_BUCKET');
      final envFirebaseDatabaseId = _safeGetEnv('FIREBASE_DATABASE_ID');
      final envIsProd = _safeGetEnv('IS_PRODUCTION_MODE') == 'true';
      final envUseVoiceFeatures = _safeGetEnv('USE_VOICE_FEATURES') == 'true';
      final envEnableAnalytics = _safeGetEnv('ENABLE_ANALYTICS') == 'true';
      final envGeminiLiveDuplex =
          _safeGetEnv('GEMINI_LIVE_DUPLEX').toLowerCase();
      if (envGeminiLiveDuplex == 'true') {
        if (!_geminiLiveDuplexEnabled) {
          await setGeminiLiveDuplexPreference(true);
        } else {
          _geminiLiveDuplexEnabled = true;
        }
      } else if (envGeminiLiveDuplex == 'false') {
        if (_geminiLiveDuplexEnabled) {
          await setGeminiLiveDuplexPreference(false);
        } else {
          _geminiLiveDuplexEnabled = false;
        }
      }
      if (envGroqBaseUrl.isNotEmpty) {
        _groqApiBaseUrl = envGroqBaseUrl;
      } else {
        _groqApiBaseUrl = 'https://api.groq.com/openai/v1';
      }
      String effectiveBackendUrl =
          'https://ai-therapist-backend-385290373302.us-central1.run.app';
      if (envBackendUrl.isNotEmpty) {
        effectiveBackendUrl = envBackendUrl;
      }
      if (envLlmEndpoint.isNotEmpty) {
        _llmApiEndpoint = envLlmEndpoint;
      } else {
        _llmApiEndpoint = effectiveBackendUrl;
      }
      if (envVoiceEndpoint.isNotEmpty) {
        _voiceModelEndpoint = envVoiceEndpoint;
      } else {
        _voiceModelEndpoint = _llmApiEndpoint;
      }
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
      _isProductionMode = envIsProd;
      _useMockTranscription = !envUseVoiceFeatures;
      if (envGeminiLiveDuplex == 'true') {
        _geminiLiveDuplexEnabled = true;
      } else if (envGeminiLiveDuplex == 'false') {
        _geminiLiveDuplexEnabled = false;
      }
    } catch (e) {}
  }
  String _safeGetEnv(String key) {
    return dotenv.env[key] ?? '';
  }
  Future<void> _loadApiKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storedKeys = prefs.getString(_apiKeysPrefsKey);
      if (storedKeys != null && storedKeys.isNotEmpty) {
        final Map<String, dynamic> keyMap = json.decode(storedKeys);
        if (keyMap.containsKey('groq_api_key')) {
          _groqApiKey = keyMap['groq_api_key'];
        }
      }
    } catch (e) {}
  }
  Future<void> saveApiKey(String keyName, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? storedKeys = prefs.getString(_apiKeysPrefsKey);
      Map<String, dynamic> keyMap = {};
      if (storedKeys != null && storedKeys.isNotEmpty) {
        keyMap = json.decode(storedKeys);
      }
      keyMap[keyName] = value;
      await prefs.setString(_apiKeysPrefsKey, json.encode(keyMap));
      if (keyName == 'groq_api_key') {
        _groqApiKey = value;
      }
    } catch (e) {}
  }
  Future<void> _loadAppInfo() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } catch (e) {}
  }
  Future<void> _loadDirectLLMModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _directLLMMode = prefs.getBool('directLLMModeEnabled') ??
          _safeGetEnv('DIRECT_LLM_MODE_ENABLED') == 'true' ??
          false;
    } catch (e) {
      _directLLMMode = false; // Fallback
    }
  }
  Future<void> _loadGeminiLiveDuplexFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('geminiLiveDuplexEnabled')) {
        final storedValue = prefs.getBool('geminiLiveDuplexEnabled');
        if (storedValue != null) {
          _geminiLiveDuplexEnabled = storedValue;
        }
      }
    } catch (e) {}
  }
  Future<void> setGeminiLiveDuplexPreference(bool enabled) async {
    _geminiLiveDuplexEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('geminiLiveDuplexEnabled', enabled);
    } catch (e) {}
  }
  Future<void> setDirectLLMModePreference(bool enabled) async {
    _directLLMMode = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('directLLMModeEnabled', enabled);
    } catch (e) {}
  }
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
  }
  @override
  bool get isInitialized => _appVersion != null;
}
