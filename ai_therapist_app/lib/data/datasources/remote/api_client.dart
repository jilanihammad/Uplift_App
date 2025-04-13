// lib/data/datasources/remote/api_client.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  final String baseUrl;
  final http.Client httpClient;
  late SharedPreferences _prefs;
  bool _initialized = false;
  // Increased timeout duration
  final Duration _timeout = const Duration(seconds: 15);
  // Max number of retries for transient errors
  final int _maxRetries = 3;
  
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client() {
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
  
  // Retry mechanism for handling transient errors
  Future<http.Response> _retryRequest(Future<http.Response> Function() requestFunc) async {
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
          print('Request failed (attempt $attempts): $e. Retrying in ${backoff.inMilliseconds}ms...');
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
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    final token = await _getToken();
    final uri = Uri.parse('$baseUrl$endpoint').replace(
      queryParameters: queryParams,
    );
    
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    
    try {
      final response = await _retryRequest(() => httpClient.get(
        uri,
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
          message: 'Connection error: ${e.message}. Please check your internet connection.',
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
  
  // POST request
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    final token = await _getToken();
    final uri = Uri.parse('$baseUrl$endpoint');
    
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    
    try {
      final response = await _retryRequest(() => httpClient.post(
        uri,
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
          message: 'Connection error: ${e.message}. Please check your internet connection.',
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
          message: 'Connection error: ${e.message}. Please check your internet connection.',
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
    final uri = Uri.parse('$baseUrl$endpoint');
    
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
      if (kDebugMode) {
        print('PATCH request failed: $e');
      }
      
      if (e is SocketException) {
        throw ApiException(
          statusCode: 0,
          message: 'Connection error: ${e.message}. Please check your internet connection.',
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
          message: 'Connection error: ${e.message}. Please check your internet connection.',
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
  
  // Handle API response
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: _getErrorMessage(response),
      );
    }
  }
  
  // Extract error message from response
  String _getErrorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['detail'] ?? body['message'] ?? 'Unknown error occurred';
    } catch (e) {
      return response.reasonPhrase ?? 'Unknown error occurred';
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  
  ApiException({required this.statusCode, required this.message});
  
  @override
  String toString() => 'ApiException: [$statusCode] $message';
}

class TimeoutException extends IOException {
  final String message;
  
  TimeoutException(this.message);
  
  @override
  String toString() => 'TimeoutException: $message';
}