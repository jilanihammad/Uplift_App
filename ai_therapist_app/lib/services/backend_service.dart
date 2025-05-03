import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api.dart';

class BackendService {
  // Singleton pattern implementation
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  // Status variables
  bool _isAvailable = false;
  DateTime? _lastChecked;
  final _cacheValidDuration = const Duration(minutes: 5);

  // Result caching for expensive operations
  final Map<String, dynamic> _responseCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  // Cache duration by endpoint type
  final Map<String, Duration> _cacheDurations = {
    'default': const Duration(minutes: 5),
    'status': const Duration(minutes: 1),
    'user': const Duration(minutes: 10),
    'session': const Duration(seconds: 30),
  };

  /// Checks if the backend is available
  /// This will cache the result for 5 minutes to avoid excessive calls
  Future<bool> isBackendAvailable() async {
    // Use cached result if available and recent
    if (_lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < _cacheValidDuration) {
      if (kDebugMode) {
        print('Backend availability using cached result: $_isAvailable');
      }
      return _isAvailable;
    }

    // Create a more aggressive timeout for better UX
    final connectionTimeout = const Duration(seconds: 2);

    try {
      // First try DNS resolution by making a basic connection
      final baseUriString = ApiConfig.baseUrlWithoutPath;
      if (kDebugMode) {
        print('Testing backend connectivity to: $baseUriString');
      }

      // Use a simple status endpoint that should respond quickly
      final uri = Uri.parse('$baseUriString/api/v1/llm/status');
      if (kDebugMode) {
        print('Making connectivity request to: $uri');
      }

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(connectionTimeout);

      // Special handling for 405 Method Not Allowed - backend might be running
      // but the endpoint might not support GET (common issue in development)
      if (response.statusCode == 200 ||
          response.statusCode == 405 ||
          response.statusCode == 404) {
        _isAvailable = true;
        _lastChecked = DateTime.now();
        if (kDebugMode) {
          print('Backend is available! Status code: ${response.statusCode}');
          print(
              'Response body: ${response.body.length > 100 ? '${response.body.substring(0, 100)}...' : response.body}');
        }
        return true;
      }

      _isAvailable = false;
      _lastChecked = DateTime.now();
      if (kDebugMode) {
        print(
            'Backend availability check: ${response.statusCode} - Not available');
        print(
            'Response body: ${response.body.length > 100 ? '${response.body.substring(0, 100)}...' : response.body}');
      }
      return false;
    } catch (e) {
      _isAvailable = false;
      _lastChecked = DateTime.now();
      if (kDebugMode) {
        print('Backend connectivity failed with error: $e');
        // More helpful message for common connection errors
        if (e is SocketException) {
          print(
              'Network socket error: Device may be offline or the server is unreachable');
        } else if (e is TimeoutException) {
          print('Connection timed out: Backend server is too slow to respond');
        } else {
          print('Unknown connection error: $e');
        }
        print(
            'Make sure your device has internet connectivity and the backend URL is correct');
        print('Current backend URL: ${ApiConfig.baseUrlWithoutPath}');
      }

      // Still try to function without backend - just mark as offline
      return false;
    }
  }

  /// Executes an API call with fallback behavior when backend is unavailable
  /// This is useful for handling offline mode gracefully
  Future<T> executeWithFallback<T>({
    required Future<T> Function() apiCall,
    required T Function() fallbackResponse,
    bool forceCheck = false,
    String endpointType = 'default',
  }) async {
    // Check if backend is available, but only if not checked recently
    // unless forced to check
    if (forceCheck ||
        _lastChecked == null ||
        DateTime.now().difference(_lastChecked!) > _cacheValidDuration) {
      await isBackendAvailable();
    }

    if (!_isAvailable) {
      // If backend is not available, return fallback response
      return fallbackResponse();
    }

    try {
      // Try to execute the API call
      return await apiCall();
    } catch (e) {
      if (kDebugMode) {
        print('API call failed with error: $e');
      }
      // If API call fails, return fallback response
      return fallbackResponse();
    }
  }

  /// Caches a response for a given endpoint
  void _cacheResponse(String endpoint, dynamic response) {
    _responseCache[endpoint] = response;
    _cacheTimestamps[endpoint] = DateTime.now();
  }

  /// Gets a cached response for a given endpoint if available and not expired
  dynamic _getCachedResponse(String endpoint, String type) {
    final timestamp = _cacheTimestamps[endpoint];
    if (timestamp == null) return null;

    final cacheDuration = _cacheDurations[type] ?? _cacheDurations['default']!;

    if (DateTime.now().difference(timestamp) < cacheDuration) {
      return _responseCache[endpoint];
    }

    // Cached response is expired
    return null;
  }

  /// Executes a GET request with caching
  Future<Map<String, dynamic>> getWithCache(
    String endpoint, {
    Map<String, String>? headers,
    bool forceRefresh = false,
    String cacheType = 'default',
  }) async {
    // Check if there's a valid cached response
    if (!forceRefresh) {
      final cachedResponse = _getCachedResponse(endpoint, cacheType);
      if (cachedResponse != null) {
        return cachedResponse;
      }
    }

    // No valid cache, execute the API call
    return executeWithFallback<Map<String, dynamic>>(
      apiCall: () async {
        final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
        final response = await http
            .get(
              uri,
              headers: headers ?? {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final jsonResponse = await compute(_parseJson, response.body);
          _cacheResponse(endpoint, jsonResponse);
          return jsonResponse;
        } else {
          throw Exception(
              'API Error: ${response.statusCode} - ${response.reasonPhrase}');
        }
      },
      fallbackResponse: () => {'error': 'Failed to connect to backend'},
      endpointType: cacheType,
    );
  }

  /// Parses JSON in a separate isolate to avoid blocking the main thread
  static Map<String, dynamic> _parseJson(String responseBody) {
    return Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
  }

  /// A convenient getter to check if app is in offline mode
  bool get isOfflineMode => !_isAvailable;
}
