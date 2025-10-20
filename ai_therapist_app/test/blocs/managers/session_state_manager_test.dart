/// Unit tests for SessionStateManager
/// 
/// These tests verify the pure state management logic of SessionStateManager.
/// No mocking required as this manager has no external dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/blocs/managers/session_state_manager.dart';
import 'package:ai_therapist_app/blocs/voice_session_state.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';
import 'package:ai_therapist_app/models/therapist_style.dart';

void main() {
  group('SessionStateManager', () {
    late SessionStateManager manager;

    setUp(() {
      manager = SessionStateManager();
    });

    group('Initialization', () {
      test('initializes with default state', () {
        expect(manager.state.status, VoiceSessionStatus.initial);
        expect(manager.state.messages, isEmpty);
        expect(manager.state.selectedMood, isNull);
        expect(manager.state.selectedDuration, isNull);
        expect(manager.state.currentSessionId, isNull);
        expect(manager.state.isVoiceMode, true);
        expect(manager.state.currentMessageSequence, 0);
      });

      test('initializeSession with parameters sets state correctly', () {
        final state = manager.initializeSession(
          sessionId: 'test-123',
          systemPrompt: 'Test prompt',
          therapyStyleName: 'empathetic',
        );

        expect(state.currentSessionId, 'test-123');
        expect(state.currentSystemPrompt, 'Test prompt');
        expect(state.activeTherapyStyleName, 'empathetic');
        expect(state.status, VoiceSessionStatus.initial);
      });
    });

    group('Session Lifecycle', () {
      test('startNewSession resets to clean state', () {
        // First set some state
        manager.selectMood(Mood.happy);
        manager.setError('Test error');
        
        // Then start new session
        final state = manager.startNewSession();

        expect(state.status, VoiceSessionStatus.initial);
        expect(state.isListening, false);
        expect(state.isRecording, false);
        expect(state.isProcessingAudio, false);
        expect(state.errorMessage, isNull);
        expect(state.messages, isEmpty);
        expect(state.isInitialGreetingPlayed, false);
        expect(state.currentMessageSequence, 0);
        // Note: mood is not reset by startNewSession
        expect(state.selectedMood, Mood.happy);
      });

      test('setSessionStarted sets ID and loading status', () {
        final state = manager.setSessionStarted('session-456');

        expect(state.currentSessionId, 'session-456');
        expect(state.status, VoiceSessionStatus.loading);
      });

      test('setSessionEnding sets ended status and mutes speaker', () {
        final state = manager.setSessionEnding();

        expect(state.status, VoiceSessionStatus.ended);
        expect(state.speakerMuted, true);
      });

      test('setSessionEnding prevents multiple calls', () {
        // First call
        manager.setSessionEnding();
        expect(manager.state.status, VoiceSessionStatus.ended);
        
        // Try to change something else
        manager.setError('Should not change');
        
        // Second call should not change anything
        final state = manager.setSessionEnding();
        expect(state.status, VoiceSessionStatus.ended);
        // Error should still be there since ending was already set
        expect(state.errorMessage, 'Should not change');
      });
    });

    group('Mood and Duration Selection', () {
      test('selectMood sets mood and hides selector', () {
        final state = manager.selectMood(Mood.anxious);

        expect(state.selectedMood, Mood.anxious);
        expect(state.showMoodSelector, false);
        expect(state.status, VoiceSessionStatus.loading);
      });

      test('selectDuration sets duration and hides selector', () {
        final state = manager.selectDuration(const Duration(minutes: 30));

        expect(state.selectedDuration, const Duration(minutes: 30));
        expect(state.showDurationSelector, false);
      });

      test('mood selector visibility control', () {
        var state = manager.setMoodSelectorVisibility(true);
        expect(state.showMoodSelector, true);

        state = manager.setMoodSelectorVisibility(false);
        expect(state.showMoodSelector, false);
      });

      test('duration selector visibility control', () {
        var state = manager.setDurationSelectorVisibility(true);
        expect(state.showDurationSelector, true);

        state = manager.setDurationSelectorVisibility(false);
        expect(state.showDurationSelector, false);
      });
    });

    group('State Updates', () {
      test('updateStatus changes session status', () {
        final state = manager.updateStatus(VoiceSessionStatus.processing);
        expect(state.status, VoiceSessionStatus.processing);
      });

      test('setInitializing sets correct status', () {
        var state = manager.setInitializing(true);
        expect(state.status, VoiceSessionStatus.loading);

        state = manager.setInitializing(false);
        expect(state.status, VoiceSessionStatus.idle);
      });

      test('setInitialGreetingPlayed marks greeting as played', () {
        final state = manager.setInitialGreetingPlayed();
        expect(state.isInitialGreetingPlayed, true);
      });

      test('setTherapistStyle updates style', () {
        final style = TherapistStyle.getById('cbt');
        final state = manager.setTherapistStyle(style);
        expect(state.therapistStyle, style);
      });
    });

    group('Error Handling', () {
      test('setError sets error message and flag', () {
        final state = manager.setError('Network error occurred');

        expect(state.errorMessage, 'Network error occurred');
        expect(state.hasError, true);
      });

      test('clearError removes error state', () {
        // First set an error
        manager.setError('Test error');
        
        // Then clear it
        final state = manager.clearError();

        expect(state.errorMessage, isNull);
        expect(state.hasError, false);
      });
    });

    group('Utility Methods', () {
      test('isSessionReady checks mood and duration', () {
        expect(manager.isSessionReady(), false);

        manager.selectMood(Mood.neutral);
        expect(manager.isSessionReady(), false);

        manager.selectDuration(const Duration(minutes: 20));
        expect(manager.isSessionReady(), true);
      });

      test('isSessionEndingOrEnded checks status', () {
        expect(manager.isSessionEndingOrEnded(), false);

        manager.setSessionEnding();
        expect(manager.isSessionEndingOrEnded(), true);
      });

      test('getSessionConfigSummary generates summary', () {
        expect(manager.getSessionConfigSummary(), 
               'Mood: not selected, Duration: 0min, Style: default');

        manager.selectMood(Mood.stressed);
        manager.selectDuration(const Duration(minutes: 45));
        manager.updateState(manager.state.copyWith(
          activeTherapyStyleName: 'mindfulness'
        ));

        expect(manager.getSessionConfigSummary(), 
               'Mood: stressed, Duration: 45min, Style: mindfulness');
      });
    });

    group('State Coordination', () {
      test('updateState allows external state updates', () {
        final newState = VoiceSessionState.initial().copyWith(
          selectedMood: Mood.happy,
          isProcessingAudio: true,
        );

        manager.updateState(newState);
        
        expect(manager.state.selectedMood, Mood.happy);
        expect(manager.state.isProcessingAudio, true);
      });
    });
  });
}
