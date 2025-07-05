// integration_test/text_session_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ai_therapist_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Text Session Integration Tests', () {
    testWidgets('Complete text therapy session end-to-end', (WidgetTester tester) async {
      // Start app
      app.main();
      await tester.pumpAndSettle();
      
      // Navigate to therapy session
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      
      // Duration selection
      expect(find.text('Session Duration'), findsOneWidget);
      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      
      // Mood selection
      expect(find.text('How are you feeling?'), findsOneWidget);
      await tester.tap(find.text('Stressed'));
      await tester.pumpAndSettle();
      
      // Wait for initial setup
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Switch to text mode immediately
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      // Should be in text mode
      expect(find.byType(TextField), findsOneWidget);
      
      // Conduct a multi-turn conversation
      final messages = [
        'I\'ve been feeling overwhelmed with work lately.',
        'Yes, I have multiple deadlines this week.',
        'I think better time management could help.',
        'Thank you for listening and the advice.'
      ];
      
      for (int i = 0; i < messages.length; i++) {
        // Send message
        await tester.enterText(find.byType(TextField), messages[i]);
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        
        // Wait for AI response
        await tester.pumpAndSettle(const Duration(seconds: 8));
        
        // Verify message appears
        expect(find.text(messages[i]), findsOneWidget);
        
        // Clear text field for next message
        await tester.enterText(find.byType(TextField), '');
      }
      
      // Verify conversation history
      expect(find.text(messages[0]), findsOneWidget);
      expect(find.text(messages.last), findsOneWidget);
      
      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      
      // Confirm end session
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle();
      
      // Wait for session processing
      await tester.pumpAndSettle(const Duration(seconds: 10));
      
      // Should be on session summary
      expect(find.text('Session Summary'), findsOneWidget);
    });
    
    testWidgets('Text session with rapid message sending', (WidgetTester tester) async {
      // Start app and setup session
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();
      
      // Switch to text mode
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      // Test rapid message sending (stress test)
      final rapidMessages = [
        'Hello',
        'How are you?',
        'I\'m doing well today'
      ];
      
      for (final message in rapidMessages) {
        await tester.enterText(find.byType(TextField), message);
        await tester.tap(find.byIcon(Icons.send));
        // Don't wait for response - send rapidly
        await tester.pump();
      }
      
      // Wait for all responses to complete
      await tester.pumpAndSettle(const Duration(seconds: 15));
      
      // Verify all messages are present
      for (final message in rapidMessages) {
        expect(find.text(message), findsOneWidget);
      }
      
      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
    
    testWidgets('Empty message handling in text mode', (WidgetTester tester) async {
      // Setup session
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neutral'));
      await tester.pumpAndSettle();
      
      // Switch to text mode
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      // Try to send empty message
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      
      // Verify no empty message was sent
      // The send button should be disabled or message should be ignored
      
      // Send whitespace only
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      
      // Send actual message to verify system still works
      await tester.enterText(find.byType(TextField), 'This is a real message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      
      // Wait for response
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Verify real message appears
      expect(find.text('This is a real message'), findsOneWidget);
      
      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}