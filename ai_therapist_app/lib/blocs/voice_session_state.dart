import 'package:equatable/equatable.dart';
import '../models/therapy_message.dart';
import '../widgets/mood_selector.dart';

class VoiceSessionState extends Equatable {
  final bool isListening;
  final bool isRecording;
  final double amplitude;
  final bool isVADActive;
  final bool isVoiceMode;
  final Mood? selectedMood;
  final int sessionDurationMinutes;
  final int sessionTimerSeconds;
  final bool isProcessing;
  final String? error;
  final List<TherapyMessage> messages;

  const VoiceSessionState({
    this.isListening = false,
    this.isRecording = false,
    this.amplitude = 0.0,
    this.isVADActive = false,
    this.isVoiceMode = true,
    this.selectedMood,
    this.sessionDurationMinutes = 15,
    this.sessionTimerSeconds = 0,
    this.isProcessing = false,
    this.error,
    this.messages = const [],
  });

  VoiceSessionState copyWith({
    bool? isListening,
    bool? isRecording,
    double? amplitude,
    bool? isVADActive,
    bool? isVoiceMode,
    Mood? selectedMood,
    int? sessionDurationMinutes,
    int? sessionTimerSeconds,
    bool? isProcessing,
    String? error,
    List<TherapyMessage>? messages,
  }) {
    return VoiceSessionState(
      isListening: isListening ?? this.isListening,
      isRecording: isRecording ?? this.isRecording,
      amplitude: amplitude ?? this.amplitude,
      isVADActive: isVADActive ?? this.isVADActive,
      isVoiceMode: isVoiceMode ?? this.isVoiceMode,
      selectedMood: selectedMood ?? this.selectedMood,
      sessionDurationMinutes:
          sessionDurationMinutes ?? this.sessionDurationMinutes,
      sessionTimerSeconds: sessionTimerSeconds ?? this.sessionTimerSeconds,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      messages: messages ?? this.messages,
    );
  }

  @override
  List<Object?> get props => [
        isListening,
        isRecording,
        amplitude,
        isVADActive,
        isVoiceMode,
        selectedMood,
        sessionDurationMinutes,
        sessionTimerSeconds,
        isProcessing,
        error,
        messages,
      ];
}
