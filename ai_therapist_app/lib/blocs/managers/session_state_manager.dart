/// SessionStateManager - Phase 1.1.1
/// 
/// Manages session lifecycle state transitions for VoiceSessionBloc.
/// This manager handles pure state management without any service dependencies
/// or platform channel interactions, making it safe to refactor and test.
/// 
/// Responsibilities:
/// - Session status transitions
/// - Mood and duration selection state
/// - UI visibility flags (selectors)
/// - Session configuration state
/// 
/// Thread Safety: All operations are synchronous and main-thread only
/// Dependencies: None (pure Dart)

import 'package:flutter/foundation.dart';
import '../../widgets/mood_selector.dart';
import '../voice_session_state.dart';

/// Manages session state transitions and configuration
class SessionStateManager {
  /// Current session state
  VoiceSessionState _state;
  
  /// Constructor initializes with default state
  SessionStateManager() : _state = VoiceSessionState.initial();
  
  /// Get current state
  VoiceSessionState get state => _state;
  
  /// Initialize session with optional parameters
  VoiceSessionState initializeSession({
    String? sessionId,
    String? systemPrompt,
    String? therapyStyleName,
  }) {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Initializing session with ID: $sessionId');
    }
    
    _state = VoiceSessionState.initial(
      sessionId: sessionId,
      systemPrompt: systemPrompt,
      therapyStyleName: therapyStyleName,
    );
    
    return _state;
  }
  
  /// Start a new session (reset to clean state)
  VoiceSessionState startNewSession() {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Starting new session - resetting state');
    }
    
    _state = _state.copyWith(
      status: VoiceSessionStatus.initial,
      isListening: false,
      isRecording: false,
      isProcessingAudio: false,
      errorMessage: null,
      clearErrorMessage: true,
      messages: [],
      isInitialGreetingPlayed: false,
      currentMessageSequence: 0,
    );
    
    return _state;
  }
  
  /// Set session ID and mark as loading
  VoiceSessionState setSessionStarted(String? sessionId) {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Session started with ID: $sessionId');
    }
    
    _state = _state.copyWith(
      currentSessionId: sessionId,
      status: VoiceSessionStatus.loading,
    );
    
    return _state;
  }
  
  /// Mark session as ending
  VoiceSessionState setSessionEnding() {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Marking session as ending');
    }
    
    // Prevent multiple end session calls
    if (_state.status == VoiceSessionStatus.ended) {
      return _state;
    }
    
    _state = _state.copyWith(
      status: VoiceSessionStatus.ended,
      speakerMuted: true, // Immediate speaker mute as per contract
    );
    
    return _state;
  }
  
  /// Update session status
  VoiceSessionState updateStatus(VoiceSessionStatus status) {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Updating status to: $status');
    }
    
    _state = _state.copyWith(status: status);
    return _state;
  }
  
  /// Select mood and hide selector
  VoiceSessionState selectMood(Mood mood) {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Mood selected: $mood');
    }
    
    _state = _state.copyWith(
      selectedMood: mood,
      showMoodSelector: false,
      status: VoiceSessionStatus.loading, // As per contract
    );
    
    return _state;
  }
  
  /// Select duration and hide selector
  VoiceSessionState selectDuration(Duration duration) {
    if (kDebugMode) {
      debugPrint('[SessionStateManager] Duration selected: ${duration.inMinutes} minutes');
    }
    
    _state = _state.copyWith(
      selectedDuration: duration,
      showDurationSelector: false,
    );
    
    return _state;
  }
  
  /// Show or hide mood selector
  VoiceSessionState setMoodSelectorVisibility(bool show) {
    _state = _state.copyWith(showMoodSelector: show);
    return _state;
  }
  
  /// Show or hide duration selector  
  VoiceSessionState setDurationSelectorVisibility(bool show) {
    _state = _state.copyWith(showDurationSelector: show);
    return _state;
  }
  
  /// Update initializing state
  VoiceSessionState setInitializing(bool isInitializing) {
    _state = _state.copyWith(
      status: isInitializing 
        ? VoiceSessionStatus.loading 
        : VoiceSessionStatus.idle,
    );
    return _state;
  }
  
  /// Mark welcome greeting as played
  VoiceSessionState setInitialGreetingPlayed() {
    _state = _state.copyWith(isInitialGreetingPlayed: true);
    return _state;
  }
  
  /// Update therapist style
  VoiceSessionState setTherapistStyle(dynamic therapistStyle) {
    _state = _state.copyWith(therapistStyle: therapistStyle);
    return _state;
  }
  
  /// Set error state
  VoiceSessionState setError(String errorMessage) {
    _state = _state.copyWith(
      errorMessage: errorMessage,
      hasError: true,
    );
    return _state;
  }
  
  /// Clear error state
  VoiceSessionState clearError() {
    _state = _state.copyWith(
      clearErrorMessage: true,
      hasError: false,
    );
    return _state;
  }
  
  /// Update the internal state (for BLoC coordination)
  void updateState(VoiceSessionState newState) {
    _state = newState;
  }
  
  /// Check if session is ready (mood and duration selected)
  bool isSessionReady() {
    return _state.selectedMood != null && _state.selectedDuration != null;
  }
  
  /// Check if session is ending or ended
  bool isSessionEndingOrEnded() {
    return _state.status == VoiceSessionStatus.ended;
  }
  
  /// Generate session configuration summary
  String getSessionConfigSummary() {
    final mood = _state.selectedMood?.toString().split('.').last ?? 'not selected';
    final duration = _state.selectedDuration?.inMinutes ?? 0;
    final style = _state.activeTherapyStyleName ?? 'default';
    
    return 'Mood: $mood, Duration: ${duration}min, Style: $style';
  }
}