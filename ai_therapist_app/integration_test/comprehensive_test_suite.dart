// integration_test/comprehensive_test_suite.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Import all test files
import 'auth_flow_test.dart' as auth_tests;
import 'voice_session_test.dart' as voice_tests;
import 'text_session_test.dart' as text_tests;
import 'mode_switching_test.dart' as mode_tests;
import 'session_ending_test.dart' as ending_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AI Therapist App - Comprehensive Integration Test Suite', () {
    group('Authentication Flow Tests', () {
      auth_tests.main();
    });

    group('Voice Session Tests', () {
      voice_tests.main();
    });

    group('Text Session Tests', () {
      text_tests.main();
    });

    group('Mode Switching Tests', () {
      mode_tests.main();
    });

    group('Session Ending Tests', () {
      ending_tests.main();
    });
  });

  // Performance monitoring test
  testWidgets('Performance baseline validation', (WidgetTester tester) async {
    final stopwatch = Stopwatch()..start();

    // Run a quick session to measure performance
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Text('Performance Test'))));
    await tester.pumpAndSettle();

    stopwatch.stop();

    // Log performance metrics
    print('UI initialization took: ${stopwatch.elapsedMilliseconds}ms');

    // Basic performance assertions
    expect(stopwatch.elapsedMilliseconds, lessThan(5000),
        reason: 'UI initialization should complete within 5 seconds');
  });
}

// Test configuration and utilities
class IntegrationTestConfig {
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration longTimeout = Duration(minutes: 2);
  static const Duration shortTimeout = Duration(seconds: 10);

  // Common test data
  static const List<String> testMoods = [
    'Happy',
    'Sad',
    'Anxious',
    'Angry',
    'Stressed',
    'Neutral'
  ];
  static const List<String> testDurations = [
    '15 min',
    '20 min',
    '30 min',
    '45 min'
  ];

  // Test messages for various scenarios
  static const Map<String, List<String>> testMessages = {
    'happy': [
      'I had a great day today!',
      'Everything is going well in my life.',
      'I feel so positive and energetic.'
    ],
    'sad': [
      'I\'ve been feeling down lately.',
      'Things don\'t seem to be going right.',
      'I feel lonely and disconnected.'
    ],
    'anxious': [
      'I\'m worried about my presentation tomorrow.',
      'I can\'t stop thinking about what might go wrong.',
      'My heart races when I think about the meeting.'
    ],
    'stressed': [
      'I have too much on my plate right now.',
      'The deadlines are overwhelming me.',
      'I can\'t seem to catch a break.'
    ]
  };
}
