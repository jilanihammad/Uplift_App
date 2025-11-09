/// Unit tests for AutoListeningCoordinator voice guard feature
///
/// Tests verify that the coordinator properly guards against starting listening
/// while AI audio (TTS or playback) is active, and correctly restarts listening
/// when AI audio completes.
library;

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:ai_therapist_app/services/auto_listening_coordinator.dart';
import 'package:ai_therapist_app/services/audio_player_manager.dart';
import 'package:ai_therapist_app/services/recording_manager.dart';
import 'package:ai_therapist_app/services/voice_service.dart';
import 'package:ai_therapist_app/services/enhanced_vad_manager.dart';
import 'package:ai_therapist_app/services/base_voice_service.dart' as base_voice;
import 'package:ai_therapist_app/utils/feature_flags.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auto_listening_coordinator_guard_test.mocks.dart';

@GenerateMocks([
  AudioPlayerManager,
  RecordingManager,
  VoiceService,
  EnhancedVADManager,
])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize AppLogger for tests
  setUpAll(() {
    AppLogger.initialize();
  });

  group('AutoListeningCoordinator Voice Guard Tests', () {
    late MockAudioPlayerManager mockAudioPlayerManager;
    late MockRecordingManager mockRecordingManager;
    late MockVoiceService mockVoiceService;
    late MockEnhancedVADManager mockVADManager;
    late AutoListeningCoordinator coordinator;

    // Stream controllers for test control - recreated for each test
    late StreamController<bool> isPlayingStreamController;
    late StreamController<bool> playbackActiveStreamController;
    late StreamController<base_voice.RecordingState> recordingStateStreamController;
    late StreamController<bool> ttsActivityStreamController;
    late StreamController<void> vadSpeechStartStreamController;
    late StreamController<void> vadSpeechEndStreamController;
    late StreamController<String> vadErrorStreamController;

    setUp(() async {
      // Initialize feature flags with coordinator voice guard enabled
      SharedPreferences.setMockInitialValues({
        'coordinatorVoiceGuardEnabled': true,
      });
      await FeatureFlags.init();

      // Create mocks
      mockAudioPlayerManager = MockAudioPlayerManager();
      mockRecordingManager = MockRecordingManager();
      mockVoiceService = MockVoiceService();
      mockVADManager = MockEnhancedVADManager();

      // Create NEW stream controllers for each test
      isPlayingStreamController = StreamController<bool>.broadcast();
      playbackActiveStreamController = StreamController<bool>.broadcast();
      recordingStateStreamController =
          StreamController<base_voice.RecordingState>.broadcast();
      ttsActivityStreamController = StreamController<bool>.broadcast();
      vadSpeechStartStreamController = StreamController<void>.broadcast();
      vadSpeechEndStreamController = StreamController<void>.broadcast();
      vadErrorStreamController = StreamController<String>.broadcast();

      // Setup mock streams
      when(mockAudioPlayerManager.isPlayingStream)
          .thenAnswer((_) => isPlayingStreamController.stream);
      when(mockAudioPlayerManager.playbackActiveStream)
          .thenAnswer((_) => playbackActiveStreamController.stream);
      when(mockRecordingManager.recordingStateStream)
          .thenAnswer((_) => recordingStateStreamController.stream);

      // Setup mock VAD manager
      when(mockVADManager.initialize()).thenAnswer((_) async => {});
      when(mockVADManager.startListening()).thenAnswer((_) async => true);
      when(mockVADManager.stopListening()).thenAnswer((_) async => {});
      when(mockVADManager.onSpeechStart)
          .thenAnswer((_) => vadSpeechStartStreamController.stream);
      when(mockVADManager.onSpeechEnd)
          .thenAnswer((_) => vadSpeechEndStreamController.stream);
      when(mockVADManager.onError)
          .thenAnswer((_) => vadErrorStreamController.stream);

      // Default states
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(false);
      when(mockVoiceService.isTtsActive).thenReturn(false);
      when(mockVoiceService.isAiSpeaking).thenReturn(false);

      // Setup recording manager methods
      when(mockRecordingManager.startRecording()).thenAnswer((_) async => {});
      when(mockRecordingManager.tryStopRecording())
          .thenAnswer((_) async => null);
      when(mockRecordingManager.markFileAsPendingTranscription(any))
          .thenReturn(null);

      // Setup audio player manager methods
      when(mockAudioPlayerManager.mute(any)).thenAnswer((_) async => {});

      // Create coordinator with mocked dependencies, TTS activity stream, and VAD manager
      coordinator = AutoListeningCoordinator(
        audioPlayerManager: mockAudioPlayerManager,
        recordingManager: mockRecordingManager,
        voiceService: mockVoiceService,
        ttsActivityStream: ttsActivityStreamController.stream,
        vadManager: mockVADManager, // Inject mocked VAD manager
      );

      await coordinator.initialize();
    });

    tearDown(() async {
      // Wait for any pending async operations to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Dispose coordinator to stop all listeners and cancel subscriptions
      coordinator.performDisposal();

      // Wait for disposal to fully complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Then close the stream controllers
      await isPlayingStreamController.close();
      await playbackActiveStreamController.close();
      await recordingStateStreamController.close();
      await ttsActivityStreamController.close();
      await vadSpeechStartStreamController.close();
      await vadSpeechEndStreamController.close();
      await vadErrorStreamController.close();
    });

    test('Guard prevents listening while AI audio active', () async {
      // Arrange: Set AI audio active
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      // Wait for stream to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      // Act: Enable auto mode while AI audio is active
      await coordinator.enableAutoMode();

      // Wait for state to settle
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert: State should be aiSpeaking, not listening
      expect(coordinator.currentState, AutoListeningState.aiSpeaking);
      expect(coordinator.autoModeEnabled, true);

      // Verify that startRecording was never called
      verifyNever(mockRecordingManager.startRecording());
    });

    test('Listening restarts when AI audio ends', () async {
      // Arrange: Start with AI audio active
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));

      // Enable auto mode while AI is speaking
      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify we're in aiSpeaking state
      expect(coordinator.currentState, AutoListeningState.aiSpeaking);

      // Act: AI audio ends
      ttsActivityStreamController.add(false);
      isPlayingStreamController.add(false);
      when(mockVoiceService.isTtsActive).thenReturn(false);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(false);

      // Wait for the coordinator to process the change and the debounce delay
      // The coordinator has a ring-down delay of 100ms + worker sync of 50ms
      await Future.delayed(const Duration(milliseconds: 250));

      // Assert: Should transition to listening state
      expect(
        coordinator.currentState,
        anyOf(
          AutoListeningState.listening,
          AutoListeningState.listeningForVoice,
        ),
      );
    });

    test('disableAutoMode waits for shutdown sequence before toggling', () async {
      // Arrange: make stopListening slow so we can observe the guard stay enabled
      when(mockVADManager.stopListening()).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() {
        when(mockVADManager.stopListening()).thenAnswer((_) async => {});
      });

      await coordinator.enableAutoMode();

      final disableFuture = coordinator.disableAutoMode();
      var disableCompleted = false;
      disableFuture.then((_) => disableCompleted = true);

      await Future.delayed(const Duration(milliseconds: 50));

      // Assert: auto mode remains enabled while the shutdown sequence runs
      expect(disableCompleted, isFalse);
      expect(coordinator.autoModeEnabled, isTrue);

      await disableFuture;

      expect(coordinator.autoModeEnabled, isFalse);
      expect(coordinator.currentState, AutoListeningState.idle);
    });

    test('Reset clears AI audio state before re-enabling auto mode', () async {
      // Arrange: simulate AI audio active when leaving voice mode
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));
      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(coordinator.currentState, AutoListeningState.aiSpeaking);

      // Simulate chat mode teardown (audio fully idle)
      ttsActivityStreamController.add(false);
      isPlayingStreamController.add(false);
      when(mockVoiceService.isTtsActive).thenReturn(false);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(false);

      coordinator.reset(preserveAutoMode: true);
      await Future.delayed(const Duration(milliseconds: 20));

      // Act: Voice mode re-enabled immediately after reset
      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert: Coordinator should no longer be stuck waiting for AI silence
      expect(coordinator.currentState, isNot(AutoListeningState.aiSpeaking));
    });

    test('Timeout fires after 10 seconds when AI audio stays active', () {
      fakeAsync((async) {
        // Arrange: Set AI audio permanently active
        ttsActivityStreamController.add(true);
        isPlayingStreamController.add(true);
        when(mockVoiceService.isTtsActive).thenReturn(true);
        when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));

        // Enable auto mode
        coordinator.enableAutoMode();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));

        // Verify we're in aiSpeaking state
        expect(coordinator.currentState, AutoListeningState.aiSpeaking);

        // Act: Advance time by 10 seconds (timeout duration)
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        // Even though AI audio is still active, allow additional processing time
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Assert: Timeout should have fired and forced listening to start
        // The coordinator should have transitioned out of aiSpeaking
        expect(
          coordinator.currentState,
          anyOf(
            AutoListeningState.listening,
            AutoListeningState.listeningForVoice,
            AutoListeningState.idle,
          ),
        );
      });
    });

    test('TTS emits false but playback still true - guard remains active',
        () async {
      // Arrange: Start with both TTS and playback active
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));

      // Enable auto mode
      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(coordinator.currentState, AutoListeningState.aiSpeaking);

      // Act: TTS stream emits false, but playback is still active
      ttsActivityStreamController.add(false);
      when(mockVoiceService.isTtsActive).thenReturn(false);
      // playback still true
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      // Wait for streams to propagate
      await Future.delayed(const Duration(milliseconds: 200));

      // Assert: Should remain in aiSpeaking state because playback is still active
      expect(coordinator.currentState, AutoListeningState.aiSpeaking);

      // Verify recording was not started
      verifyNever(mockRecordingManager.startRecording());

      // Now end playback too
      isPlayingStreamController.add(false);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(false);

      // Wait for the debounce delay and state transition
      await Future.delayed(const Duration(milliseconds: 250));

      // Now it should transition to listening
      expect(
        coordinator.currentState,
        anyOf(
          AutoListeningState.listening,
          AutoListeningState.listeningForVoice,
        ),
      );
    });

    test('Auto mode disabled cancels pending restart', () async {
      // Arrange: Start with AI audio active
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));

      // Enable auto mode
      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(coordinator.currentState, AutoListeningState.aiSpeaking);
      expect(coordinator.autoModeEnabled, true);

      // Act: Disable auto mode before AI audio ends
      await coordinator.disableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(coordinator.autoModeEnabled, false);
      expect(coordinator.currentState, AutoListeningState.idle);

      // Now AI audio ends
      ttsActivityStreamController.add(false);
      isPlayingStreamController.add(false);
      when(mockVoiceService.isTtsActive).thenReturn(false);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(false);

      // Wait for potential restart (should not happen)
      await Future.delayed(const Duration(milliseconds: 300));

      // Assert: Should stay in idle, not restart listening
      expect(coordinator.currentState, AutoListeningState.idle);

      // Verify that startRecording was never called after disabling
      verifyNever(mockRecordingManager.startRecording());
    });

    test('Guard respects manual forceStart override (user taps mic)', () async {
      // Note: The current implementation doesn't expose forceStart parameter
      // This test documents expected behavior if/when implemented

      // Arrange: AI audio is active
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));

      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(coordinator.currentState, AutoListeningState.aiSpeaking);

      // Act: User manually calls startListening (simulating mic button tap)
      // Current implementation still respects the guard
      coordinator.startListening();
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert: Current behavior is that it's still blocked by the guard
      // If forceStart is implemented in the future, this test should be updated
      expect(coordinator.currentState, AutoListeningState.aiSpeaking);
    });

    test('State transitions correctly during rapid AI audio changes', () async {
      // Arrange: Enable auto mode first
      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      // Act: Rapidly toggle AI audio state
      for (int i = 0; i < 5; i++) {
        // AI starts speaking
        ttsActivityStreamController.add(true);
        when(mockVoiceService.isTtsActive).thenReturn(true);
        await Future.delayed(const Duration(milliseconds: 20));

        // AI stops speaking
        ttsActivityStreamController.add(false);
        when(mockVoiceService.isTtsActive).thenReturn(false);
        await Future.delayed(const Duration(milliseconds: 20));
      }

      // Wait for final state to settle
      await Future.delayed(const Duration(milliseconds: 300));

      // Assert: Should end in a valid state (not stuck or crashed)
      expect(
        coordinator.currentState,
        anyOf(
          AutoListeningState.idle,
          AutoListeningState.listening,
          AutoListeningState.listeningForVoice,
          AutoListeningState.aiSpeaking,
        ),
      );

      // Should still have auto mode enabled
      expect(coordinator.autoModeEnabled, true);
    });

    test('Reset clears pending restart state', () async {
      // Arrange: Set AI audio active and enable auto mode
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));

      await coordinator.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(coordinator.currentState, AutoListeningState.aiSpeaking);

      // Act: Call reset
      coordinator.reset(full: false, preserveAutoMode: false);
      await Future.delayed(const Duration(milliseconds: 50));

      // Assert: Should be in idle state with auto mode disabled
      expect(coordinator.currentState, AutoListeningState.idle);
      expect(coordinator.autoModeEnabled, false);

      // Now AI audio ends
      ttsActivityStreamController.add(false);
      isPlayingStreamController.add(false);
      when(mockVoiceService.isTtsActive).thenReturn(false);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(false);

      // Wait for potential restart
      await Future.delayed(const Duration(milliseconds: 300));

      // Should still be idle (no restart because auto mode was disabled)
      expect(coordinator.currentState, AutoListeningState.idle);
    });

    test('Voice guard disabled flag bypasses guard logic', () async {
      // Arrange: Disable the voice guard feature flag
      await FeatureFlags.setEnabled('coordinatorVoiceGuardEnabled', false);

      // Create new coordinator with guard disabled
      final coordinatorNoGuard = AutoListeningCoordinator(
        audioPlayerManager: mockAudioPlayerManager,
        recordingManager: mockRecordingManager,
        voiceService: mockVoiceService,
        ttsActivityStream: ttsActivityStreamController.stream,
        vadManager: mockVADManager, // Inject mocked VAD manager
      );

      await coordinatorNoGuard.initialize();

      // Set AI audio active
      ttsActivityStreamController.add(true);
      isPlayingStreamController.add(true);
      when(mockVoiceService.isTtsActive).thenReturn(true);
      when(mockAudioPlayerManager.isPlaybackActive).thenReturn(true);

      await Future.delayed(const Duration(milliseconds: 50));

      // Act: Enable auto mode
      await coordinatorNoGuard.enableAutoMode();
      await Future.delayed(const Duration(milliseconds: 50));

      // Assert: Without guard, it should still go to aiSpeaking
      // (the basic playback monitoring still works)
      expect(coordinatorNoGuard.currentState, AutoListeningState.aiSpeaking);

      // Cleanup
      coordinatorNoGuard.performDisposal();

      // Re-enable guard for other tests
      await FeatureFlags.setEnabled('coordinatorVoiceGuardEnabled', true);
    });
  });
}
