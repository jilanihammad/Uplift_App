/// VoiceSessionState holds all the current state data for an active therapy session including
/// UI states (mood/duration selectors), audio states (recording, playing), and session data (messages, timer).
/// This immutable state class ensures predictable state management across the entire chat interface.

import 'package:equatable/equatable.dart';
import '../models/therapy_message.dart';
import '../models/therapist_style.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';

enum VoiceSessionStatus {
  initial,
  loading,
  listening, // Actively listening for user speech via mic
  processing, // User speech captured, STT in progress, or AI response generation
  speaking, // AI is speaking (TTS playback)
  error,
  idle, // Waiting for user to speak or AI to respond, mic might be open (VAD) or closed
  ended,
  selectingDuration,
  selectingMood,
  awaitingMood, // Waiting for mood selection before starting audio pipeline
  voiceModeActive,
  textModeActive,
}

/// Unified TTS status enum - single source of truth for TTS state across all components
enum TtsStatus {
  idle,      // No TTS activity
  preparing, // Getting AI response, preparing for TTS (optional UI feedback)
  streaming, // TTS WebSocket is streaming content  
  playing,   // Audio is actively playing through speakers
  cancelled, // TTS operation was cancelled
}

class VoiceSessionState extends Equatable {
  final VoiceSessionStatus status;
  final List<TherapyMessage> messages;
  final String? errorMessage;
  final String? currentSessionId;
  final bool isListening; // General listening state (mic active)
  final bool isRecording; // Specifically if audio is being captured to a file
  final bool
      isProcessingAudio; // True if STT or other audio processing is happening
  final bool isAiSpeaking; // True if TTS is active (legacy - use ttsStatus instead)
  final TtsStatus ttsStatus; // Unified TTS state - single source of truth
  final bool ttsAudible; // True if TTS can be heard (not muted)
  final bool hasError;
  final String? transcribedText;
  final bool showMicButton;
  final bool showSendButton;
  final Duration? selectedDuration;
  final bool showDurationSelector;
  final bool showMoodSelector;
  final Mood? selectedMood;
  final String? currentSystemPrompt;
  final bool isMicEnabled; // User permission for mic
  final bool isVoiceMode; // True if in voice interaction mode
  final bool
      isInitialGreetingPlayed; // Tracks if the initial greeting TTS has been played
  final String? activeTherapyStyleName;
  final TherapistStyle? therapistStyle; // Full therapist style object (Phase 1A.1)
  final bool isAutoListeningEnabled; // From AutoListeningCoordinator
  final int currentMessageSequence; // Added for message sequencing
  final bool speakerMuted; // Track speaker mute state
  final double amplitude; // Real-time audio amplitude [0-1] for visualization
  // Session timer remaining seconds (counts down from selected duration)
  final int timerRemainingSeconds;
  // Flag indicating time limit reached and auto end flow should trigger
  final bool autoEndTriggered;

  const VoiceSessionState({
    required this.status,
    required this.messages,
    this.errorMessage,
    this.currentSessionId,
    this.isListening = false,
    this.isRecording = false,
    this.isProcessingAudio = false,
    this.isAiSpeaking = false,
    this.ttsStatus = TtsStatus.idle,
    this.ttsAudible = true,
    this.hasError = false,
    this.transcribedText,
    this.showMicButton = true, // Default to true, adjust based on mode
    this.showSendButton = false, // Default to false, adjust based on mode
    this.selectedDuration,
    this.showDurationSelector = false, // Initialize to false
    this.showMoodSelector = false,
    this.selectedMood,
    this.currentSystemPrompt,
    this.isMicEnabled = true, // Assume enabled until checked
    this.isVoiceMode = true, // Default to voice mode
    this.isInitialGreetingPlayed = false,
    this.activeTherapyStyleName,
    this.therapistStyle, // Phase 1A.1: Full therapist style object
    this.isAutoListeningEnabled = false,
    required this.currentMessageSequence, // Added
    this.speakerMuted = false,
    this.amplitude = 0.0,
    this.timerRemainingSeconds = 0,
    this.autoEndTriggered = false,
  });

  factory VoiceSessionState.initial({
    String? sessionId,
    String? systemPrompt,
    String? therapyStyleName,
  }) {
    return VoiceSessionState(
      status: VoiceSessionStatus.initial,
      messages: [],
      errorMessage: null,
      currentSessionId: sessionId,
      isListening: false,
      isRecording: false,
      isProcessingAudio: false,
      isAiSpeaking: false,
      hasError: false,
      transcribedText: null,
      showMicButton: true, // Show mic button in initial voice mode
      showSendButton: false, // Don't show send in initial voice mode
      selectedDuration: null,
      showDurationSelector: false, // Start by showing duration selector
      showMoodSelector: false,
      selectedMood: null,
      currentSystemPrompt: systemPrompt,
      isMicEnabled: true, // Assuming enabled, will be updated
      isVoiceMode: true, // Default to voice mode
      isInitialGreetingPlayed: false,
      activeTherapyStyleName: therapyStyleName,
      therapistStyle: null, // Phase 1A.1: Will be set when mood is selected
      isAutoListeningEnabled: false,
      currentMessageSequence: 0, // Initialize sequence
      speakerMuted: false,
      amplitude: 0.0,
      timerRemainingSeconds: 0,
      autoEndTriggered: false,
    );
  }

