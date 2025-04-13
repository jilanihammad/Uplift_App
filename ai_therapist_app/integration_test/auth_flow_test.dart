// integration_test/auth_flow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ai_therapist_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Authentication Flow Tests', () {
    testWidgets('Sign up, login, and logout flow', (WidgetTester tester) async {
      // Start app
      app.main();
      await tester.pumpAndSettle();
      
      // Should start on login screen
      expect(find.text('Welcome Back'), findsOneWidget);
      
      // Tap sign up link
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      
      // Fill sign up form
      await tester.enterText(find.byType(TextField).at(0), 'Test User');
      await tester.enterText(find.byType(TextField).at(1), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'password123');
      await tester.enterText(find.byType(TextField).at(3), 'password123');
      
      // Submit form
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Should be on welcome/onboarding screen
      expect(find.text('Welcome to AI Therapist'), findsOneWidget);
      
      // Skip onboarding
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      
      // Should be on home screen
      expect(find.text('How are you feeling today?'), findsOneWidget);
      
      // Go to profile
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      
      // Logout
      await tester.dragUntilVisible(
        find.text('Log Out'),
        find.byType(SingleChildScrollView),
        const Offset(0, 100),
      );
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      
      // Should be back on login screen
      expect(find.text('Welcome Back'), findsOneWidget);
    });
  });
}