// lib/data/datasources/remote/api_client.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _initialized = false;
  String? _cachedAuthToken;
  final Duration _timeout = const Duration(seconds: 15);
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
    _initPrefs();
  }
  Future<void> _initPrefs() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      await _migrateTokenToSecureStorage();
      _initialized = true;
    }
  }
  Future<void> _migrateTokenToSecureStorage() async {
    try {
      final migrated = _prefs.getBool('auth_token_migrated_v1') ?? false;
      if (migrated) {
        return;
      }
      final oldToken = _prefs.getString('auth_token');
      if (oldToken != null && oldToken.isNotEmpty) {
        await _secureStorage.write(key: 'auth_token', value: oldToken);
        await _prefs.remove('auth_token');
      } else {
      }
      await _prefs.setBool('auth_token_migrated_v1', true);
    } catch (e) {}
  }
  Future<String?> _getToken() async {
    if (_cachedAuthToken != null) {
      return _cachedAuthToken;
    }
    await _initPrefs();
    try {
      _cachedAuthToken = await _secureStorage.read(key: 'auth_token');
    } catch (e) {
      _cachedAuthToken = _prefs.getString('auth_token_fallback');
    }
    return _cachedAuthToken;
  }
  Future<void> updateAuthToken(String token) async {
    _cachedAuthToken = token;
    try {
      await _secureStorage.write(key: 'auth_token', value: token);
    } catch (e) {
      await _prefs.setString('auth_token_fallback', token);
    }
  }
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
          rethrow;
        }
        bool shouldRetry = e is SocketException ||
            e is TimeoutException ||
            (e is IOException && e.toString().contains('Connection reset'));
        if (!shouldRetry) {
          rethrow;
        }
        await Future.delayed(backoff);
        backoff *= 2;
      }
    }
    throw Exception('Retry mechanism failed');
  }
  @override
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParams,
  }) async {
    final token = await _getToken();
    final String urlString = _resolveUrl(endpoint);
    final Uri uri = Uri.parse(urlString);
    final Uri uriWithParams =
        queryParams != null ? uri.replace(queryParameters: queryParams) : uri;
    final requestHeaders = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };
    try {
      final response = await _retryRequest(() => httpClient.get(
            uriWithParams,
            headers: requestHeaders,
          ));
      return _handleResponse(response);
    } catch (e) {
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
        return null;
      }
      rethrow;
    }
  }
  @override
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    final String urlString = _resolveUrl(endpoint);
    final token = await _getToken();
    final requestHeaders = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (headers != null) ...headers,
    };
    try {
      final response = await _retryRequest(() => httpClient.post(
            Uri.parse(urlString),
            headers: requestHeaders,
            body: jsonEncode(data),
          ));
      return _handleResponse(response);
    } catch (e) {
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
  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    final token = await _getToken();
    final urlString = _resolveUrl(endpoint);
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
  Future<dynamic> patch(String endpoint, {dynamic body}) async {
    final token = await _getToken();
    final String urlString = _resolveUrl(endpoint);
    final uri = Uri.parse(urlString);
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final response = await _retryRequest(() => httpClient.patch(
            uri,
            headers: headers,
            body: jsonEncode(body),
          ));
      return _handleResponse(response);
    } catch (e) {
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
  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    final token = await _getToken();
    final urlString = _resolveUrl(endpoint);
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
      } catch (e) {}
      throw ApiException(
        statusCode: response.statusCode,
        message: errorMessage,
      );
    }
  }
  @override
  Future<Map<String, dynamic>> uploadFile(
    String endpoint,
    String fieldName,
    Uint8List fileData,
    String fileName, {
    Map<String, String>? headers,
    Map<String, String>? additionalFields,
  }) async {
    throw UnimplementedError('File upload not yet implemented');
  }
  @override
  Future<Uint8List> downloadFile(String url) async {
    throw UnimplementedError('File download not yet implemented');
  }
  @override
  void setAuthToken(String token) {
    updateAuthToken(token);
  }
  @override
  void clearAuthToken() {
    _initPrefs().then((_) async {
      await _secureStorage.delete(key: 'auth_token');
      _cachedAuthToken = null;
    });
  }
  @override
  String? get authToken {
    return _cachedAuthToken;
  }
  @override
  String get baseUrl => configService.llmApiEndpoint;
  @override
  void setBaseUrl(String url) {
    throw UnimplementedError(
        'Base URL modification not supported - use ConfigService instead');
  }
  @override
  void setTimeout(Duration timeout) {
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
  Future<Map<String, dynamic>> callLLMDirect(
    String systemPrompt,
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      final llmConfig = LLMConfig.currentLLMConfig;
      final apiKey = await _getApiKeyForProvider(llmConfig.apiKeyEnvVar);
      if (apiKey == null || apiKey.isEmpty) {
        throw ApiException(
          statusCode: 401,
          message: 'API key not found for ${llmConfig.apiKeyEnvVar}',
        );
      }
      final headers = Map<String, String>.from(llmConfig.headers);
      headers['Authorization'] = 'Bearer $apiKey';
      final body = _buildLLMRequestBody(
        llmConfig,
        systemPrompt,
        userMessage,
        conversationHistory: conversationHistory,
        additionalParams: additionalParams,
      );
      final response = await _retryRequest(() => httpClient.post(
            Uri.parse(llmConfig.endpoint),
            headers: headers,
            body: jsonEncode(body),
          ));
      final responseData = _handleResponse(response);
      return _extractLLMResponse(responseData, LLMConfig.activeLLMProvider);
    } catch (e) {
      rethrow;
    }
  }
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
        return _buildOpenAIStyleBody(config, systemPrompt, userMessage,
            conversationHistory, additionalParams);
    }
  }
  Map<String, dynamic> _buildOpenAIStyleBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  ) {
    final messages = <Map<String, String>>[];
    messages.add({
      'role': 'system',
      'content': systemPrompt,
    });
    if (conversationHistory != null) {
      messages.addAll(conversationHistory);
    }
    messages.add({
      'role': 'user',
      'content': userMessage,
    });
    final body = {
      'model': config.modelId,
      'messages': messages,
      ...config.defaultParams,
    };
    if (additionalParams != null) {
      body.addAll(additionalParams);
    }
    return body;
  }
  Map<String, dynamic> _buildAnthropicStyleBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  ) {
    final messages = <Map<String, String>>[];
    if (conversationHistory != null) {
      for (final msg in conversationHistory) {
        if (msg['role'] != 'system') {
          messages.add(msg);
        }
      }
    }
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
    if (additionalParams != null) {
      body.addAll(additionalParams);
    }
    return body;
  }
  Map<String, dynamic> _buildGoogleStyleBody(
    LLMModelConfig config,
    String systemPrompt,
    String userMessage,
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? additionalParams,
  ) {
    final contents = <Map<String, dynamic>>[];
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
    if (additionalParams != null) {
      body.addAll(additionalParams);
    }
    return body;
  }
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
        return _extractLLMResponse(response, LLMProvider.openai);
    }
    throw ApiException(
      statusCode: 500,
      message: 'Unable to extract response from LLM provider: $provider',
    );
  }
  Future<String?> _getApiKeyForProvider(String envVarName) async {
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
