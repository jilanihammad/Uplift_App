import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration class for managing environment-specific values
/// such as API endpoints and other configuration settings.
class AppConfig {
  // Singleton instance
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  // Backend URLs
  String get backendUrl =>
      dotenv.env['BACKEND_URL'] ??
      'https://ai-therapist-backend-385290373302.us-central1.run.app'; // Use production Cloud Run URL

  String get apiBaseUrl => '$backendUrl/api/v1';

  // Endpoints
  String get llmApiEndpoint => '$backendUrl';
  String get voiceModelEndpoint => '$backendUrl';

  // Other config settings can be added here
  bool get isDebugMode => false;

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
    print('==============================');
  }
}
