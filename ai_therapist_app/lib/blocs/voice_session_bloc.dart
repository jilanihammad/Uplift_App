import 'package:flutter_bloc/flutter_bloc.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';

class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  final VoiceService voiceService;
  final VADManager vadManager;

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

  void _onProcessAudio(ProcessAudio event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isProcessing: true));
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
}
