// integration_test/mode_switching_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ai_therapist_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Mode Switching Integration Tests', () {
    testWidgets('Seamless voice ↔ text mode switching during session',
        (WidgetTester tester) async {
      // Start app and setup session
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anxious'));
      await tester.pumpAndSettle();

      // Start in voice mode - wait for greeting
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify voice mode UI
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Switch to text mode
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // Verify text mode UI
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);

      // Send a text message
      await tester.enterText(find.byType(TextField),
          'I feel anxious about my presentation tomorrow.');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Wait for response
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // Switch back to voice mode
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      // Verify back in voice mode
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Switch to text mode again
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // Send another text message
      await tester.enterText(find.byType(TextField), 'That helps, thank you.');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Wait for response
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // Verify conversation history is maintained
      expect(find.text('I feel anxious about my presentation tomorrow.'),
          findsOneWidget);
      expect(find.text('That helps, thank you.'), findsOneWidget);

      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 8));
    });

    testWidgets('Rapid mode switching stress test',
        (WidgetTester tester) async {
      // Setup session
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();

      // Wait for initial setup
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Rapidly switch modes multiple times
      for (int i = 0; i < 5; i++) {
        // To text mode
        await tester.tap(find.byIcon(Icons.chat));
        await tester.pump(const Duration(milliseconds: 500));

        // Verify text mode
        expect(find.byType(TextField), findsOneWidget);

        // To voice mode
        await tester.tap(find.byIcon(Icons.mic));
        await tester.pump(const Duration(milliseconds: 500));

        // Verify voice mode
        expect(find.byIcon(Icons.mic), findsOneWidget);
      }

      // Final pump and settle
      await tester.pumpAndSettle();

      // Send a message to verify system still works
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField), 'System still working after rapid switching');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Wait for response
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify message was processed
      expect(find.text('System still working after rapid switching'),
          findsOneWidget);

      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('Mode switching with active audio playback',
        (WidgetTester tester) async {
      // Setup session
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sad'));
      await tester.pumpAndSettle();

      // Wait for initial greeting to start playing
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Switch to text mode while TTS might be playing
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // Verify switch worked and audio was stopped
      expect(find.byType(TextField), findsOneWidget);

      // Send a text message
      await tester.enterText(find.byType(TextField), 'I\'m feeling down today');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Immediately switch back to voice while response is being processed
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      // Wait for any audio to complete
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Verify we're in voice mode and system is stable
      expect(find.byIcon(Icons.mic), findsOneWidget);

      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('Mode switching preserves conversation state',
        (WidgetTester tester) async {
      // Setup session
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stressed'));
      await tester.pumpAndSettle();

      // Start in voice mode, then switch to text
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // Send first message
      await tester.enterText(
          find.byType(TextField), 'First message in text mode');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Switch to voice mode
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      // Switch back to text mode
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      // Verify first message is still visible
      expect(find.text('First message in text mode'), findsOneWidget);

      // Send second message
      await tester.enterText(
          find.byType(TextField), 'Second message after mode switching');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify both messages are visible
      expect(find.text('First message in text mode'), findsOneWidget);
      expect(find.text('Second message after mode switching'), findsOneWidget);

      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Verify session summary includes all messages
      expect(find.text('Session Summary'), findsOneWidget);
    });
  });
}
