// lib/blocs/voice_session/voice_session_bloc.dart
// Comprehensive rewrite - Clean, focused bloc using VoicePipelineController

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';

import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../../services/pipeline/voice_pipeline_controller.dart';
import '../../services/pipeline/voice_pipeline_dependencies.dart';
import '../../services/therapy_service.dart';
import '../../di/interfaces/i_therapy_service.dart';
import '../../utils/app_logger.dart';

/// Clean, focused bloc that delegates voice pipeline management to VoicePipelineController
/// Replaces the 2400+ line legacy bloc with proper separation of concerns
class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  // Dependencies
  final VoicePipelineController? _pipelineController;
  final ITherapyService _therapyService;
  
  // Subscriptions
  StreamSubscription<VoicePipelineSnapshot>? _pipelineSub;
  Timer? _sessionTimer;
  
  // Session tracking
  DateTime? _sessionStartTime;
  String? _sessionId;

  VoiceSessionBloc({
    VoicePipelineController? pipelineController,
    required ITherapyService therapyService,
  })  : _pipelineController = pipelineController,
        _therapyService = therapyService,
        super(VoiceSessionState.initial()) {
    _registerEventHandlers();
    _wirePipelineController();
  }

  void _registerEventHandlers() {
    on<InitializeSession>(_onInitializeSession);
    on<StartSession>(_onStartSession);
    on<EndSession>(_onEndSession);
    on<SwitchMode>(_onSwitchMode);
    on<ToggleMic>(_onToggleMic);
    on<SendMessage>(_onSendMessage);
    on<ProcessAudio>(_onProcessAudio);
    on<StopAudio>(_onStopAudio);
    on<SetMood>(_onSetMood);
    on<SetDuration>(_onSetDuration);
    on<PipelineSnapshotUpdated>(_onPipelineSnapshotUpdated);
    on<ErrorOccurred>(_onErrorOccurred);
    on<ClearError>(_onClearError);
  }

  void _wirePipelineController() {
    if (_pipelineController == null) return;
    
    _pipelineSub = _pipelineController!.snapshots.listen(
      (snapshot) => add(PipelineSnapshotUpdated(snapshot)),
      onError: (error) => add(ErrorOccurred(error.toString())),
    );
    
    // Wire the can-start-listening callback
    _pipelineController!.setCanStartListeningCallback(() {
      return state.isVoiceMode && 
             state.isGreetingComplete && 
             !state.isMicMuted;
    });
  }

  // Event handlers

  Future<void> _onInitializeSession(
    InitializeSession event,
    Emitter<VoiceSessionState> emit,
  ) async {
    logger.info('[VoiceSessionBloc] Initializing session');
    
    emit(state.copyWith(
      status: VoiceSessionStatus.initializing,
    ));
    
    try {
      await _therapyService.init();
      
      emit(state.copyWith(
        status: VoiceSessionStatus.idle,
      ));
    } catch (e) {
      logger.error('[VoiceSessionBloc] Initialization failed', error: e);
      emit(state.copyWith(
        status: VoiceSessionStatus.error,
        errorMessage: 'Failed to initialize: $e',
      ));
    }
  }

  Future<void> _onStartSession(
    StartSession event,
    Emitter<VoiceSessionState> emit,
  ) async {
    if (state.status == VoiceSessionStatus.active) {
      logger.warning('[VoiceSessionBloc] Session already active');
      return;
    }
    
    logger.info('[VoiceSessionBloc] Starting session');
    
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _sessionStartTime = DateTime.now();
    
    emit(state.copyWith(
      status: VoiceSessionStatus.active,
      isVoiceMode: true,
      sessionId: _sessionId,
    ));
    
    // Start the pipeline
    await _pipelineController?.startSession(VoiceSessionConfig(
      sessionId: _sessionId,
      targetDuration: state.selectedDuration,
    ));
    
    // Start session timer
    _startSessionTimer();
  }

  Future<void> _onEndSession(
    EndSession event,
    Emitter<VoiceSessionState> emit,
  ) async {
    logger.info('[VoiceSessionBloc] Ending session');
    
    _sessionTimer?.cancel();
    
    await _pipelineController?.teardown();
    
    emit(VoiceSessionState.initial());
  }

  Future<void> _onSwitchMode(
    SwitchMode event,
    Emitter<VoiceSessionState> emit,
  ) async {
    logger.info('[VoiceSessionBloc] Switching to ${event.isVoiceMode ? "voice" : "chat"} mode');
    
    if (event.isVoiceMode) {
      // Switching to voice mode
      emit(state.copyWith(
        isVoiceMode: true,
        status: VoiceSessionStatus.active,
      ));
      
      await _pipelineController?.requestEnableAutoMode();
    } else {
      // Switching to chat mode
      await _pipelineController?.requestDisableAutoMode();
      await _pipelineController?.requestStopAudio();
      
      emit(state.copyWith(
        isVoiceMode: false,
      ));
    }
  }

  Future<void> _onToggleMic(
    ToggleMic event,
    Emitter<VoiceSessionState> emit,
  ) async {
    final newMutedState = !state.isMicMuted;
    
    logger.info('[VoiceSessionBloc] Toggling mic: ${newMutedState ? "muted" : "unmuted"}');
    
    _pipelineController?.updateExternalMicState(newMutedState);
    
    emit(state.copyWith(
      isMicMuted: newMutedState,
    ));
    
    if (!newMutedState && state.isVoiceMode) {
      // Unmuted in voice mode - re-enable auto mode
      await _pipelineController?.requestEnableAutoMode();
    }
  }

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<VoiceSessionState> emit,
  ) async {
    logger.info('[VoiceSessionBloc] Sending message: ${event.text.substring(0, event.text.length.clamp(0, 50))}...');
    
    // Add user message
    final updatedMessages = [...state.messages, ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: event.text,
      isUser: true,
      timestamp: DateTime.now(),
    )];
    
    emit(state.copyWith(
      messages: updatedMessages,
      isProcessing: true,
    ));
    
    try {
      // Get AI response
      final history = updatedMessages
          .where((m) => m.isUser || !m.isError)
          .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
          .toList();
      
      String responseText;
      
      if (state.isVoiceMode) {
        // Voice mode - use streaming with TTS
        responseText = await _processVoiceResponse(event.text, history, emit);
      } else {
        // Chat mode - text only
        responseText = await _therapyService.processUserMessage(
          event.text,
          history: history,
        );
      }
      
      // Add AI message
      final finalMessages = [...updatedMessages, ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: responseText,
        isUser: false,
        timestamp: DateTime.now(),
      )];
      
      emit(state.copyWith(
        messages: finalMessages,
        isProcessing: false,
      ));
      
    } catch (e) {
      logger.error('[VoiceSessionBloc] Error processing message', error: e);
      
      final errorMessages = [...updatedMessages, ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Sorry, I encountered an error. Please try again.',
        isUser: false,
        isError: true,
        timestamp: DateTime.now(),
      )];
      
      emit(state.copyWith(
        messages: errorMessages,
        isProcessing: false,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<String> _processVoiceResponse(
    String userText,
    List<Map<String, String>> history,
    Emitter<VoiceSessionState> emit,
  ) async {
    String responseText = '';
    
    await _therapyService.processUserMessageWithStreamingAudio(
      userText,
      history,
      onTTSStart: (text) {
        responseText = text;
        emit(state.copyWith(
          isSpeaking: true,
        ));
      },
      onTTSPlaybackComplete: () {
        emit(state.copyWith(
          isSpeaking: false,
          isGreetingComplete: true,
        ));
      },
      onTTSError: (error) {
        emit(state.copyWith(
          isSpeaking: false,
          errorMessage: error,
        ));
      },
    );
    
    return responseText;
  }

  Future<void> _onProcessAudio(
    ProcessAudio event,
    Emitter<VoiceSessionState> emit,
  ) async {
    logger.info('[VoiceSessionBloc] Processing audio: ${event.audioPath}');
    
    emit(state.copyWith(
      isProcessing: true,
    ));
    
    try {
      // Transcribe audio
      final transcription = await _voiceService.processRecordedAudioFile(event.audioPath);
      
      if (transcription.isEmpty || transcription.startsWith('Error')) {
        emit(state.copyWith(
          isProcessing: false,
          errorMessage: 'Could not understand audio. Please try again.',
        ));
        return;
      }
      
      // Process as message
      add(SendMessage(transcription));
      
    } catch (e) {
      logger.error('[VoiceSessionBloc] Error processing audio', error: e);
      emit(state.copyWith(
        isProcessing: false,
        errorMessage: 'Error processing audio: $e',
      ));
    }
  }

  Future<void> _onStopAudio(
    StopAudio event,
    Emitter<VoiceSessionState> emit,
  ) async {
    logger.info('[VoiceSessionBloc] Stopping audio');
    
    await _pipelineController?.requestStopAudio();
    
    emit(state.copyWith(
      isSpeaking: false,
    ));
  }

  void _onSetMood(
    SetMood event,
    Emitter<VoiceSessionState> emit,
  ) {
    logger.info('[VoiceSessionBloc] Setting mood: ${event.mood}');
    
    emit(state.copyWith(
      selectedMood: event.mood,
    ));
  }

  void _onSetDuration(
    SetDuration event,
    Emitter<VoiceSessionState> emit,
  ) {
    logger.info('[VoiceSessionBloc] Setting duration: ${event.duration.inMinutes} min');
    
    emit(state.copyWith(
      selectedDuration: event.duration,
    ));
  }

  void _onPipelineSnapshotUpdated(
    PipelineSnapshotUpdated event,
    Emitter<VoiceSessionState> emit,
  ) {
    final snapshot = event.snapshot;
    
    emit(state.copyWith(
      pipelinePhase: snapshot.phase,
      isMicMuted: snapshot.micMuted,
      isAutoListeningEnabled: snapshot.autoModeEnabled,
      isSpeaking: snapshot.isTtsActive,
      isRecording: snapshot.isRecording,
      amplitude: snapshot.amplitude,
    ));
  }

  void _onErrorOccurred(
    ErrorOccurred event,
    Emitter<VoiceSessionState> emit,
  ) {
    logger.error('[VoiceSessionBloc] Error: ${event.error}');
    
    emit(state.copyWith(
      errorMessage: event.error,
      status: VoiceSessionStatus.error,
    ));
  }

  void _onClearError(
    ClearError event,
    Emitter<VoiceSessionState> emit,
  ) {
    emit(state.copyWith(
      errorMessage: null,
      status: state.status == VoiceSessionStatus.error 
          ? VoiceSessionStatus.active 
          : state.status,
    ));
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sessionStartTime != null && state.selectedDuration != null) {
        final elapsed = DateTime.now().difference(_sessionStartTime!);
        final remaining = state.selectedDuration! - elapsed;
        
        if (remaining.isNegative) {
          add(EndSession());
        }
      }
    });
  }

  VoiceService get _voiceService {
    // Get from service locator
    // This is a temporary accessor - in production use DI
    throw UnimplementedError('Access VoiceService through DependencyContainer');
  }

  @override
  Future<void> close() async {
    _sessionTimer?.cancel();
    await _pipelineSub?.cancel();
    await _pipelineController?.teardown();
    return super.close();
  }
}
