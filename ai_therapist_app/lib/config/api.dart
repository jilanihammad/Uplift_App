// lib/config/api.dart
import 'package:flutter/foundation.dart';

class ApiConfig {
  // Use a getter for baseUrl that checks the environment
  static String get baseUrl {
    return kDebugMode
        ? 'http://10.0.2.2:8000/api/v1'
        : 'https://api-fuukqlcsha-uc.a.run.app/api/v1';
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