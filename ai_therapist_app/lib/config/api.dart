// lib/config/api.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:ai_therapist_app/config/app_config.dart';

class ApiConfig {
  // Use a getter for baseUrl that uses AppConfig
  static String get baseUrl {
    // Use the cloud backend URL from AppConfig
    return '${AppConfig().apiBaseUrl}';
  }

  // Add a getter for the base URL without the /api/v1 path
  static String get baseUrlWithoutPath {
    // Use the cloud backend URL from AppConfig
    return AppConfig().backendUrl;
  }

  // Firebase project URL
  static String get firebaseProjectUrl {
    return 'https://upliftapp-cd86e.web.app';
  }

  // Check if the backend is available
  static Future<bool> isBackendAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/llm/status');
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      // Log the response for debugging
      debugPrint(
          'Backend availability check: ${response.statusCode} - ${response.statusCode >= 200 && response.statusCode < 300}');

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Backend availability check failed: $e');
      return false;
    }
  }

  // Execute a function with fallback if backend is unavailable
  static Future<T> executeWithFallback<T>({
    required Future<T> Function() apiCall,
    required T Function() fallback,
  }) async {
    try {
      // First check if backend is available
      final isAvailable = await isBackendAvailable();
      if (!isAvailable) {
        debugPrint('Backend unavailable, using fallback');
        return fallback();
      }

      // Try to execute the API call
      return await apiCall();
    } catch (e) {
      debugPrint('API call failed, using fallback: $e');
      return fallback();
    }
  }

  // Authentication endpoints
  static const String login = '/auth/login';
  static const String register = '/auth/register';

  // User endpoints
  static const String user = '/users/me';

  // Assessment endpoints
  static const String assessments = '/assessments';
  static const String latestAssessment = '/assessments/latest';

  // Session endpoints
  static const String sessions = '/sessions';
  static const String activeSession = '/sessions/active';

  // Message endpoints
  static const String messages = '/messages';

  // Action plan endpoints
  static const String actionPlans = '/action-plans';

  // Note endpoints
  static const String notes = '/notes';

  // Reminder endpoints
  static const String reminders = '/reminders';

  // Subscription endpoints
  static const String subscriptions = '/subscriptions';
  static const String subscriptionPlans = '/subscriptions/plans';
  static const String subscriptionTrial = '/subscriptions/trial';
  static const String subscriptionCheckout = '/subscriptions/checkout';
  static const String subscriptionCancel = '/subscriptions/cancel';
}
