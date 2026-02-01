// lib/blocs/voice_session/voice_session_state.dart
// Clean state definition for VoiceSessionBloc

import 'package:flutter/foundation.dart';
import '../../services/pipeline/voice_pipeline_controller.dart';

/// Session status enum
enum VoiceSessionStatus {
  idle,
  initializing,
  active,
  error,
  ending,
}

/// Chat message model
@immutable
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final bool isError;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.isError = false,
    required this.timestamp,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    bool? isError,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      isError: isError ?? this.isError,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Voice session state
@immutable
class VoiceSessionState {
  final VoiceSessionStatus status;
  final List<ChatMessage> messages;
  final bool isVoiceMode;
  final bool isMicMuted;
  final bool isProcessing;
  final bool isSpeaking;
  final bool isRecording;
  final bool isAutoListeningEnabled;
  final bool isGreetingComplete;
  final double? amplitude;
  final String? selectedMood;
  final Duration? selectedDuration;
  final String? sessionId;
  final String? errorMessage;
  final VoicePipelinePhase? pipelinePhase;

  const VoiceSessionState({
    required this.status,
    required this.messages,
    required this.isVoiceMode,
    required this.isMicMuted,
    required this.isProcessing,
    required this.isSpeaking,
    required this.isRecording,
    required this.isAutoListeningEnabled,
    required this.isGreetingComplete,
    this.amplitude,
    this.selectedMood,
    this.selectedDuration,
    this.sessionId,
    this.errorMessage,
    this.pipelinePhase,
  });

  /// Initial state factory
  factory VoiceSessionState.initial() => const VoiceSessionState(
        status: VoiceSessionStatus.idle,
        messages: [],
        isVoiceMode: false,
        isMicMuted: false,
        isProcessing: false,
        isSpeaking: false,
        isRecording: false,
        isAutoListeningEnabled: false,
        isGreetingComplete: false,
      );

  VoiceSessionState copyWith({
    VoiceSessionStatus? status,
    List<ChatMessage>? messages,
    bool? isVoiceMode,
    bool? isMicMuted,
    bool? isProcessing,
    bool? isSpeaking,
    bool? isRecording,
    bool? isAutoListeningEnabled,
    bool? isGreetingComplete,
    double? amplitude,
    String? selectedMood,
    Duration? selectedDuration,
    String? sessionId,
    String? errorMessage,
    VoicePipelinePhase? pipelinePhase,
    bool clearError = false,
  }) {
    return VoiceSessionState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      isVoiceMode: isVoiceMode ?? this.isVoiceMode,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isProcessing: isProcessing ?? this.isProcessing,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isRecording: isRecording ?? this.isRecording,
      isAutoListeningEnabled: isAutoListeningEnabled ?? this.isAutoListeningEnabled,
      isGreetingComplete: isGreetingComplete ?? this.isGreetingComplete,
      amplitude: amplitude ?? this.amplitude,
      selectedMood: selectedMood ?? this.selectedMood,
      selectedDuration: selectedDuration ?? this.selectedDuration,
      sessionId: sessionId ?? this.sessionId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pipelinePhase: pipelinePhase ?? this.pipelinePhase,
    );
  }

  /// Whether user can send messages
  bool get canSendMessage => !isProcessing && status == VoiceSessionStatus.active;

  /// Whether mic button should be shown
  bool get showMicButton => isVoiceMode && !isProcessing;

  /// Whether we're in an error state
  bool get hasError => errorMessage != null;

  @override
  String toString() {
    return 'VoiceSessionState(status: $status, messages: ${messages.length}, '
        'voiceMode: $isVoiceMode, speaking: $isSpeaking, recording: $isRecording)';
  }
}
