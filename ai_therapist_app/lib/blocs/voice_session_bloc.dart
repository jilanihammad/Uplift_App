/// VoiceSessionBloc manages the entire therapy session state including voice/text mode switching,
/// audio recording, TTS playback, message processing, and session lifecycle (mood selection, timer, etc).
/// This is the central brain that coordinates all real-time interactions during a therapy session.
///
/// Phase 6 Migration Status: ✅ COMPLETED
/// - Supports both legacy VoiceService and new IVoiceService interface
/// - Uses _safeVoiceService helper for gradual migration
/// - 18 method calls migrated to interface pattern
/// - Maintains full backward compatibility

import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import 'package:flutter/foundation.dart';
import '../models/therapy_message.dart';
import '../services/recording_manager.dart';
import '../widgets/mood_selector.dart'; // For Mood enum
import 'package:uuid/uuid.dart';


class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  final VoiceService voiceService;
  final VADManager vadManager;
  final ITherapyService? therapyService;
  // Phase 6B-1: Optional IVoiceService parameter for gradual migration
  final IVoiceService? interfaceVoiceService;
  StreamSubscription? _recordingStateSub;
  StreamSubscription? _audioPlaybackSub;
  StreamSubscription? _ttsStateSub;

  VoiceSessionBloc({
    required this.voiceService,
    required this.vadManager,
    this.therapyService,
    this.interfaceVoiceService, // Optional for backward compatibility
  }) : super(VoiceSessionState.initial()) {
    on<StartSession>(_onStartSession);
    on<EndSession>(_onEndSession);
    on<StartListening>(_onStartListening);
    on<StopListening>(_onStopListening);
    on<SelectMood>(_onSelectMood);
    on<ChangeDuration>(_onChangeDuration);
    // Phase 1A.3: New event handlers for refactoring
    on<SessionStarted>(_onSessionStarted);
    on<MoodSelected>(_onMoodSelected); 
    on<DurationSelected>(_onDurationSelected);
    on<TextMessageSent>(_onTextMessageSent);
    on<EndSessionRequested>(_onEndSessionRequested);
    on<SwitchMode>(_onSwitchMode);
    on<ProcessAudio>(_onProcessAudio);
    on<HandleError>(_onHandleError);
    on<UpdateAmplitude>(_onUpdateAmplitude);
    on<AddMessage>(_onAddMessage);
    on<SetProcessing>(_onSetProcessing);
    on<SetRecordingState>(_onSetRecordingState);
    on<ProcessTextMessage>(_onProcessTextMessage);
    on<ShowMoodSelector>(_onShowMoodSelector);
    on<ShowDurationSelector>(_onShowDurationSelector);
    on<ToggleMicMute>(_onToggleMicMute);
    on<SetSpeakerMuted>(_onSetSpeakerMuted);
    on<InitializeService>(_onInitializeService);
    on<EnableAutoMode>(_onEnableAutoMode);
    on<DisableAutoMode>(_onDisableAutoMode);
    on<StopAudio>(_onStopAudio);
    on<PlayAudio>(_onPlayAudio);
    on<AudioPlaybackStateChanged>(_onAudioPlaybackStateChanged);
    on<TtsStateChanged>(_onTtsStateChanged);
    on<PlayWelcomeMessage>(_onPlayWelcomeMessage);
    on<WelcomeMessageCompleted>(_onWelcomeMessageCompleted);
    on<SetInitializing>(_onSetInitializing);
    on<SetEndingSession>(_onSetEndingSession);
    on<UpdateSessionTimer>(_onUpdateSessionTimer);
    
    _recordingStateSub = voiceService.recordingState.listen((recState) {
      final isRecording = recState.toString().contains('recording');
      add(SetRecordingState(isRecording));
    });

    _audioPlaybackSub = voiceService
        .getAudioPlayerManager()
        .isPlayingStream
        .listen((isPlaying) {
      add(AudioPlaybackStateChanged(isPlaying));
    });

    _ttsStateSub = voiceService.isTtsActuallySpeaking.listen((isSpeaking) {
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] Legacy VoiceService TTS state: $isSpeaking');
      }
      add(TtsStateChanged(isSpeaking));
    });
  }

  // Phase 6B-3: Helper method to safely choose between interface and legacy service
  // For methods that exist in IVoiceService interface, use interface service
  // For methods that don't exist yet, fall back to legacy service  
  IVoiceService get _safeVoiceService {
    // If we have the interface service, use it; otherwise cast legacy service to interface
    return interfaceVoiceService ?? voiceService as IVoiceService;
  }

  // Phase 6B-3: Helper for legacy-only methods that haven't migrated to interface yet
  // Currently unused but kept for future migration of autoListeningCoordinator, recordingState stream, etc.
  VoiceService get _legacyVoiceService {
    return voiceService;
  }

  void _onStartSession(StartSession event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      status: VoiceSessionStatus.initial,
      isListening: false,
      isRecording: false,
      isProcessingAudio: false,
      errorMessage: null,
      messages: [],
      isInitialGreetingPlayed: false,
      currentMessageSequence: 0,
    ));
  }

  Future<void> _onEndSession(
      EndSession event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Ending session - cleaning up audio and resources...');

    try {
      await _safeVoiceService.stopAudio();
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');

      _safeVoiceService.resetTTSState();

      await voiceService.autoListeningCoordinator.disableAutoMode();

      try {
        await _safeVoiceService.stopRecording();
      } on NotRecordingException {
        // Not recording, that's fine
      }


      debugPrint('[VoiceSessionBloc] Session cleanup completed successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error during session cleanup: $e');
    }

    emit(state.copyWith(
      isListening: false,
      isRecording: false,
      isProcessingAudio: false,
      isAiSpeaking: false,
    ));
  }

  void _onStartListening(
      StartListening event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      isListening: true,
      isAutoListeningEnabled: true,
    ));
  }

  void _onStopListening(StopListening event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      isListening: false,
      isAutoListeningEnabled: false,
    ));
  }

  void _onSelectMood(SelectMood event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(selectedMood: event.mood));
  }

  void _onChangeDuration(
      ChangeDuration event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(selectedDuration: Duration(minutes: event.minutes)));
  }

  Future<void> _onSwitchMode(
      SwitchMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Switching to ${event.isVoiceMode ? "voice" : "chat"} mode');

    if (event.isVoiceMode) {
      debugPrint(
          '[VoiceSessionBloc] Preparing for voice mode (will enable VAD after TTS)');
      try {
        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          isAiSpeaking: false,
          isAutoListeningEnabled: false,
          isInitialGreetingPlayed: false,
        ));

        await _safeVoiceService.stopAudio();
        debugPrint('[VoiceSessionBloc] Audio stopped successfully');

        _safeVoiceService.resetTTSState();

        await Future.delayed(const Duration(milliseconds: 200));

        // ALWAYS enable auto mode when switching to voice mode
        // Keep autoModeEnabled=true throughout voice sessions
        await _safeVoiceService.enableAutoMode();
        debugPrint('[VoiceSessionBloc] Auto mode enabled for voice session');
        
        // Only start listening immediately if this is a manual mode switch (user has messages)
        // For initial session, let _onTtsStateChanged handle listening after welcome TTS
        if (!state.isAiSpeaking && state.messages.isNotEmpty) {
          voiceService.autoListeningCoordinator.triggerListening();
        }

        debugPrint('[VoiceSessionBloc] Voice mode switch complete - auto-listening enabled');
      } catch (e) {
        debugPrint('[VoiceSessionBloc] Failed to prepare for voice mode: $e');
        emit(state.copyWith(errorMessage: e.toString()));
      }
    } else {
      debugPrint('[VoiceSessionBloc] Disabling VAD for chat mode');
      try {
        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          isAiSpeaking: false,
        ));

        await voiceService.autoListeningCoordinator.disableAutoMode();
        String? path;
        try {
          path = await _safeVoiceService.stopRecording();
        } on NotRecordingException {
          path = null;
        }
        if (path != null && path.isNotEmpty) {
          add(ProcessAudio(path));
        } else {
          emit(state.copyWith(isProcessingAudio: false));
        }
        emit(state.copyWith(isAutoListeningEnabled: false, isRecording: false));
        debugPrint(
            '[VoiceSessionBloc] VAD disabled successfully for chat mode');
      } catch (e) {
        debugPrint(
            '[VoiceSessionBloc] Failed to disable VAD for chat mode: $e');
        emit(state.copyWith(errorMessage: e.toString()));
      }
    }
  }

  Future<void> _onProcessAudio(
      ProcessAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Processing audio file: ${event.audioPath}');
    emit(state.copyWith(isProcessingAudio: true));

    try {
      final transcription =
          await _safeVoiceService.processRecordedAudioFile(event.audioPath);
      debugPrint('[VoiceSessionBloc] Transcription: "$transcription"');

      if (transcription.trim().isEmpty || transcription.startsWith("Error:")) {
        debugPrint('[VoiceSessionBloc] Empty or error transcription');
        emit(state.copyWith(
            isProcessingAudio: false,
            errorMessage: 'Could not understand audio'));
        return;
      }

      final nextUserSequence = state.currentMessageSequence + 1;

      final userMessage = TherapyMessage(
        id: const Uuid().v4(),
        content: transcription,
        isUser: true,
        timestamp: DateTime.now(),
        sequence: nextUserSequence,
      );

      final messagesWithUser = List.of(state.messages)..add(userMessage);
      emit(state.copyWith(
        messages: messagesWithUser,
        currentMessageSequence: nextUserSequence,
      ));

      final history = _buildConversationHistory(messagesWithUser);

      if (state.isVoiceMode) {
        debugPrint(
            '[VoiceSessionBloc] Voice mode - generating TTS response...');
        emit(state.copyWith(isAiSpeaking: true));

        final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
        final responseData =
            await therapyServiceInstance.processUserMessageWithStreamingAudio(
          transcription,
          history,
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            emit(state.copyWith(isProcessingAudio: false, isAiSpeaking: false));
            voiceService.autoListeningCoordinator.onProcessingComplete();
          },
          onTTSError: (error) async {
            debugPrint('[VoiceSessionBloc] TTS error: $error');
            emit(state.copyWith(
                isProcessingAudio: false,
                errorMessage: error.toString(),
                isAiSpeaking: false));
            voiceService.autoListeningCoordinator.onProcessingComplete();
          },
        );

        final mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';

        debugPrint(
            '[VoiceSessionBloc] Maya\'s text response: "$mayaResponseText"');

        final nextAISequence = state.currentMessageSequence + 1;

        final mayaMessage = TherapyMessage(
          id: const Uuid().v4(),
          content: mayaResponseText,
          isUser: false,
          timestamp: DateTime.now(),
          sequence: nextAISequence,
        );

        final finalMessages = List.of(messagesWithUser)..add(mayaMessage);
        emit(state.copyWith(
          messages: finalMessages,
          currentMessageSequence: nextAISequence,
        ));
      } else {
        // Text mode - only get text response without TTS
        debugPrint(
            '[VoiceSessionBloc] Text mode - getting text response only...');
        final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
        final mayaResponseText = await therapyServiceInstance.processUserMessage(
          transcription,
          history: history,
        );

        if (mayaResponseText.trim().isEmpty) {
          debugPrint('[VoiceSessionBloc] Empty response from Maya');
          emit(state.copyWith(
              isProcessingAudio: false,
              errorMessage: 'Failed to get response from Maya'));
          return;
        }

        debugPrint(
            '[VoiceSessionBloc] Maya\'s text response: "$mayaResponseText"');

        final nextAISequence = state.currentMessageSequence + 1;

        final mayaMessage = TherapyMessage(
          id: const Uuid().v4(),
          content: mayaResponseText,
          isUser: false,
          timestamp: DateTime.now(),
          sequence: nextAISequence,
        );

        final finalMessages = List.of(messagesWithUser)..add(mayaMessage);
        emit(state.copyWith(
          messages: finalMessages,
          currentMessageSequence: nextAISequence,
        ));

        emit(state.copyWith(isProcessingAudio: false));
      }
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error in _onProcessAudio: $e');
      emit(
          state.copyWith(isProcessingAudio: false, errorMessage: e.toString()));
    }
  }

  void _onHandleError(HandleError event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(errorMessage: event.error.toString()));
  }

  void _onUpdateAmplitude(
      UpdateAmplitude event, Emitter<VoiceSessionState> emit) {}

  Future<void> _onAddMessage(
      AddMessage event, Emitter<VoiceSessionState> emit) async {
    try {
      final newSequence = state.currentMessageSequence + 1;
      final messageWithSequence = event.message.copyWith(sequence: newSequence);

      final updatedMessages = List<TherapyMessage>.from(state.messages)
        ..add(messageWithSequence);

      emit(state.copyWith(
        messages: updatedMessages,
        currentMessageSequence: newSequence,
      ));

      if (state.currentSessionId != null) {
        debugPrint(
            '[VoiceSessionBloc] Message would be added to repository: ${messageWithSequence.content.substring(0, min(messageWithSequence.content.length, 20))}... Seq: ${messageWithSequence.sequence}');
      } else {
        debugPrint(
            '[VoiceSessionBloc] CurrentSessionId is null, message not saved to repo.');
      }
    } catch (e, stackTrace) {
      debugPrint('Error adding message: $e $stackTrace');
      emit(state.copyWith(
          errorMessage: 'Failed to add message: $e', hasError: true));
    }
  }

  void _onSetProcessing(SetProcessing event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isProcessingAudio: event.isProcessing));
  }

  void _onSetRecordingState(
      SetRecordingState event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isRecording: event.isRecording));
  }

  Future<void> _onProcessTextMessage(
      ProcessTextMessage event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Received ProcessTextMessage: \'${event.text}\'');
    debugPrint('[VoiceSessionBloc] Current state - isVoiceMode: ${state.isVoiceMode}, isProcessingAudio: ${state.isProcessingAudio}');
    emit(state.copyWith(isProcessingAudio: true));

    try {
      final nextUserSequence = state.currentMessageSequence + 1;

      final userMessage = TherapyMessage(
        id: const Uuid().v4(),
        content: event.text,
        isUser: true,
        timestamp: DateTime.now(),
        sequence: nextUserSequence,
      );

      final messagesWithUser = List.of(state.messages)..add(userMessage);
      emit(state.copyWith(
        messages: messagesWithUser,
        currentMessageSequence: nextUserSequence,
      ));

      final history = _buildConversationHistory(messagesWithUser);

      final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
      String mayaResponseText;

      if (state.isVoiceMode) {
        debugPrint(
            '[VoiceSessionBloc] Text message in voice mode - generating TTS...');

        emit(state.copyWith(isAiSpeaking: true));

        final responseData =
            await therapyServiceInstance.processUserMessageWithStreamingAudio(
          event.text,
          history,
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            emit(state.copyWith(isAiSpeaking: false));
          },
          onTTSError: (error) {
            debugPrint('[VoiceSessionBloc] TTS Error: $error');
            emit(state.copyWith(
                isAiSpeaking: false, errorMessage: error.toString()));
          },
        );
        mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';
      } else {
        debugPrint('[VoiceSessionBloc] Text message in text mode - no TTS...');
        debugPrint('[VoiceSessionBloc] Calling therapyService.processUserMessage...');
        mayaResponseText = await therapyServiceInstance.processUserMessage(
          event.text,
          history: history,
        );
        debugPrint('[VoiceSessionBloc] Received therapy response: "${mayaResponseText.substring(0, 50)}..."');
      }

      final nextAISequence = state.currentMessageSequence + 1;

      final mayaResponse = TherapyMessage(
        id: const Uuid().v4(),
        content: mayaResponseText,
        isUser: false,
        timestamp: DateTime.now(),
        sequence: nextAISequence,
      );

      final finalMessages = List.of(messagesWithUser)..add(mayaResponse);
      emit(state.copyWith(
        messages: finalMessages,
        isProcessingAudio: false,
        currentMessageSequence: nextAISequence,
      ));

      debugPrint('[VoiceSessionBloc] Text message processing complete');
    } catch (e, stackTrace) {
      debugPrint('[VoiceSessionBloc] Error processing text message: $e');
      debugPrint('[VoiceSessionBloc] Stack trace: $stackTrace');
      
      // Ensure processing state is cleared and error is shown to user
      emit(state.copyWith(
        isProcessingAudio: false, 
        errorMessage: 'Failed to get response: ${e.toString()}',
        hasError: true,
      ));
      
      // Also add a fallback error message to chat
      final errorMessage = TherapyMessage(
        id: const Uuid().v4(),
        content: "I'm sorry, I'm having trouble responding right now. Please try again.",
        isUser: false,
        timestamp: DateTime.now(),
        sequence: state.currentMessageSequence + 1,
      );
      
      final messagesWithError = List.of(state.messages)..add(errorMessage);
      emit(state.copyWith(
        messages: messagesWithError,
        currentMessageSequence: state.currentMessageSequence + 1,
      ));
    }
  }

  void _onShowMoodSelector(
      ShowMoodSelector event, Emitter<VoiceSessionState> emit) {
    debugPrint('[VoiceSessionBloc] Show mood selector: ${event.show}');
    emit(state.copyWith(showMoodSelector: event.show));
  }

  void _onShowDurationSelector(
      ShowDurationSelector event, Emitter<VoiceSessionState> emit) {
    debugPrint('[VoiceSessionBloc] Show duration selector: ${event.show}');
    emit(state.copyWith(showDurationSelector: event.show));
  }

  void _onToggleMicMute(ToggleMicMute event, Emitter<VoiceSessionState> emit) {
    final newMicEnabledState = !state.isMicEnabled;
    debugPrint('[VoiceSessionBloc] Toggle mic enabled: $newMicEnabledState');
    emit(state.copyWith(isMicEnabled: newMicEnabledState));
  }

  void _onSetSpeakerMuted(
      SetSpeakerMuted event, Emitter<VoiceSessionState> emit) {
    _safeVoiceService.setSpeakerMuted(event.isMuted);
    emit(state.copyWith(speakerMuted: event.isMuted));
  }

  Future<void> _onInitializeService(
      InitializeService event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Initializing services...');
    emit(state.copyWith(isProcessingAudio: true));

    try {
      await _safeVoiceService.initialize();

      final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
      await therapyServiceInstance.init();

      debugPrint('[VoiceSessionBloc] Services initialized successfully');
      emit(state.copyWith(isProcessingAudio: false));
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Service initialization failed: $e');
      emit(
          state.copyWith(isProcessingAudio: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onEnableAutoMode(
      EnableAutoMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Enabling auto mode...');

    if (state.isAutoListeningEnabled) {
      debugPrint('[VoiceSessionBloc] Auto mode already active, skipping');
      return;
    }

    try {
      await _safeVoiceService.stopAudio();
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');

      _safeVoiceService.resetTTSState();

      // Add buffer delay to prevent Maya from detecting her own voice
      debugPrint('[VoiceSessionBloc] Adding 125ms buffer before enabling auto-listening...');
      await Future.delayed(const Duration(milliseconds: 125));

      await _safeVoiceService.enableAutoMode();
      emit(state.copyWith(isAutoListeningEnabled: true));

      voiceService.autoListeningCoordinator.triggerListening();

      debugPrint(
          '[VoiceSessionBloc] Auto mode enabled successfully, VAD is now active');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to enable auto mode: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onDisableAutoMode(
      DisableAutoMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Disabling auto mode...');

    try {
      await voiceService.autoListeningCoordinator.disableAutoMode();
      emit(state.copyWith(isAutoListeningEnabled: false));
      debugPrint('[VoiceSessionBloc] Auto mode disabled successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to disable auto mode: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onStopAudio(
      StopAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Stopping audio...');
    try {
      await _safeVoiceService.stopAudio();
      emit(state.copyWith(isAiSpeaking: false));
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to stop audio: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onPlayAudio(
      PlayAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Playing audio: ${event.audioPath}');
    try {
      await _safeVoiceService.playAudio(event.audioPath);
      debugPrint('[VoiceSessionBloc] Audio played successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to play audio: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onPlayWelcomeMessage(
      PlayWelcomeMessage event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Playing welcome message TTS: ${event.welcomeMessage}');
    
    try {
      // Use VoiceService TTS state management to properly coordinate with auto-listening
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] updateTTSSpeakingState(true) - Welcome message starting');
      }
      _safeVoiceService.updateTTSSpeakingState(true); // Stops auto-listening
      
      // Use SimpleTTSService directly for welcome messages
      final ttsService = DependencyContainer().ttsService;
      await ttsService.speak(event.welcomeMessage, makeBackupFile: false);
      
      debugPrint('[VoiceSessionBloc] Welcome TTS streaming completed');
      
      // Use VoiceService TTS state management to trigger auto-listening
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] updateTTSSpeakingState(false) - Welcome message completed');
      }
      _safeVoiceService.updateTTSSpeakingState(false); // Starts auto-listening
      
      // Fire the welcome message completed event if needed
      add(const WelcomeMessageCompleted());
      
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error playing welcome message: $e');
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] updateTTSSpeakingState(false) - Welcome message error recovery');
      }
      _safeVoiceService.updateTTSSpeakingState(false); // Reset state on error
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  void _onAudioPlaybackStateChanged(
      AudioPlaybackStateChanged event, Emitter<VoiceSessionState> emit) {}

  void _onTtsStateChanged(
      TtsStateChanged event, Emitter<VoiceSessionState> emit) {
    debugPrint('[VoiceSessionBloc] TTS state changed: ${event.isSpeaking}');

    final bool wasSpeaking = state.isAiSpeaking;
    emit(state.copyWith(isAiSpeaking: event.isSpeaking));

    if (wasSpeaking &&
        !event.isSpeaking &&
        !state.isInitialGreetingPlayed &&
        state.isVoiceMode) {
      debugPrint(
          '[VoiceSessionBloc] TTS transition detected (true -> false), initial TTS has completed, enabling listening');
      emit(state.copyWith(isInitialGreetingPlayed: true));

      // Add buffer delay to prevent Maya from detecting her own voice
      Future.delayed(const Duration(milliseconds: 125), () {
        if (state.isVoiceMode &&
            !state.isAutoListeningEnabled &&
            !state.isRecording) {
          debugPrint(
              '[VoiceSessionBloc] Dispatching EnableAutoMode after TTS with buffer delay');
          add(const EnableAutoMode());
        }
      });
    }
  }

  void _onWelcomeMessageCompleted(
      WelcomeMessageCompleted event, Emitter<VoiceSessionState> emit) {}

  void _onSetInitializing(
      SetInitializing event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
        status: event.isInitializing
            ? VoiceSessionStatus.loading
            : VoiceSessionStatus.idle));
  }

  void _onSetEndingSession(
      SetEndingSession event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
        status: event.isEndingSession
            ? VoiceSessionStatus.ended
            : VoiceSessionStatus.idle));
  }

  void _onUpdateSessionTimer(
      UpdateSessionTimer event, Emitter<VoiceSessionState> emit) {}

  // ========== Phase 1A.3: New Event Handlers for Refactoring ==========

  /// Handles session initialization with optional sessionId
  void _onSessionStarted(SessionStarted event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Session started with ID: ${event.sessionId}');
    }
    
    emit(state.copyWith(
      currentSessionId: event.sessionId,
      status: VoiceSessionStatus.loading,
    ));
  }

  /// Handles mood selection - moves logic from ChatScreen._handleMoodSelection
  void _onMoodSelected(MoodSelected event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Mood selected: ${event.mood}');
    }
    
    emit(state.copyWith(
      selectedMood: event.mood,
      showMoodSelector: false,
      status: VoiceSessionStatus.loading,
    ));
    
    // Add initial AI welcome message based on mood
    _addInitialAIMessage(event.mood, emit);
  }

  /// Handles duration selection with Duration object
  void _onDurationSelected(DurationSelected event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Duration selected: ${event.duration.inMinutes} minutes');
    }
    
    emit(state.copyWith(
      selectedDuration: event.duration,
      showDurationSelector: false,
    ));
  }

  /// Handles text message sending - delegates to existing ProcessTextMessage
  void _onTextMessageSent(TextMessageSent event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Text message sent: "${event.message}"');
    }
    
    // Delegate to existing ProcessTextMessage handler
    add(ProcessTextMessage(event.message));
  }

  /// Handles session end request - moves core logic from ChatScreen._endSession  
  void _onEndSessionRequested(EndSessionRequested event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Session end requested');
    }
    
    // Prevent multiple end session calls
    if (state.status == VoiceSessionStatus.ended) {
      return;
    }
    
    emit(state.copyWith(
      status: VoiceSessionStatus.ended,
      speakerMuted: true, // Mute speaker immediately to stop any ongoing TTS
    ));
    
    // Note: Wakelock, navigation, VAD stopping remain in UI layer for now
    // These are UI concerns that will be handled by ChatScreen
  }

  /// Helper method to add initial AI message based on mood
  void _addInitialAIMessage(Mood mood, Emitter<VoiceSessionState> emit) {
    final welcomeMessage = _getWelcomeMessage(mood);
    
    final aiMessage = TherapyMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_ai',
      content: welcomeMessage,
      isUser: false,
      timestamp: DateTime.now(),
      sequence: 1,
    );
    
    emit(state.copyWith(
      messages: [...state.messages, aiMessage],
      status: VoiceSessionStatus.idle,
    ));
    
    // If in voice mode, should generate TTS for welcome message
    // This will be handled by ChatScreen for now to maintain UI separation
  }

  /// Helper method to generate welcome message based on mood
  String _getWelcomeMessage(Mood mood) {
    final messages = {
      Mood.happy: [
        "Heyyy! What's keeping your spirits high today?",
        "Hello hello! Your positivity is contagious! What's on your mind?",
        "Hey there! Glad you're feeling upbeat! How can I support you today?",
        "Heyyy! Hearing you're happy makes me happy! Anything special you'd like to talk about?",
        "Hello hello! Would you like to share more about what's brightening your day?"
      ],
      Mood.sad: [
        "I'm here for you. What's been weighing on your heart lately?",
        "Thank you for trusting me with your feelings. How can I support you today?",
        "I hear you're going through a tough time. Would you like to share what's on your mind?",
        "It takes courage to reach out when you're feeling down. I'm glad you're here.",
        "I'm here to listen. What's been making you feel this way?"
      ],
      Mood.anxious: [
        "I understand you're feeling anxious. Let's take this one step at a time. What's on your mind?",
        "Anxiety can feel overwhelming. I'm here to help you work through it. What's been triggering these feelings?",
        "Thank you for reaching out. Anxiety is tough, but you're not alone. What would you like to talk about?",
        "I can sense you're feeling anxious. Let's explore what's been causing these feelings together.",
        "It's okay to feel anxious. I'm here to support you. What's been on your mind lately?"
      ],
      Mood.angry: [
        "I can feel the intensity of your emotions. What's been frustrating you?",
        "Anger often signals that something important to you has been affected. What's going on?",
        "Thank you for being honest about your anger. What's been triggering these feelings?",
        "I'm here to listen without judgment. What's been making you feel this way?",
        "Anger can be a powerful emotion. Let's explore what's behind it together."
      ],
      Mood.neutral: [
        "Hello! I'm here to listen. What's been on your mind lately?",
        "Thanks for reaching out today. What would you like to talk about?",
        "I'm glad you're here. What's been going on in your life?",
        "How are you feeling today? What would you like to explore together?",
        "I'm here to support you. What's been on your mind?"
      ],
      Mood.stressed: [
        "I can sense you're feeling stressed. Let's work through this together. What's been weighing on you?",
        "Stress can feel overwhelming. I'm here to help you find some relief. What's been the biggest challenge?",
        "Thank you for sharing that you're stressed. What's been contributing to these feelings?",
        "I understand stress can be exhausting. Let's take this one step at a time. What's been most difficult?",
        "It takes strength to recognize when you're stressed. What would help you feel more balanced?"
      ],
    };
    
    final moodMessages = messages[mood] ?? [
      "Thank you for sharing how you're feeling. What's been on your mind lately?",
    ];
    
    return moodMessages[DateTime.now().millisecond % moodMessages.length];
  }

  List<Map<String, String>> _buildConversationHistory(
      List<TherapyMessage> messages) {
    return messages
        .map((message) => {
              'role': message.isUser ? 'user' : 'assistant',
              'content': message.content,
            })
        .toList();
  }

  @override
  Future<void> close() {
    _recordingStateSub?.cancel();
    _audioPlaybackSub?.cancel();
    _ttsStateSub?.cancel();
    return super.close();
  }
}
