// lib/config/api.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class ApiConfig {
  // Use a getter for baseUrl that checks the environment
  static String get baseUrl {
    return kDebugMode
        ? 'http://10.0.2.2:8001/api/v1'
        : 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app/api/v1';
  }
  
  // Add a getter for the base URL without the /api/v1 path
  static String get baseUrlWithoutPath {
    return kDebugMode
        ? 'http://10.0.2.2:8001'
        : 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';
  }
  
  // Check if the backend is available
  static Future<bool> isBackendAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/llm/status'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      // Log the response for debugging
      debugPrint('Backend availability check: ${response.statusCode} - ${response.statusCode >= 200 && response.statusCode < 300}');
      
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Backend availability check failed: $e');
      return false;
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