// lib/data/datasources/remote/api_client.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../../../services/config_service.dart'; // Corrected import path
import 'package:ai_therapist_app/config/app_config.dart'; // Import AppConfig
import 'package:ai_therapist_app/config/llm_config.dart'; // Import LLM Configuration
import 'package:ai_therapist_app/models/tts_config.dart';
import '../../../di/interfaces/i_api_client.dart';

class ApiClient implements IApiClient {
  final http.Client httpClient;
  final ConfigService configService; // Add ConfigService field
  late SharedPreferences _prefs;
  bool _initialized = false;
  // Increased timeout duration
  final Duration _timeout = const Duration(seconds: 15);
  // Max number of retries for transient errors
  final int _maxRetries = 3;
  static const List<String> _rootEndpointPrefixes = <String>[
    '/voice/',
    '/ai/',
    '/therapy/',
    '/sessions',
    '/session-reminder',
    '/health',
  ];

  ApiClient({
    required this.configService, // Add required ConfigService parameter
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client() {
    // Add logging here
    debugPrint(
        '[RELEASE DEBUG] ApiClient Constructor - Instance Hash: ${identityHashCode(this)}');
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // Helper method to get auth token
  Future<String?> _getToken() async {
    await _initPrefs();
    return _prefs.getString('auth_token');
  }

  // Method to update auth token - used when refreshing Firebase tokens
  Future<void> updateAuthToken(String token) async {
    await _initPrefs();
    await _prefs.setString('auth_token', token);
    if (kDebugMode) {
      debugPrint('ApiClient: Updated auth token');
    }
  }

  // Retry mechanism for handling transient errors
  Future<http.Response> _retryRequest(
      Future<http.Response> Function() requestFunc) async {
    int attempts = 0;
    Duration backoff = const Duration(milliseconds: 500);

    while (attempts < _maxRetries) {
      try {
        return await requestFunc().timeout(_timeout);
      } catch (e) {
        attempts++;
        if (attempts >= _maxRetries) {
          if (kDebugMode) {
            debugPrint('Request failed after $_maxRetries attempts: $e');
          }
          rethrow;
        }

        // Check if the error is retryable
        bool shouldRetry = e is SocketException ||
            e is TimeoutException ||
            (e is IOException && e.toString().contains('Connection reset'));

        if (!shouldRetry) {
          rethrow;
        }

        if (kDebugMode) {
          debugPrint(
              'Request failed (attempt $attempts): $e. Retrying in ${backoff.inMilliseconds}ms...');
        }

        // Exponential backoff
        await Future.delayed(backoff);
        backoff *= 2;
      }
    }

    // This should never be reached because the last attempt will either return or throw
    throw Exception('Retry mechanism failed');
  }

  // GET request
  @override
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParams,
  }) async {
    final token = await _getToken();
    final String urlString = _resolveUrl(endpoint);
    if (kDebugMode) {
      debugPrint('[RELEASE DEBUG] ApiClient.get - Resolved URL: $urlString');
    }

    final Uri uri = Uri.parse(urlString);
    final Uri uriWithParams =
        queryParams != null ? uri.replace(queryParameters: queryParams) : uri;

    final requestHeaders = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };

    try {
      if (kDebugMode) {
        debugPrint('Making GET request to: $uriWithParams');
      }

      final response = await _retryRequest(() => httpClient.get(
            uriWithParams,
            headers: requestHeaders,
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GET request failed: $e');
      }

      if (e is SocketException) {
        throw ApiException(
          statusCode: 0,
          message:
              'Connection error: ${e.message}. Please check your internet connection.',
        );
      } else if (e is TimeoutException) {
        throw ApiException(
          statusCode: 0,
          message: 'Request timed out. Please try again later.',
        );
      }

      rethrow;
    }
  }

  @override
  Future<TtsConfigDto?> fetchTtsConfig() async {
    try {
      final response = await get('/system/tts-config');
      if (response.isEmpty) {
        return null;
      }
      return TtsConfigDto.fromJson(response);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        if (kDebugMode) {
          debugPrint('Remote TTS config endpoint unavailable (404).');
        }
        return null;
      }
      rethrow;
    }
  }

