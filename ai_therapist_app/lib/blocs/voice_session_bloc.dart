import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';
import '../services/therapy_service.dart';
import '../di/service_locator.dart';
import 'package:flutter/foundation.dart';
import '../models/therapy_message.dart';
import '../services/recording_manager.dart';

class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  final VoiceService voiceService;
  final VADManager vadManager;
  StreamSubscription? _recordingStateSub;

  VoiceSessionBloc({required this.voiceService, required this.vadManager})
      : super(const VoiceSessionState()) {
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
    // Phase 3: New event handlers
    on<InitializeService>(_onInitializeService);
    on<EnableAutoMode>(_onEnableAutoMode);
    on<DisableAutoMode>(_onDisableAutoMode);
    on<StopAudio>(_onStopAudio);
    on<PlayAudio>(_onPlayAudio);
    // Subscribe to recording state
    _recordingStateSub = voiceService.recordingState.listen((recState) {
      final isRecording = recState.toString().contains('recording');
      add(SetRecordingState(isRecording));
    });
  }

  void _onStartSession(StartSession event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      isListening: false,
      isRecording: false,
      isVADActive: false,
      isProcessing: false,
      error: null,
      sessionTimerSeconds: 0,
      messages: [],
    ));
  }

  void _onEndSession(EndSession event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      isListening: false,
      isRecording: false,
      isVADActive: false,
      isProcessing: false,
    ));
  }

  void _onStartListening(
      StartListening event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isListening: true, isVADActive: true));
  }

  void _onStopListening(StopListening event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isListening: false, isVADActive: false));
  }

  void _onSelectMood(SelectMood event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(selectedMood: event.mood));
  }

  void _onChangeDuration(
      ChangeDuration event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(sessionDurationMinutes: event.minutes));
  }

  Future<void> _onSwitchMode(
      SwitchMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Switching to ${event.isVoiceMode ? "voice" : "chat"} mode');

    if (event.isVoiceMode) {
      // Switching TO voice mode: stop any audio, reset TTS state, then enable VAD
      debugPrint('[VoiceSessionBloc] Enabling VAD for voice mode');
      try {
        // 1. Update state to show we're stopping audio
        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          isAudioPlaying: false, // Bloc manages audio state
        ));

        // 2. Stop any ongoing audio
        await voiceService.stopAudio();
        print('[VoiceSessionBloc] Audio stopped successfully');

        // 3. Reset TTS state
        voiceService.resetTTSState();

        // 4. Add a small delay to ensure audio state is fully updated
        await Future.delayed(const Duration(milliseconds: 200));

        // 5. Enable auto mode with Bloc-managed audio state (false = not playing)
        await voiceService.enableAutoModeWithAudioState(state.isAudioPlaying);
        emit(state.copyWith(isVADActive: true));
        debugPrint(
            '[VoiceSessionBloc] VAD enabled successfully for voice mode');
      } catch (e) {
        debugPrint(
            '[VoiceSessionBloc] Failed to enable VAD for voice mode: $e');
        emit(state.copyWith(error: e.toString()));
      }
    } else {
      // Switching TO chat mode: disable VAD and auto mode
      debugPrint('[VoiceSessionBloc] Disabling VAD for chat mode');
      try {
        // 1. Update state first
        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          isAudioPlaying: false, // Ensure audio state is false
        ));

        // 2. Disable auto mode and stop recording
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
          emit(state.copyWith(isProcessing: false));
        }
        emit(state.copyWith(isVADActive: false, isRecording: false));
        debugPrint(
            '[VoiceSessionBloc] VAD disabled successfully for chat mode');
      } catch (e) {
        debugPrint(
            '[VoiceSessionBloc] Failed to disable VAD for chat mode: $e');
        emit(state.copyWith(error: e.toString()));
      }
    }
  }

  Future<void> _onProcessAudio(
      ProcessAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Processing audio file: ${event.audioPath}');
    emit(state.copyWith(isProcessing: true));

    try {
      // 1. Transcribe the audio
      final transcription =
          await voiceService.processRecordedAudioFile(event.audioPath);
      debugPrint('[VoiceSessionBloc] Transcription: "$transcription"');

      if (transcription.trim().isEmpty || transcription.startsWith("Error:")) {
        debugPrint('[VoiceSessionBloc] Empty or error transcription');
        emit(state.copyWith(
            isProcessing: false, error: 'Could not understand audio'));
        return;
      }

      // 2. Create user message
      final userMessage = TherapyMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_user',
        content: transcription,
        isUser: true,
        timestamp: DateTime.now(),
      );

      // 3. Add user message to state
      final messagesWithUser = List.of(state.messages)..add(userMessage);
      emit(state.copyWith(messages: messagesWithUser));

      // 4. Build conversation history for therapy service
      final history = _buildConversationHistory(messagesWithUser);

      // 5. Get Maya's text response first (without TTS)
      debugPrint('[VoiceSessionBloc] Getting Maya\'s text response...');
      final therapyService = serviceLocator<TherapyService>();
      final mayaResponseText = await therapyService.processUserMessage(
        transcription,
        history: history, // Pass the proper conversation history
      );

      if (mayaResponseText.trim().isEmpty) {
        debugPrint('[VoiceSessionBloc] Empty response from Maya');
        emit(state.copyWith(
            isProcessing: false, error: 'Failed to get response from Maya'));
        return;
      }

      debugPrint(
          '[VoiceSessionBloc] Maya\'s text response: "$mayaResponseText"');

      // 6. Create Maya's message and add to chat immediately
      final mayaMessage = TherapyMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_maya',
        content: mayaResponseText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      // 7. Add Maya's message to state immediately (chat bubble appears now)
      final finalMessages = List.of(messagesWithUser)..add(mayaMessage);
      emit(state.copyWith(messages: finalMessages));

      // 8. Generate and play TTS in the background (if in voice mode)
      if (state.isVoiceMode) {
        debugPrint('[VoiceSessionBloc] Generating TTS for Maya\'s response...');

        // Update state to show Maya is speaking
        emit(state.copyWith(isAudioPlaying: true));

        // Generate and play TTS with callbacks
        final audioResponse =
            await therapyService.processUserMessageWithStreamingAudio(
          transcription,
          history, // Pass the proper conversation history
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            // Update state to show Maya stopped speaking
            emit(state.copyWith(isProcessing: false, isAudioPlaying: false));
          },
          onTTSError: (error) async {
            debugPrint('[VoiceSessionBloc] TTS error: $error');
            // Update state to show Maya stopped speaking (due to error)
            emit(state.copyWith(
                isProcessing: false, error: error, isAudioPlaying: false));
          },
        );

        if (audioResponse['text'] == null) {
          debugPrint('[VoiceSessionBloc] TTS generation failed');
          emit(state.copyWith(
              isProcessing: false,
              error: 'TTS generation failed',
              isAudioPlaying: false));
        }
        // Note: Processing state will be cleared by onTTSPlaybackComplete callback
      } else {
        // If not in voice mode, just clear processing state
        emit(state.copyWith(isProcessing: false));
      }
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error in _onProcessAudio: $e');
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  void _onHandleError(HandleError event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(error: event.error));
  }

  void _onUpdateAmplitude(
      UpdateAmplitude event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(amplitude: event.amplitude));
  }

  void _onAddMessage(AddMessage event, Emitter<VoiceSessionState> emit) {
    final updatedMessages = List.of(state.messages)..add(event.message);
    emit(state.copyWith(messages: updatedMessages));
  }

  void _onSetProcessing(SetProcessing event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isProcessing: event.isProcessing));
  }

  void _onSetRecordingState(
      SetRecordingState event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isRecording: event.isRecording));
  }

  Future<void> _onProcessTextMessage(
      ProcessTextMessage event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Received ProcessTextMessage: \'${event.text}\'');
    emit(state.copyWith(isProcessing: true));

    try {
      // 1. Create user message
      final userMessage = TherapyMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_user',
        content: event.text,
        isUser: true,
        timestamp: DateTime.now(),
      );

      // 2. Add user message to state
      final messagesWithUser = List.of(state.messages)..add(userMessage);
      emit(state.copyWith(messages: messagesWithUser));

      // 3. Build conversation history for therapy service
      final history = _buildConversationHistory(messagesWithUser);

      // 4. Get Maya's response from TherapyService
      final therapyService = serviceLocator<TherapyService>();
      String mayaResponseText;

      if (state.isVoiceMode) {
        // In voice mode: get response with TTS audio
        debugPrint(
            '[VoiceSessionBloc] Text message in voice mode - generating TTS...');

        // Update state to show Maya is speaking
        emit(state.copyWith(isAudioPlaying: true));

        final responseData =
            await therapyService.processUserMessageWithStreamingAudio(
          event.text,
          history, // Pass the proper conversation history
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            // Update state to show Maya stopped speaking
            emit(state.copyWith(isAudioPlaying: false));
          },
          onTTSError: (error) {
            debugPrint('[VoiceSessionBloc] TTS Error: $error');
            // Update state to show Maya stopped speaking (due to error)
            emit(state.copyWith(isAudioPlaying: false));
          },
        );
        mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';
      } else {
        // In text mode: get response without audio
        debugPrint('[VoiceSessionBloc] Text message in text mode - no TTS...');
        mayaResponseText = await therapyService.processUserMessage(
          event.text,
          history: history, // Pass the proper conversation history
        );
      }

      // 5. Create Maya's response message
      final mayaResponse = TherapyMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_maya',
        content: mayaResponseText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      // 6. Add Maya's response to state
      final finalMessages = List.of(messagesWithUser)..add(mayaResponse);
      emit(state.copyWith(messages: finalMessages, isProcessing: false));

      debugPrint('[VoiceSessionBloc] Text message processing complete');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error processing text message: $e');
      emit(state.copyWith(isProcessing: false, error: e.toString()));
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
    final newMutedState = !state.isMicMuted;
    debugPrint('[VoiceSessionBloc] Toggle mic mute: $newMutedState');
    emit(state.copyWith(isMicMuted: newMutedState));
  }

  Future<void> _onInitializeService(
      InitializeService event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Initializing services...');
    emit(state.copyWith(isProcessing: true));

    try {
      // Initialize voice service
      await voiceService.initialize();

      // Initialize therapy service
      final therapyService = serviceLocator<TherapyService>();
      await therapyService.init();

      debugPrint('[VoiceSessionBloc] Services initialized successfully');
      emit(state.copyWith(isProcessing: false));
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Service initialization failed: $e');
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  Future<void> _onEnableAutoMode(
      EnableAutoMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Enabling auto mode...');

    try {
      // Stop any ongoing audio
      await voiceService.stopAudio();
      print('[VoiceSessionBloc] Audio stopped successfully');

      // Reset TTS state
      voiceService.resetTTSState();

      // Add a small delay to ensure audio state is fully updated
      await Future.delayed(const Duration(milliseconds: 200));

      // Enable auto mode (starts in idle instead of aiSpeaking)
      await voiceService.enableAutoMode();
      debugPrint('[VoiceSessionBloc] Auto mode enabled successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to enable auto mode: $e');
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onDisableAutoMode(
      DisableAutoMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Disabling auto mode...');

    try {
      await voiceService.autoListeningCoordinator.disableAutoMode();
      debugPrint('[VoiceSessionBloc] Auto mode disabled successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to disable auto mode: $e');
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onStopAudio(
      StopAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Stopping audio...');

    try {
      await voiceService.stopAudio();
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to stop audio: $e');
      emit(state.copyWith(error: e.toString()));
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
      emit(state.copyWith(error: e.toString()));
    }
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
}
