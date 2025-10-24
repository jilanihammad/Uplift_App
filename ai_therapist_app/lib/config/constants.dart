// lib/config/constants.dart

class AppConstants {
  // App Info
  static const String appName = 'Maya';
  static const String appVersion = '1.0.0';

  // Storage Keys
  static const String tokenKey = 'token';
  static const String userDataKey = 'user_data';
  static const String onboardingCompleteKey = 'onboarding_complete';

  // Assessment
  static const List<String> primaryGoals = [
    'Improve general wellbeing',
    'Cope with specific challenges',
    'Personal growth',
    'Improve relationships',
    'Gain self-awareness',
  ];

  static const List<Map<String, String>> challengeOptions = [
    {'id': 'anxiety', 'name': 'Anxiety'},
    {'id': 'depression', 'name': 'Depression'},
    {'id': 'stress', 'name': 'Stress'},
    {'id': 'sleep', 'name': 'Sleep problems'},
    {'id': 'relationships', 'name': 'Relationship issues'},
    {'id': 'loneliness', 'name': 'Loneliness'},
    {'id': 'self_esteem', 'name': 'Self-esteem'},
    {'id': 'work', 'name': 'Work/career stress'},
    {'id': 'trauma', 'name': 'Past trauma'},
    {'id': 'grief', 'name': 'Grief/loss'},
  ];

  static const List<Map<String, String>> approachOptions = [
    {'id': 'practical', 'name': 'Practical and solution-focused'},
    {'id': 'emotional', 'name': 'Emotional support and validation'},
    {'id': 'balanced', 'name': 'Balanced combination'},
  ];

  // Mood Tracking
  static const List<Map<String, dynamic>> moodOptions = [
    {'value': 1, 'emoji': '😢', 'label': 'Very Bad'},
    {'value': 2, 'emoji': '😕', 'label': 'Bad'},
    {'value': 3, 'emoji': '😐', 'label': 'Neutral'},
    {'value': 4, 'emoji': '🙂', 'label': 'Good'},
    {'value': 5, 'emoji': '😄', 'label': 'Very Good'},
  ];

  // Subscription
  static const int trialDurationDays = 7;

  // Animation Durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 400);
  static const Duration longAnimationDuration = Duration(milliseconds: 800);
}
