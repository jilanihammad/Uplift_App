// lib/data/datasources/remote/api_client.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../../../services/config_service.dart'; // Corrected import path
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/config/app_config.dart'; // Import AppConfig
import 'package:ai_therapist_app/config/llm_config.dart'; // Import LLM Configuration

class ApiClient {
  final http.Client httpClient;
  final ConfigService configService; // Add ConfigService field
  late SharedPreferences _prefs;
  bool _initialized = false;
  // Increased timeout duration
  final Duration _timeout = const Duration(seconds: 15);
  // Max number of retries for transient errors
  final int _maxRetries = 3;

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
      print('ApiClient: Updated auth token');
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
            print('Request failed after $_maxRetries attempts: $e');
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
          print(
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
  Future<dynamic> get(String endpoint,
      {Map<String, dynamic>? queryParams}) async {
    final token = await _getToken();
    final baseUrl = configService.llmApiEndpoint; // Get baseUrl just-in-time
    debugPrint('[RELEASE DEBUG] ApiClient.get - Using baseUrl: "$baseUrl"');

    final bool needsApiPrefix = !endpoint.startsWith('/voice/') &&
        !endpoint.startsWith('/ai/') &&
        !endpoint.startsWith('/therapy/') &&
        !endpoint.startsWith('/sessions');

    final String urlString = needsApiPrefix
        ? '$baseUrl$endpoint'
        : baseUrl.replaceAll('/api/v1', '') + endpoint;

    final Uri uri = Uri.parse(urlString);
    final Uri uriWithParams =
        queryParams != null ? uri.replace(queryParameters: queryParams) : uri;

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      if (kDebugMode) {
        print('Making GET request to: $uriWithParams');
      }

      final response = await _retryRequest(() => httpClient.get(
            uriWithParams,
            headers: headers,
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        print('GET request failed: $e');
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

  /// POST request to the API
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    String contentType = 'application/json',
    bool isFormData = false,
    Map<String, String>? additionalHeaders,
    Map<String, String>? queryParams,
    bool forceAuth = false,
    bool handleErrors = true,
  }) async {
    if (kDebugMode) {
      debugPrint(
          '[RELEASE DEBUG] ApiClient.post - Starting post request to endpoint: $endpoint');
    }

    // Force the URL to be the backend URL from AppConfig
    final String forcedBaseUrl = AppConfig().backendUrl;

    // Construct the complete URL - handle special endpoints differently
    String urlString;
    if (endpoint.startsWith('/voice/') ||
        endpoint.startsWith('/ai/') ||
        endpoint.startsWith('/therapy/') ||
        endpoint.startsWith('/sessions')) {
      // These endpoints don't need the /api/v1 prefix
      urlString = '$forcedBaseUrl$endpoint';
    } else if (endpoint.startsWith('/api/')) {
      // These endpoints already have /api prefix
      urlString = '$forcedBaseUrl$endpoint';
    } else {
      // Regular API endpoint needs the /api/v1 prefix
      urlString = '$forcedBaseUrl/api/v1$endpoint';
    }

    final token = await _getToken();

    final headers = {
      'Content-Type': contentType,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      if (kDebugMode) {
        print('Making POST request to: $urlString');
      }

      final response = await _retryRequest(() => httpClient.post(
            Uri.parse(urlString),
            headers: headers,
            body: jsonEncode(body),
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        print('POST request failed: $e');
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
  Future<dynamic> put(String endpoint, {dynamic body}) async {
    final token = await _getToken();
    final baseUrl = configService.llmApiEndpoint; // Get baseUrl just-in-time
    debugPrint('[RELEASE DEBUG] ApiClient.put - Using baseUrl: "$baseUrl"');
    final uri = Uri.parse('$baseUrl$endpoint');

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await _retryRequest(() => httpClient.put(
            uri,
            headers: headers,
            body: jsonEncode(body),
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        print('PUT request failed: $e');
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
    final baseUrl = configService.llmApiEndpoint; // Get baseUrl just-in-time
    debugPrint('[RELEASE DEBUG] ApiClient.patch - Using baseUrl: "$baseUrl"');

    final bool needsApiPrefix = !endpoint.startsWith('/voice/') &&
        !endpoint.startsWith('/ai/') &&
        !endpoint.startsWith('/therapy/') &&
        !endpoint.startsWith('/sessions');

    final String urlString = needsApiPrefix
        ? '$baseUrl$endpoint'
        : baseUrl.replaceAll('/api/v1', '') + endpoint;
    debugPrint(
        '[RELEASE DEBUG] ApiClient.patch - Constructed urlString: "$urlString"');

    final uri = Uri.parse(urlString);

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      if (kDebugMode) {
        print('Making PATCH request to: $uri');
      }

      final response = await _retryRequest(() => httpClient.patch(
            uri,
            headers: headers,
            body: jsonEncode(body),
          ));

      return _handleResponse(response);
    } catch (e) {
      if (kDebugMode) {
        print('PATCH request failed: $e');
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
  Future<dynamic> delete(String endpoint) async {
    final token = await _getToken();
    final baseUrl = configService.llmApiEndpoint; // Get baseUrl just-in-time
    debugPrint('[RELEASE DEBUG] ApiClient.delete - Using baseUrl: "$baseUrl"');
    final uri = Uri.parse('$baseUrl$endpoint');

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
        print('DELETE request failed: $e');
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
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {};
      }
      return jsonDecode(response.body);
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

  // Close the client when done
  void close() {
    httpClient.close();
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
        print('[ApiClient] Making direct LLM call to ${llmConfig.modelId}');
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
        print('[ApiClient] LLM Request to: ${llmConfig.endpoint}');
        print('[ApiClient] LLM Model: ${llmConfig.modelId}');
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
        print('[ApiClient] Direct LLM call failed: $e');
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

class TimeoutException extends IOException {
  final String message;

  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