  VoiceSessionState copyWith({
    VoiceSessionStatus? status,
    List<TherapyMessage>? messages,
    String? errorMessage,
    bool? clearErrorMessage,
    String? currentSessionId,
    bool? isListening,
    bool? isRecording,
    bool? isProcessingAudio,
    bool? isAiSpeaking,
    TtsStatus? ttsStatus,
    bool? ttsAudible,
    bool? hasError,
    String? transcribedText,
    bool? clearTranscribedText,
    bool? showMicButton,
    bool? showSendButton,
    Duration? selectedDuration,
    bool? showDurationSelector,
    bool? showMoodSelector,
    Mood? selectedMood,
    String? currentSystemPrompt,
    bool? isMicEnabled,
    bool? isVoiceMode,
    bool? isInitialGreetingPlayed,
    String? activeTherapyStyleName,
    TherapistStyle? therapistStyle, // Phase 1A.1
    bool? isAutoListeningEnabled,
    int? currentMessageSequence, // Added
    bool? speakerMuted,
    double? amplitude,
    int? timerRemainingSeconds,
    bool? autoEndTriggered,
  }) {
    return VoiceSessionState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage:
          clearErrorMessage == true ? null : errorMessage ?? this.errorMessage,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      isListening: isListening ?? this.isListening,
      isRecording: isRecording ?? this.isRecording,
      isProcessingAudio: isProcessingAudio ?? this.isProcessingAudio,
      isAiSpeaking: isAiSpeaking ?? this.isAiSpeaking,
      ttsStatus: ttsStatus ?? this.ttsStatus,
      ttsAudible: ttsAudible ?? this.ttsAudible,
      hasError: hasError ?? this.hasError,
      transcribedText: clearTranscribedText == true
          ? null
          : transcribedText ?? this.transcribedText,
      showMicButton: showMicButton ?? this.showMicButton,
      showSendButton: showSendButton ?? this.showSendButton,
      selectedDuration: selectedDuration ?? this.selectedDuration,
      showDurationSelector: showDurationSelector ?? this.showDurationSelector,
      showMoodSelector: showMoodSelector ?? this.showMoodSelector,
      selectedMood: selectedMood ?? this.selectedMood,
      currentSystemPrompt: currentSystemPrompt ?? this.currentSystemPrompt,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isVoiceMode: isVoiceMode ?? this.isVoiceMode,
      isInitialGreetingPlayed:
          isInitialGreetingPlayed ?? this.isInitialGreetingPlayed,
      activeTherapyStyleName:
          activeTherapyStyleName ?? this.activeTherapyStyleName,
      therapistStyle: therapistStyle ?? this.therapistStyle, // Phase 1A.1
      isAutoListeningEnabled:
          isAutoListeningEnabled ?? this.isAutoListeningEnabled,
      currentMessageSequence:
          currentMessageSequence ?? this.currentMessageSequence, // Added
      speakerMuted: speakerMuted ?? this.speakerMuted,
      amplitude: amplitude ?? this.amplitude,
      timerRemainingSeconds: timerRemainingSeconds ?? this.timerRemainingSeconds,
      autoEndTriggered: autoEndTriggered ?? this.autoEndTriggered,
    );
  }

  @override
  List<Object?> get props => [
        status,
        messages,
        errorMessage,
        currentSessionId,
        isListening,
        isRecording,
        isProcessingAudio,
        isAiSpeaking,
        ttsStatus,
        ttsAudible,
        hasError,
        transcribedText,
        showMicButton,
        showSendButton,
        selectedDuration,
        showDurationSelector,
        showMoodSelector,
        selectedMood,
        currentSystemPrompt,
        isMicEnabled,
        isVoiceMode,
        isInitialGreetingPlayed,
        activeTherapyStyleName,
        therapistStyle, // Phase 1A.1
        isAutoListeningEnabled,
        currentMessageSequence, // Added
        speakerMuted,
        amplitude,
        timerRemainingSeconds,
        autoEndTriggered,
      ];

  bool get canSend {
    // In chat mode: allow sending when not processing audio
    if (!isVoiceMode) {
      return !isProcessingAudio;
    }
    // In voice mode: only disable Send button when TTS is active 
    // (per engineer feedback: smart disable logic)
    return !isProcessingAudio && (ttsStatus == TtsStatus.idle || ttsStatus == TtsStatus.cancelled);
  }

  // Add missing getters for UI compatibility
  bool get isInitializing => status == VoiceSessionStatus.loading;
  int get sessionDurationMinutes => selectedDuration?.inMinutes ?? 0;
  int get sessionTimerSeconds =>
      timerRemainingSeconds;
  bool get isEndingSession => status == VoiceSessionStatus.ended;
  bool get isProcessing => isProcessingAudio;
  bool get isSpeakerMuted => speakerMuted;
  bool get isVADActive => isAutoListeningEnabled;
  // Returns true when VAD is active, not recording, not processing, and not AI speaking
  bool get isListeningForVoice =>
      isVADActive && !isRecording && !isProcessing && !isAiSpeaking;
}
