// integration_test/session_ending_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ai_therapist_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Session Ending and Navigation Tests', () {
    testWidgets('Normal session ending flow', (WidgetTester tester) async {
      // Setup complete session
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();
      
      // Conduct short conversation
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      await tester.enterText(find.byType(TextField), 'I had a wonderful day today!');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 6));
      
      // End session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      
      // Verify confirmation dialog
      expect(find.text('End Session'), findsOneWidget);
      expect(find.text('Are you sure you want to end this session?'), findsOneWidget);
      
      // Confirm ending
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle();
      
      // Verify processing dialog appears
      expect(find.text('Generating session summary...'), findsOneWidget);
      
      // Wait for summary generation
      await tester.pumpAndSettle(const Duration(seconds: 15));
      
      // Verify navigation to summary screen
      expect(find.text('Session Summary'), findsOneWidget);
      expect(find.text('Key Insights'), findsOneWidget);
      expect(find.text('Action Items'), findsOneWidget);
      
      // Verify navigation back to home
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      
      // Should be back on home screen
      expect(find.text('How are you feeling today?'), findsOneWidget);
    });
    
    testWidgets('Cancel session ending', (WidgetTester tester) async {
      // Setup session
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neutral'));
      await tester.pumpAndSettle();
      
      // Start conversation
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      await tester.enterText(find.byType(TextField), 'Just testing the cancel flow');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      
      // Try to end session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      
      // Cancel instead of confirming
      expect(find.text('End Session'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      
      // Should still be in session
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Just testing the cancel flow'), findsOneWidget);
      
      // Send another message to verify session continues
      await tester.enterText(find.byType(TextField), 'Session continued after cancel');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Now actually end session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });
    
    testWidgets('Back button prevention during active session', (WidgetTester tester) async {
      // Setup active session
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Happy'));
      await tester.pumpAndSettle();
      
      // Conduct conversation to make session active
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      await tester.enterText(find.byType(TextField), 'Testing back button prevention');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Try to use back button (simulate back gesture)
      final backButton = find.byType(BackButton);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton);
        await tester.pumpAndSettle();
        
        // Should show snackbar preventing navigation
        expect(find.text('Please use the End button to finish your session.'), findsOneWidget);
        
        // Should still be in session
        expect(find.byType(TextField), findsOneWidget);
      }
      
      // End session properly
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle(const Duration(seconds: 8));
    });
    
    testWidgets('Session ending with network error recovery', (WidgetTester tester) async {
      // Setup session
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anxious'));
      await tester.pumpAndSettle();
      
      // Quick conversation
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();
      
      await tester.enterText(find.byType(TextField), 'Testing error recovery');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Try to end session
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle();
      
      // Wait for processing - may fail due to network
      await tester.pumpAndSettle(const Duration(seconds: 20));
      
      // Check if error snackbar appears and retry option exists
      final retryButton = find.text('Try Again');
      if (retryButton.evaluate().isNotEmpty) {
        await tester.tap(retryButton);
        await tester.pumpAndSettle();
        
        // Wait for retry
        await tester.pumpAndSettle(const Duration(seconds: 15));
      }
      
      // Should eventually reach summary or show proper error handling
      expect(find.text('Session Summary'), findsAny);
    });
    
    testWidgets('Empty session ending (no messages)', (WidgetTester tester) async {
      // Setup session but don't send any messages
      app.main();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Start Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neutral'));
      await tester.pumpAndSettle();
      
      // Immediately try to end session without conversation
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End Session'));
      await tester.pumpAndSettle();
      
      // Should skip summary generation and go directly back to home
      await tester.pumpAndSettle(const Duration(seconds: 3));
      
      // Should be back on home screen (no summary for empty session)
      expect(find.text('How are you feeling today?'), findsOneWidget);
    });
  });
}