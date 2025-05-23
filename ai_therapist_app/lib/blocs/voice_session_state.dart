import 'package:equatable/equatable.dart';
import '../models/therapy_message.dart';
import '../widgets/mood_selector.dart';

class VoiceSessionState extends Equatable {
  final bool isListening;
  final bool isRecording;
  final double amplitude;
  final bool isVADActive;
  final bool isVoiceMode;
  final bool isAudioPlaying;
  final Mood? selectedMood;
  final int sessionDurationMinutes;
  final int sessionTimerSeconds;
  final bool isProcessing;
  final String? error;
  final List<TherapyMessage> messages;
  final bool showMoodSelector;
  final bool showDurationSelector;
  final bool isMicMuted;
  final bool isSpeakerMuted;

  const VoiceSessionState({
    this.isListening = false,
    this.isRecording = false,
    this.amplitude = 0.0,
    this.isVADActive = false,
    this.isVoiceMode = true,
    this.isAudioPlaying = false,
    this.selectedMood,
    this.sessionDurationMinutes = 15,
    this.sessionTimerSeconds = 0,
    this.isProcessing = false,
    this.error,
    this.messages = const [],
    this.showMoodSelector = false,
    this.showDurationSelector = false,
    this.isMicMuted = false,
    this.isSpeakerMuted = false,
  });

  VoiceSessionState copyWith({
    bool? isListening,
    bool? isRecording,
    double? amplitude,
    bool? isVADActive,
    bool? isVoiceMode,
    bool? isAudioPlaying,
    Mood? selectedMood,
    int? sessionDurationMinutes,
    int? sessionTimerSeconds,
    bool? isProcessing,
    String? error,
    List<TherapyMessage>? messages,
    bool? showMoodSelector,
    bool? showDurationSelector,
    bool? isMicMuted,
    bool? isSpeakerMuted,
  }) {
    return VoiceSessionState(
      isListening: isListening ?? this.isListening,
      isRecording: isRecording ?? this.isRecording,
      amplitude: amplitude ?? this.amplitude,
      isVADActive: isVADActive ?? this.isVADActive,
      isVoiceMode: isVoiceMode ?? this.isVoiceMode,
      isAudioPlaying: isAudioPlaying ?? this.isAudioPlaying,
      selectedMood: selectedMood ?? this.selectedMood,
      sessionDurationMinutes:
          sessionDurationMinutes ?? this.sessionDurationMinutes,
      sessionTimerSeconds: sessionTimerSeconds ?? this.sessionTimerSeconds,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      messages: messages ?? this.messages,
      showMoodSelector: showMoodSelector ?? this.showMoodSelector,
      showDurationSelector: showDurationSelector ?? this.showDurationSelector,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isSpeakerMuted: isSpeakerMuted ?? this.isSpeakerMuted,
    );
  }

  @override
  List<Object?> get props => [
        isListening,
        isRecording,
        amplitude,
        isVADActive,
        isVoiceMode,
        isAudioPlaying,
        selectedMood,
        sessionDurationMinutes,
        sessionTimerSeconds,
        isProcessing,
        error,
        messages,
        showMoodSelector,
        showDurationSelector,
        isMicMuted,
        isSpeakerMuted,
      ];
}
