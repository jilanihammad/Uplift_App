// lib/config/api.dart
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:ai_therapist_app/config/app_config.dart';
class ApiConfig {
  static String get baseUrl {
    return AppConfig().apiBaseUrl;
  }
  static String get baseUrlWithoutPath {
    return AppConfig().backendUrl;
  }
  static String get firebaseProjectUrl {
    return 'https://upliftapp-cd86e.web.app';
  }
  static Future<bool> isBackendAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/llm/status');
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
  static Future<T> executeWithFallback<T>({
    required Future<T> Function() apiCall,
    required T Function() fallback,
  }) async {
    try {
      final isAvailable = await isBackendAvailable();
      if (!isAvailable) {
        return fallback();
      }
      return await apiCall();
    } catch (e) {
      return fallback();
    }
  }
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String user = '/users/me';
  static const String assessments = '/assessments';
  static const String latestAssessment = '/assessments/latest';
  static const String sessions = '/sessions';
  static const String activeSession = '/sessions/active';
  static const String messages = '/messages';
  static const String actionPlans = '/action-plans';
  // Note endpoints
  static const String notes = '/notes';
  static const String reminders = '/reminders';
  static const String subscriptions = '/subscriptions';
  static const String subscriptionPlans = '/subscriptions/plans';
  static const String subscriptionTrial = '/subscriptions/trial';
  static const String subscriptionCheckout = '/subscriptions/checkout';
  static const String subscriptionCancel = '/subscriptions/cancel';
}
