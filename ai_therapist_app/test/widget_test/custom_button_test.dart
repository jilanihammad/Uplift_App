// test/widget_test/custom_button_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/presentation/widgets/common/custom_button.dart';

void main() {
  testWidgets('CustomButton renders correctly', (WidgetTester tester) async {
    bool buttonPressed = false;
    
    // Create button
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomButton(
            label: 'Test Button',
            onPressed: () {
              buttonPressed = true;
            },
          ),
        ),
      ),
    );
    
    // Find button
    final buttonFinder = find.text('Test Button');
    expect(buttonFinder, findsOneWidget);
    
    // Tap button
    await tester.tap(buttonFinder);
    await tester.pump();
    
    // Verify callback was called
    expect(buttonPressed, true);
  });
  
  testWidgets('CustomButton shows loading indicator when isLoading=true', (WidgetTester tester) async {
    // Create button with loading state
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomButton(
            label: 'Test Button',
            onPressed: () {},
            isLoading: true,
          ),
        ),
      ),
    );
    
    // Should not find text
    final buttonFinder = find.text('Test Button');
    expect(buttonFinder, findsNothing);
    
    // Should find loading indicator
    final loaderFinder = find.byType(CircularProgressIndicator);
    expect(loaderFinder, findsOneWidget);
  });
}