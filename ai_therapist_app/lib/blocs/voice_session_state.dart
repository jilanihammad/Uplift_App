/// VoiceSessionState holds all the current state data for an active therapy session including
/// UI states (mood/duration selectors), audio states (recording, playing), and session data (messages, timer).
/// This immutable state class ensures predictable state management across the entire chat interface.

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
  final bool isTtsSpeaking;
  final bool hasInitialTtsPlayed;
  final bool welcomeMessageCompleted;
  final bool isInitializing;
  final bool isEndingSession;

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
    this.isTtsSpeaking = false,
    this.hasInitialTtsPlayed = false,
    this.welcomeMessageCompleted = false,
    this.isInitializing = true,
    this.isEndingSession = false,
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
    bool? isTtsSpeaking,
    bool? hasInitialTtsPlayed,
    bool? welcomeMessageCompleted,
    bool? isInitializing,
    bool? isEndingSession,
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
      isTtsSpeaking: isTtsSpeaking ?? this.isTtsSpeaking,
      hasInitialTtsPlayed: hasInitialTtsPlayed ?? this.hasInitialTtsPlayed,
      welcomeMessageCompleted:
          welcomeMessageCompleted ?? this.welcomeMessageCompleted,
      isInitializing: isInitializing ?? this.isInitializing,
      isEndingSession: isEndingSession ?? this.isEndingSession,
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
        isTtsSpeaking,
        hasInitialTtsPlayed,
        welcomeMessageCompleted,
        isInitializing,
        isEndingSession,
      ];

  bool get canSend => !isProcessing && !isVoiceMode;

  VoiceSessionState listening() =>
      copyWith(isListening: true, isVADActive: true);
  VoiceSessionState idle() => copyWith(
      isListening: false,
      isVADActive: false,
      isRecording: false,
      isProcessing: false);
  VoiceSessionState recording() =>
      copyWith(isRecording: true, isListening: true, isVADActive: true);
  VoiceSessionState errorOccurred(String error) =>
      copyWith(isProcessing: false, error: error);
}
