import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api.dart';
class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();
  bool _isAvailable = false;
  DateTime? _lastChecked;
  final _cacheValidDuration = const Duration(minutes: 5);
  bool _isInitialized = false;
  final Map<String, dynamic> _responseCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Duration> _cacheDurations = {
    'default': const Duration(minutes: 5),
    'status': const Duration(minutes: 1),
    'user': const Duration(minutes: 10),
    'session': const Duration(seconds: 30),
  };
  Future<bool> init() async {
    try {
      final baseUrl = ApiConfig.baseUrlWithoutPath;
      if (baseUrl.isEmpty) {
        _isInitialized = false;
        return false;
      }
      _isInitialized = true;
      return true;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }
  Future<bool> isBackendAvailable() async {
    if (!_isInitialized) {
      final initialized = await init();
      if (!initialized) {
        return false;
      }
    }
    if (_lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < _cacheValidDuration) {
      return _isAvailable;
    }
    const connectionTimeout = Duration(seconds: 2);
    try {
      final baseUriString = ApiConfig.baseUrlWithoutPath;
      final uri = Uri.parse('$baseUriString/api/v1/llm/status');
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(connectionTimeout);
      if (response.statusCode == 200 ||
          response.statusCode == 405 ||
          response.statusCode == 404) {
        _isAvailable = true;
        _lastChecked = DateTime.now();
        return true;
      }
      _isAvailable = false;
      _lastChecked = DateTime.now();
      return false;
    } catch (e) {
      _isAvailable = false;
      _lastChecked = DateTime.now();
      return false;
    }
  }
  Future<T> executeWithFallback<T>({
    required Future<T> Function() apiCall,
    required T Function() fallbackResponse,
    bool forceCheck = false,
    String endpointType = 'default',
  }) async {
    if (forceCheck ||
        _lastChecked == null ||
        DateTime.now().difference(_lastChecked!) > _cacheValidDuration) {
      await isBackendAvailable();
    }
    if (!_isAvailable) {
      return fallbackResponse();
    }
    try {
      return await apiCall();
    } catch (e) {
      return fallbackResponse();
    }
  }
  void _cacheResponse(String endpoint, dynamic response) {
    _responseCache[endpoint] = response;
    _cacheTimestamps[endpoint] = DateTime.now();
  }
  dynamic _getCachedResponse(String endpoint, String type) {
    final timestamp = _cacheTimestamps[endpoint];
    if (timestamp == null) return null;
    final cacheDuration = _cacheDurations[type] ?? _cacheDurations['default']!;
    if (DateTime.now().difference(timestamp) < cacheDuration) {
      return _responseCache[endpoint];
    }
    return null;
  }
  Future<Map<String, dynamic>> getWithCache(
    String endpoint, {
    Map<String, String>? headers,
    bool forceRefresh = false,
    String cacheType = 'default',
  }) async {
    if (!forceRefresh) {
      final cachedResponse = _getCachedResponse(endpoint, cacheType);
      if (cachedResponse != null) {
        return cachedResponse;
      }
    }
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
  static Map<String, dynamic> _parseJson(String responseBody) {
    return Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
  }
  bool get isOfflineMode => !_isAvailable;
}
