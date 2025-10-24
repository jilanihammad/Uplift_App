// integration_test/voice_session_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ai_therapist_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Voice Session Integration Tests', () {
    testWidgets('Complete voice therapy session end-to-end',
        (WidgetTester tester) async {
      // Start app
      app.main();
      await tester.pumpAndSettle();

      // Navigate to therapy session (skip auth for now)
      // This assumes the app starts authenticated or has guest mode
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();

      // Duration selection
      expect(find.text('Session Duration'), findsOneWidget);
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();

      // Mood selection
      expect(find.text('How are you feeling?'), findsOneWidget);
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();

      // Should be in voice mode with Maya greeting
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Wait for initial greeting to complete
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify voice controls are visible
      expect(find.byIcon(Icons.mic), findsOneWidget);

      // Test mode switching from voice to text
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // Should now be in text mode
      expect(find.byType(TextField), findsOneWidget);

      // Send a text message
      await tester.enterText(
          find.byType(TextField), 'I had a great day today!');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Wait for AI response
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify message appears in chat
      expect(find.text('I had a great day today!'), findsOneWidget);

      // Switch back to voice mode
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      // Should be back in voice mode
      expect(find.byType(TextField), findsNothing);

      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();

      // Confirm end session
      expect(find.text('End Session'), findsOneWidget);
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle();

      // Wait for session summary generation
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // Should be on session summary screen
      expect(find.text('Session Summary'), findsOneWidget);

      // Verify summary contains expected elements
      expect(find.text('Key Insights'), findsOneWidget);
      expect(find.text('Action Items'), findsOneWidget);
    });

    testWidgets('Voice session interruption and recovery',
        (WidgetTester tester) async {
      // Start app and navigate to session
      app.main();
      await tester.pumpAndSettle();

      // Quick session setup
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anxious'));
      await tester.pumpAndSettle();

      // Wait for greeting
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Simulate app lifecycle interruption
      final binding = tester.binding;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/lifecycle',
        (message) async {
          return null;
        },
      );

      // Simulate going to background
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StandardMethodCodec()
            .encodeSuccessEnvelope('AppLifecycleState.paused'),
        (data) {},
      );
      await tester.pumpAndSettle();

      // Simulate returning to foreground
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StandardMethodCodec()
            .encodeSuccessEnvelope('AppLifecycleState.resumed'),
        (data) {},
      );
      await tester.pumpAndSettle();

      // Verify session is still active
      expect(find.byIcon(Icons.mic), findsOneWidget);

      // End session normally
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
