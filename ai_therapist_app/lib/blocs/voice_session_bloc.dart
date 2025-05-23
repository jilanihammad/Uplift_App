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

  void _onSwitchMode(SwitchMode event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isVoiceMode: event.isVoiceMode));
  }

  Future<void> _onProcessAudio(
      ProcessAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Received ProcessAudio for: ${event.audioPath}');
    emit(state.copyWith(isProcessing: true));

    try {
      // 1. Transcribe the audio file
      debugPrint('[VoiceSessionBloc] Transcribing audio...');
      final transcription =
          await voiceService.processRecordedAudioFile(event.audioPath);

      if (transcription.startsWith("Error:")) {
        debugPrint('[VoiceSessionBloc] Transcription error: $transcription');
        emit(state.copyWith(isProcessing: false, error: transcription));
        return;
      }

      if (transcription.trim().isEmpty) {
        debugPrint('[VoiceSessionBloc] Empty transcription, ignoring');
        emit(state.copyWith(isProcessing: false));
        return;
      }

      debugPrint('[VoiceSessionBloc] Valid transcription: "$transcription"');

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

      // 4. Get Maya's text response first (without TTS)
      debugPrint('[VoiceSessionBloc] Getting Maya\'s text response...');
      final therapyService = serviceLocator<TherapyService>();
      final mayaResponseText = await therapyService.processUserMessage(
        transcription,
        history: [], // Use named parameter
      );

      if (mayaResponseText.trim().isEmpty) {
        debugPrint('[VoiceSessionBloc] Empty response from Maya');
        emit(state.copyWith(
            isProcessing: false, error: 'Failed to get response from Maya'));
        return;
      }

      debugPrint(
          '[VoiceSessionBloc] Maya\'s text response: "$mayaResponseText"');

      // 5. Create Maya's message and add to chat immediately
      final mayaMessage = TherapyMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_maya',
        content: mayaResponseText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      // 6. Add Maya's message to state immediately (chat bubble appears now)
      final finalMessages = List.of(messagesWithUser)..add(mayaMessage);
      emit(state.copyWith(messages: finalMessages));

      // 7. Generate and play TTS in the background (if in voice mode)
      if (state.isVoiceMode) {
        debugPrint('[VoiceSessionBloc] Generating TTS for Maya\'s response...');

        // Generate and play TTS with callbacks
        final audioResponse =
            await therapyService.processUserMessageWithStreamingAudio(
          transcription,
          [], // Empty history for now
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            emit(state.copyWith(isProcessing: false));
          },
          onTTSError: (error) async {
            debugPrint('[VoiceSessionBloc] TTS error: $error');
            emit(state.copyWith(isProcessing: false, error: error));
          },
        );

        if (audioResponse['text'] == null) {
          debugPrint('[VoiceSessionBloc] TTS generation failed');
          emit(state.copyWith(
              isProcessing: false, error: 'TTS generation failed'));
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

      // 3. Get Maya's response from TherapyService
      final therapyService = serviceLocator<TherapyService>();
      String mayaResponseText;

      if (state.isVoiceMode) {
        // In voice mode: get response with TTS audio
        debugPrint(
            '[VoiceSessionBloc] Text message in voice mode - generating TTS...');
        final responseData =
            await therapyService.processUserMessageWithStreamingAudio(
          event.text,
          [], // Empty history for now, could be enhanced later
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
          },
          onTTSError: (error) {
            debugPrint('[VoiceSessionBloc] TTS Error: $error');
          },
        );
        mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';
      } else {
        // In text mode: get response without audio
        debugPrint('[VoiceSessionBloc] Text message in text mode - no TTS...');
        mayaResponseText = await therapyService.processUserMessage(
          event.text,
          history: [], // Use named parameter
        );
      }

      // 4. Create Maya's response message
      final mayaResponse = TherapyMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_maya',
        content: mayaResponseText,
        isUser: false,
        timestamp: DateTime.now(),
      );

      // 5. Add Maya's response to state
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
}
