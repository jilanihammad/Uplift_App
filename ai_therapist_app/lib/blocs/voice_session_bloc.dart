/// VoiceSessionBloc manages the entire therapy session state including voice/text mode switching,
/// audio recording, TTS playback, message processing, and session lifecycle (mood selection, timer, etc).
/// This is the central brain that coordinates all real-time interactions during a therapy session.

import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';
// Removed service_locator import - now using dependency injection
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import 'package:flutter/foundation.dart';
import '../models/therapy_message.dart';
import '../services/recording_manager.dart';
import 'package:uuid/uuid.dart';

// Placeholder imports - replace with actual paths or remove if not used
// import '../services/memory_service.dart';
// import '../services/therapy_graph_service.dart';
// import '../services/notification_service.dart';
// import '../services/conversation_buffer_memory.dart';

// Assuming these service types are still needed,
// you might need to define them or import them correctly.
// For now, let's use dynamic to resolve analyzer errors,
// but this should be replaced with actual types.
typedef MemoryService = dynamic;
typedef TherapyGraphService = dynamic;
typedef NotificationService = dynamic;
typedef ConversationBufferMemory = dynamic;

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
    // on<ProcessAudioFile>(_onProcessAudioFile); // Commented out: ProcessAudioFile event/handler not found
    // on<SendTextMessage>(_onSendTextMessage); // Commented out: SendTextMessage event/handler not found
    // on<ProcessWelcomeMessage>(_onProcessWelcomeMessage); // Commented out: ProcessWelcomeMessage event/handler not found
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

  // Phase 6B-3: Helper for legacy-only methods until fully migrated
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
      await voiceService.stopAudio();
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');

      voiceService.resetTTSState();

      await voiceService.autoListeningCoordinator.disableAutoMode();

      try {
        await voiceService.stopRecording();
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

        await voiceService.stopAudio();
        debugPrint('[VoiceSessionBloc] Audio stopped successfully');

        voiceService.resetTTSState();

        await Future.delayed(const Duration(milliseconds: 200));

        // ALWAYS enable auto mode when switching to voice mode
        // Keep autoModeEnabled=true throughout voice sessions
        await voiceService.enableAutoMode();
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
          path = await voiceService.stopRecording();
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
          await voiceService.processRecordedAudioFile(event.audioPath);
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
    voiceService.setSpeakerMuted(event.isMuted);
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
      await voiceService.stopAudio();
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');

      voiceService.resetTTSState();

      // Add buffer delay to prevent Maya from detecting her own voice
      debugPrint('[VoiceSessionBloc] Adding 125ms buffer before enabling auto-listening...');
      await Future.delayed(const Duration(milliseconds: 125));

      await voiceService.enableAutoMode();
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
      await voiceService.stopAudio();
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
      await voiceService.playAudio(event.audioPath);
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
      _safeVoiceService.updateTTSSpeakingState(true); // Stops auto-listening
      
      // Use SimpleTTSService directly for welcome messages
      final ttsService = DependencyContainer().ttsService;
      await ttsService.speak(event.welcomeMessage);
      
      debugPrint('[VoiceSessionBloc] Welcome TTS streaming completed');
      
      // Use VoiceService TTS state management to trigger auto-listening
      _safeVoiceService.updateTTSSpeakingState(false); // Starts auto-listening
      
      // Fire the welcome message completed event if needed
      add(const WelcomeMessageCompleted());
      
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error playing welcome message: $e');
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