  /// POST request to the API
  @override
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    if (kDebugMode) {
      debugPrint(
          '[RELEASE DEBUG] ApiClient.post - Starting post request to endpoint: $endpoint');
    }

    final String urlString = _resolveUrl(endpoint);

    final token = await _getToken();

    final requestHeaders = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };

    try {
      if (kDebugMode) {
        debugPrint('Making POST request to: $urlString');
      }

      final response = await _retryRequest(() => httpClient.post(
            Uri.parse(urlString),
            headers: requestHeaders,
            body: jsonEncode(data),
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('POST request failed: $e');
      }

      if (e is SocketException) {
        throw ApiException(
          statusCode: 0,
          message:
              'Connection error: ${e.message}. Please check your internet connection.',
        );
      } else if (e is TimeoutException) {
        throw ApiException(
          statusCode: 0,
          message: 'Request timed out. Please try again later.',
        );
      }

      rethrow;
    }
  }

  // PUT request
  @override
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    final token = await _getToken();
    final urlString = _resolveUrl(endpoint);
    if (kDebugMode) {
      debugPrint('[RELEASE DEBUG] ApiClient.put - Resolved URL: $urlString');
    }
    final uri = Uri.parse(urlString);

    final requestHeaders = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };

    try {
      final response = await _retryRequest(() => httpClient.put(
            uri,
            headers: requestHeaders,
            body: jsonEncode(data),
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PUT request failed: $e');
      }

      if (e is SocketException) {
        throw ApiException(
          statusCode: 0,
          message:
              'Connection error: ${e.message}. Please check your internet connection.',
        );
      } else if (e is TimeoutException) {
        throw ApiException(
          statusCode: 0,
          message: 'Request timed out. Please try again later.',
        );
      }

      rethrow;
    }
  }

  // PATCH request
  Future<dynamic> patch(String endpoint, {dynamic body}) async {
    final token = await _getToken();
    final String urlString = _resolveUrl(endpoint);
    if (kDebugMode) {
      debugPrint(
          '[RELEASE DEBUG] ApiClient.patch - Constructed urlString: "$urlString"');
    }

    final uri = Uri.parse(urlString);

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      if (kDebugMode) {
        debugPrint('Making PATCH request to: $uri');
      }

      final response = await _retryRequest(() => httpClient.patch(
            uri,
            headers: headers,
            body: jsonEncode(body),
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PATCH request failed: $e');
      }

      if (e is SocketException) {
        throw ApiException(
          statusCode: 0,
          message:
              'Connection error: ${e.message}. Please check your internet connection.',
        );
      } else if (e is TimeoutException) {
        throw ApiException(
          statusCode: 0,
          message: 'Request timed out. Please try again later.',
        );
      }

      rethrow;
    }
  }

  // DELETE request
  @override
  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    final token = await _getToken();
    final urlString = _resolveUrl(endpoint);
    if (kDebugMode) {
      debugPrint(
          '[RELEASE DEBUG] ApiClient.delete - Resolved URL: $urlString');
    }
    final uri = Uri.parse(urlString);

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await _retryRequest(() => httpClient.delete(
            uri,
            headers: headers,
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DELETE request failed: $e');
      }

      if (e is SocketException) {
        throw ApiException(
          statusCode: 0,
          message:
              'Connection error: ${e.message}. Please check your internet connection.',
        );
      } else if (e is TimeoutException) {
        throw ApiException(
          statusCode: 0,
          message: 'Request timed out. Please try again later.',
        );
      }

      rethrow;
    }
  }

  // Handle response and process JSON
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {};
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } else if (response.statusCode == 401) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Authentication required. Please log in again.',
      );
    } else {
      String errorMessage =
          'Request failed with status: ${response.statusCode}';

      try {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body.containsKey('message')) {
          errorMessage = body['message'];
        } else if (body.containsKey('error')) {
          errorMessage = body['error'];
        }
      } catch (e) {
        // If we can't parse the error, just use the status code
      }

      throw ApiException(
        statusCode: response.statusCode,
        message: errorMessage,
      );
    }
  }

  // IApiClient interface methods
  @override
  Future<Map<String, dynamic>> uploadFile(
    String endpoint,
    String fieldName,
    Uint8List fileData,
    String fileName, {
    Map<String, String>? headers,
    Map<String, String>? additionalFields,
  }) async {
    // Implementation for file upload
    throw UnimplementedError('File upload not yet implemented');
  }

  @override
  Future<Uint8List> downloadFile(String url) async {
    // Implementation for file download
    throw UnimplementedError('File download not yet implemented');
  }

  @override
  void setAuthToken(String token) {
    updateAuthToken(token);
  }

  @override
  void clearAuthToken() {
    _initPrefs().then((_) {
      _prefs.remove('auth_token');
    });
  }

  @override
  String? get authToken {
    // Can't make this async, so return null and require proper initialization
    return _initialized ? _prefs.getString('auth_token') : null;
  }

  @override
  String get baseUrl => configService.llmApiEndpoint;

  @override
  void setBaseUrl(String url) {
    // This would require modifying the ConfigService, which is not recommended
    throw UnimplementedError(
        'Base URL modification not supported - use ConfigService instead');
  }

  @override
  void setTimeout(Duration timeout) {
    // Current implementation uses a fixed timeout, enhancement needed
    throw UnimplementedError('Timeout modification not yet implemented');
  }

  @override
  Future<bool> checkConnection() async {
    try {
      await get('/health');
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  bool get isConnected => true; // Simplified implementation

  @override
  Stream<String> get errorStream =>
      const Stream.empty(); // Simplified implementation

  @override
  Future<void> initialize() async {
    await _initPrefs();
  }

  @override
  void dispose() {
    close();
  }

  // Close the client when done
  void close() {
    httpClient.close();
  }

  String _resolveUrl(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return endpoint;
    }

    final normalizedEndpoint =
        endpoint.startsWith('/') ? endpoint : '/$endpoint';
    final backendBase = AppConfig().backendUrl;

    if (normalizedEndpoint.startsWith('/api/')) {
      return '$backendBase$normalizedEndpoint';
    }

    if (_rootEndpointPrefixes
        .any((prefix) => normalizedEndpoint.startsWith(prefix))) {
      return '$backendBase$normalizedEndpoint';
    }

    final apiBase = AppConfig().apiBaseUrl;
    return '$apiBase$normalizedEndpoint';
  }

  /// Make a direct LLM API call using centralized configuration
  /// This bypasses the backend and calls the LLM provider directly
  Future<Map<String, dynamic>> callLLMDirect(
    String systemPrompt,
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      final llmConfig = LLMConfig.currentLLMConfig;

      if (kDebugMode) {
        debugPrint(
            '[ApiClient] Making direct LLM call to ${llmConfig.modelId}');
      }

      // Get API key from environment variable
      final apiKey = await _getApiKeyForProvider(llmConfig.apiKeyEnvVar);
      if (apiKey == null || apiKey.isEmpty) {
        throw ApiException(
          statusCode: 401,
          message: 'API key not found for ${llmConfig.apiKeyEnvVar}',
        );
      }

      // Build headers
      final headers = Map<String, String>.from(llmConfig.headers);
      headers['Authorization'] = 'Bearer $apiKey';

      // Build the request body based on provider
      final body = _buildLLMRequestBody(
        llmConfig,
        systemPrompt,
        userMessage,
        conversationHistory: conversationHistory,
        additionalParams: additionalParams,
      );

      if (kDebugMode) {
        debugPrint('[ApiClient] LLM Request to: ${llmConfig.endpoint}');
        debugPrint('[ApiClient] LLM Model: ${llmConfig.modelId}');
      }

      // Make the request
      final response = await _retryRequest(() => httpClient.post(
            Uri.parse(llmConfig.endpoint),
            headers: headers,
            body: jsonEncode(body),
          ));

      final responseData = _handleResponse(response);

      // Extract response text based on provider format
      return _extractLLMResponse(responseData, LLMConfig.activeLLMProvider);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ApiClient] Direct LLM call failed: $e');
      }
      rethrow;
    }
  }

  /// Build request body for different LLM providers
  Map<String, dynamic> _buildLLMRequestBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  }) {
    final provider = LLMConfig.activeLLMProvider;

    switch (provider) {
      case LLMProvider.openai:
      case LLMProvider.groq:
        return _buildOpenAIStyleBody(config, systemPrompt, userMessage,
            conversationHistory, additionalParams);

      case LLMProvider.anthropic:
        return _buildAnthropicStyleBody(config, systemPrompt, userMessage,
            conversationHistory, additionalParams);

      case LLMProvider.google:
        return _buildGoogleStyleBody(config, systemPrompt, userMessage,
            conversationHistory, additionalParams);

      case LLMProvider.custom:
        // For custom providers, use OpenAI format as default
        return _buildOpenAIStyleBody(config, systemPrompt, userMessage,
            conversationHistory, additionalParams);
    }
  }

  /// Build OpenAI/Groq style request body
  Map<String, dynamic> _buildOpenAIStyleBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  ) {
    final messages = <Map<String, String>>[];

    // Add system message
    messages.add({
      'role': 'system',
      'content': systemPrompt,
    });

    // Add conversation history
    if (conversationHistory != null) {
      messages.addAll(conversationHistory);
    }

    // Add current user message
    messages.add({
      'role': 'user',
      'content': userMessage,
    });

    final body = {
      'model': config.modelId,
      'messages': messages,
      ...config.defaultParams,
    };

    // Override with additional params if provided
    if (additionalParams != null) {
      body.addAll(additionalParams);
    }

    return body;
  }

  /// Build Anthropic style request body
  Map<String, dynamic> _buildAnthropicStyleBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  ) {
    final messages = <Map<String, String>>[];

    // Add conversation history (excluding system messages)
    if (conversationHistory != null) {
      for (final msg in conversationHistory) {
        if (msg['role'] != 'system') {
          messages.add(msg);
        }
      }
    }

    // Add current user message
    messages.add({
      'role': 'user',
      'content': userMessage,
    });

    final body = {
      'model': config.modelId,
      'system': systemPrompt,
      'messages': messages,
      ...config.defaultParams,
    };

    // Override with additional params if provided
    if (additionalParams != null) {
      body.addAll(additionalParams);
    }

    return body;
  }

  /// Build Google style request body
  Map<String, dynamic> _buildGoogleStyleBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  ) {
    final contents = <Map<String, dynamic>>[];

    // Combine system prompt with user message for Google format
    final fullPrompt = '$systemPrompt\n\nUser: $userMessage\nAssistant:';

    contents.add({
      'parts': [
        {
          'text': fullPrompt,
        }
      ]
    });

    final body = {
      'contents': contents,
      ...config.defaultParams,
    };

    // Override with additional params if provided
    if (additionalParams != null) {
      body.addAll(additionalParams);
    }

    return body;
  }

  /// Extract response text based on provider format
  Map<String, dynamic> _extractLLMResponse(
      Map<String, dynamic> response, LLMProvider provider) {
    switch (provider) {
      case LLMProvider.openai:
      case LLMProvider.groq:
        final choices = response['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'];
          return {
            'response': message['content'],
            'usage': response['usage'],
          };
        }
        break;

      case LLMProvider.anthropic:
        final content = response['content'] as List?;
        if (content != null && content.isNotEmpty) {
          return {
            'response': content[0]['text'],
            'usage': response['usage'],
          };
        }
        break;

      case LLMProvider.google:
        final candidates = response['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return {
              'response': parts[0]['text'],
              'usage': response['usageMetadata'],
            };
          }
        }
        break;

      case LLMProvider.custom:
        // For custom providers, try OpenAI format first
        return _extractLLMResponse(response, LLMProvider.openai);
    }

    throw ApiException(
      statusCode: 500,
      message: 'Unable to extract response from LLM provider: $provider',
    );
  }

  /// Get API key for a specific provider from environment variables
  Future<String?> _getApiKeyForProvider(String envVarName) async {
    // In a real app, you would get this from secure storage or environment variables
    // For now, we'll use SharedPreferences (in production, use flutter_secure_storage)
    await _initPrefs();
    return _prefs.getString(envVarName);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => 'ApiException: $statusCode - $message';
}

class BackendSchemaException extends ApiException {
  final Map<String, dynamic>? receivedResponse;
  final String expectedField;

  BackendSchemaException({
    required super.message,
    required this.expectedField,
    this.receivedResponse,
  }) : super(statusCode: 422);

  @override
  String toString() =>
      'BackendSchemaException: $message (expected field: $expectedField)';
}

class TimeoutException extends IOException {
  final String message;

  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
