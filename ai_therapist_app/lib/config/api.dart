// lib/config/api.dart
class ApiConfig {
  static const String baseUrl = 'http://localhost:8000/api/v1';
  
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