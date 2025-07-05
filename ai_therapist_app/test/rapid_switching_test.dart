// test/rapid_switching_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
import 'package:ai_therapist_app/blocs/voice_session_bloc.dart';
import 'package:ai_therapist_app/blocs/voice_session_state.dart';
import 'package:ai_therapist_app/blocs/voice_session_event.dart';
import 'package:ai_therapist_app/screens/widgets/chat_interface_view.dart';

// Mock the VoiceSessionBloc
class MockVoiceSessionBloc extends Mock implements VoiceSessionBloc {}

void main() {
  group('Rapid Mode Switching Tests', () {
    late MockVoiceSessionBloc mockBloc;
    late VoiceSessionState testState;
    
    setUp(() {
      mockBloc = MockVoiceSessionBloc();
      testState = VoiceSessionState(
        isVoiceMode: true,
        isInitializing: false,
        isProcessing: false,
        isEndingSession: false,
        showMoodSelector: false,
        showDurationSelector: false,
        messages: [],
        sessionTimerSeconds: 0,
        sessionDurationMinutes: 20,
      );
    });
    
    testWidgets('ChatInterfaceView handles rapid mode switching', (WidgetTester tester) async {
      // Setup mock to return different states
      when(mockBloc.state).thenReturn(testState);
      when(mockBloc.stream).thenAnswer((_) => Stream.fromIterable([testState]));
      
      final messageController = TextEditingController();
      final scrollController = ScrollController();
      
      // Create widget with mock bloc
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<VoiceSessionBloc>.value(
            value: mockBloc,
            child: Scaffold(
              body: ChatInterfaceView(
                onSwitchMode: () {
                  // Toggle the state for testing
                  testState = testState.copyWith(
                    isVoiceMode: !testState.isVoiceMode,
                  );
                  when(mockBloc.state).thenReturn(testState);
                },
                onSendMessage: () {},
                messageController: messageController,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Should start in voice mode
      expect(find.byType(VoiceControlsPanel), findsOneWidget);
      
      // Rapid switching simulation
      for (int i = 0; i < 10; i++) {
        // The actual switching logic would be handled by the parent widget
        // Here we just verify the widget can handle state changes rapidly
        testState = testState.copyWith(isVoiceMode: !testState.isVoiceMode);
        when(mockBloc.state).thenReturn(testState);
        
        // Trigger rebuild
        await tester.pump(const Duration(milliseconds: 50));
      }
      
      // Final pump to ensure stability
      await tester.pumpAndSettle();
      
      // Cleanup
      messageController.dispose();
      scrollController.dispose();
    });
    
    testWidgets('Widget maintains state during rapid UI changes', (WidgetTester tester) async {
      final messageController = TextEditingController();
      final scrollController = ScrollController();
      
      // Test with text mode state
      testState = testState.copyWith(isVoiceMode: false);
      when(mockBloc.state).thenReturn(testState);
      when(mockBloc.stream).thenAnswer((_) => Stream.fromIterable([testState]));
      
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<VoiceSessionBloc>.value(
            value: mockBloc,
            child: Scaffold(
              body: ChatInterfaceView(
                onSwitchMode: () {},
                onSendMessage: () {},
                messageController: messageController,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      
      // Should be in text mode
      expect(find.byType(TextField), findsOneWidget);
      
      // Enter text
      await tester.enterText(find.byType(TextField), 'Test message persistence');
      expect(messageController.text, equals('Test message persistence'));
      
      // Rapid state updates (simulating BLoC state changes)
      for (int i = 0; i < 5; i++) {
        testState = testState.copyWith(
          isProcessing: !testState.isProcessing,
        );
        when(mockBloc.state).thenReturn(testState);
        await tester.pump(const Duration(milliseconds: 30));
      }
      
      // Text should still be there
      expect(messageController.text, equals('Test message persistence'));
      
      // Cleanup
      messageController.dispose();
      scrollController.dispose();
    });
    
    testWidgets('Performance under rapid widget rebuilds', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      final messageController = TextEditingController();
      final scrollController = ScrollController();
      
      when(mockBloc.state).thenReturn(testState);
      when(mockBloc.stream).thenAnswer((_) => Stream.fromIterable([testState]));
      
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<VoiceSessionBloc>.value(
            value: mockBloc,
            child: Scaffold(
              body: ChatInterfaceView(
                onSwitchMode: () {},
                onSendMessage: () {},
                messageController: messageController,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );
      
      // Rapid rebuilds
      for (int i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      
      stopwatch.stop();
      
      // Should complete reasonably quickly
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      
      // Cleanup
      messageController.dispose();
      scrollController.dispose();
    });
    
    testWidgets('Memory stability during extended operation', (WidgetTester tester) async {
      final messageController = TextEditingController();
      final scrollController = ScrollController();
      
      when(mockBloc.state).thenReturn(testState);
      when(mockBloc.stream).thenAnswer((_) => Stream.fromIterable([testState]));
      
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<VoiceSessionBloc>.value(
            value: mockBloc,
            child: Scaffold(
              body: ChatInterfaceView(
                onSwitchMode: () {},
                onSendMessage: () {},
                messageController: messageController,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );
      
      // Simulate extended use with various state changes
      for (int cycle = 0; cycle < 20; cycle++) {
        // Alternate between different states
        testState = testState.copyWith(
          isVoiceMode: cycle % 2 == 0,
          isProcessing: cycle % 3 == 0,
        );
        when(mockBloc.state).thenReturn(testState);
        
        await tester.pump(const Duration(milliseconds: 100));
        
        // Occasionally pump and settle to allow full rebuilds
        if (cycle % 5 == 0) {
          await tester.pumpAndSettle();
        }
      }
      
      // Final verification
      expect(find.byType(ChatInterfaceView), findsOneWidget);
      
      // Cleanup
      messageController.dispose();
      scrollController.dispose();
    });
  });
}