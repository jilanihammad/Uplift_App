// lib/services/pipeline/voice_pipeline_state.dart
// Unified state definition for voice pipeline

import 'voice_pipeline_controller.dart';

/// Extension methods for VoicePipelinePhase
extension VoicePipelinePhaseX on VoicePipelinePhase {
  /// Whether this phase represents an active listening state
  bool get isListening => this == VoicePipelinePhase.listening || 
                         this == VoicePipelinePhase.recording;
  
  /// Whether this phase represents an active speaking state
  bool get isSpeaking => this == VoicePipelinePhase.speaking ||
                        this == VoicePipelinePhase.greeting;
  
  /// Whether this phase represents a processing state
  bool get isProcessing => this == VoicePipelinePhase.transcribing;
  
  /// Whether this phase is idle
  bool get isIdle => this == VoicePipelinePhase.idle;
  
  /// Whether user can interact in this phase
  bool get canInteract => this == VoicePipelinePhase.listening || 
                         this == VoicePipelinePhase.idle;
}

/// Extension methods for VoicePipelineSnapshot
extension VoicePipelineSnapshotX on VoicePipelineSnapshot {
  /// Convenience getter for UI state
  bool get isListeningForVoice => phase == VoicePipelinePhase.listening;
  
  /// Whether mic button should be enabled
  bool get isMicEnabled => !micMuted;
  
  /// Whether auto-listening is active
  bool get isAutoListening => autoModeEnabled && !micMuted;
  
  /// User-friendly status message
  String get statusMessage {
    switch (phase) {
      case VoicePipelinePhase.idle:
        return 'Ready';
      case VoicePipelinePhase.greeting:
        return 'Playing welcome message...';
      case VoicePipelinePhase.listening:
        return micMuted ? 'Microphone muted' : 'Listening...';
      case VoicePipelinePhase.recording:
        return 'Recording...';
      case VoicePipelinePhase.transcribing:
        return 'Processing...';
      case VoicePipelinePhase.speaking:
        return 'Speaking...';
      case VoicePipelinePhase.cooldown:
        return 'Cooling down...';
      case VoicePipelinePhase.error:
        return errorMessage ?? 'Error occurred';
    }
  }
}
