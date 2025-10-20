import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration class for managing environment-specific values
/// such as API endpoints and other configuration settings.
class AppConfig {
  // Singleton instance
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  // Dart define overrides (evaluated at compile time)
  static const String _dartDefineTtsStreamingEnabled =
      String.fromEnvironment('TTS_STREAMING_ENABLED');
  static const int _dartDefineTtsStreamingBufferSize =
      int.fromEnvironment('TTS_STREAMING_BUFFER_SIZE', defaultValue: -1);
  static const int _dartDefineTtsMaxMemoryDurationSeconds =
      int.fromEnvironment('TTS_MAX_MEMORY_DURATION_SECONDS', defaultValue: -1);

  // Runtime overrides sourced from remote config / cached preferences
  bool? _runtimeTtsStreamingEnabled;
  int? _runtimeTtsStreamingBufferSize;
  int? _runtimeTtsMaxMemoryDurationSeconds;

  // Backend URLs
  String get backendUrl =>
      dotenv.env['BACKEND_URL'] ??
      'https://ai-therapist-backend-385290373302.us-central1.run.app'; // Use production Cloud Run URL

  String get apiBaseUrl => '$backendUrl/api/v1';

  // Endpoints
  String get llmApiEndpoint => '$backendUrl';
  String get voiceModelEndpoint => '$backendUrl';

  String get privacyPolicyUrl =>
      dotenv.env['PRIVACY_POLICY_URL'] ??
      'https://upliftapp-cd86e.web.app/privacy';

  String get termsOfServiceUrl =>
      dotenv.env['TERMS_OF_SERVICE_URL'] ??
      'https://upliftapp-cd86e.web.app/terms';

  String get accountDeletionUrl =>
      dotenv.env['ACCOUNT_DELETION_URL'] ??
      'https://upliftapp-cd86e.web.app/account/delete';

  // Other config settings can be added here
  bool get isDebugMode => false;

  // TTS Streaming Configuration
  bool get ttsStreamingEnabled {
    if (_runtimeTtsStreamingEnabled != null) {
      return _runtimeTtsStreamingEnabled!;
    }

    if (_dartDefineTtsStreamingEnabled.isNotEmpty) {
      final normalized = _dartDefineTtsStreamingEnabled.toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }

    final envValue = dotenv.env['TTS_STREAMING_ENABLED'];
    if (envValue != null) {
      final normalized = envValue.toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }

    return true; // Default to enabled unless explicitly disabled
  }

  int get ttsStreamingBufferSize {
    if (_runtimeTtsStreamingBufferSize != null) {
      return _runtimeTtsStreamingBufferSize!;
    }

    if (_dartDefineTtsStreamingBufferSize >= 0) {
      return _dartDefineTtsStreamingBufferSize;
    }

    return int.tryParse(dotenv.env['TTS_STREAMING_BUFFER_SIZE'] ?? '') ?? 8192;
  }

  int get ttsMaxMemoryDurationSeconds {
    if (_runtimeTtsMaxMemoryDurationSeconds != null) {
      return _runtimeTtsMaxMemoryDurationSeconds!;
    }

    if (_dartDefineTtsMaxMemoryDurationSeconds >= 0) {
      return _dartDefineTtsMaxMemoryDurationSeconds;
    }

    return int.tryParse(dotenv.env['TTS_MAX_MEMORY_DURATION_SECONDS'] ?? '') ??
        300;
  }

  /// Apply runtime overrides sourced from remote config / cached values
  void applyRuntimeOverrides({
    bool? ttsStreamingEnabled,
    int? ttsStreamingBufferSize,
    int? ttsMaxMemoryDurationSeconds,
  }) {
    if (ttsStreamingEnabled != null) {
      _runtimeTtsStreamingEnabled = ttsStreamingEnabled;
      if (kDebugMode) {
        debugPrint(
            '[AppConfig] Runtime override: ttsStreamingEnabled=$ttsStreamingEnabled');
      }
    }

    if (ttsStreamingBufferSize != null) {
      _runtimeTtsStreamingBufferSize = ttsStreamingBufferSize;
      if (kDebugMode) {
        debugPrint(
            '[AppConfig] Runtime override: ttsStreamingBufferSize=$ttsStreamingBufferSize');
      }
    }

    if (ttsMaxMemoryDurationSeconds != null) {
      _runtimeTtsMaxMemoryDurationSeconds = ttsMaxMemoryDurationSeconds;
      if (kDebugMode) {
        debugPrint(
            '[AppConfig] Runtime override: ttsMaxMemoryDurationSeconds=$ttsMaxMemoryDurationSeconds');
      }
    }
  }

  /// Clear runtime overrides (useful for tests)
  void clearRuntimeOverrides() {
    _runtimeTtsStreamingEnabled = null;
    _runtimeTtsStreamingBufferSize = null;
    _runtimeTtsMaxMemoryDurationSeconds = null;
  }

  /// Initialize the configuration
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
      print('Environment configuration loaded successfully');
    } catch (e) {
      print(
          'Warning: Could not load .env file, using default values. Error: $e');
    }
  }

  /// Log the current configuration
  void logConfig() {
    print('====== App Configuration ======');
    print('Backend URL: $backendUrl');
    print('API Base URL: $apiBaseUrl');
    print('LLM API Endpoint: $llmApiEndpoint');
    print('Voice Model Endpoint: $voiceModelEndpoint');
    print('Debug Mode: $isDebugMode');
    print('TTS Streaming Enabled: $ttsStreamingEnabled');
    print('TTS Streaming Buffer Size: $ttsStreamingBufferSize');
    print('TTS Max Memory Duration (s): $ttsMaxMemoryDurationSeconds');
    print('Privacy Policy URL: $privacyPolicyUrl');
    print('Terms of Service URL: $termsOfServiceUrl');
    print('Account Deletion URL: $accountDeletionUrl');
    print('==============================');
  }
}
