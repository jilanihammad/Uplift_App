library;
import '../../widgets/mood_selector.dart';
import '../voice_session_state.dart';
class SessionStateManager {
  VoiceSessionState _state;
  SessionStateManager() : _state = VoiceSessionState.initial();
  VoiceSessionState get state => _state;
  VoiceSessionState initializeSession({
    String? sessionId,
    String? systemPrompt,
    String? therapyStyleName,
  }) {
    _state = VoiceSessionState.initial(
      sessionId: sessionId,
      systemPrompt: systemPrompt,
      therapyStyleName: therapyStyleName,
    );
    return _state;
  }
  VoiceSessionState startNewSession() {
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
      autoEndTriggered: false,
    );
    return _state;
  }
  VoiceSessionState setSessionStarted(String? sessionId) {
    _state = _state.copyWith(
      currentSessionId: sessionId,
      status: VoiceSessionStatus.loading,
    );
    return _state;
  }
  VoiceSessionState setSessionEnding() {
    if (_state.status == VoiceSessionStatus.ended) {
      return _state;
    }
    _state = _state.copyWith(
      status: VoiceSessionStatus.ended,
      speakerMuted: true, // Immediate speaker mute as per contract
    );
    return _state;
  }
  VoiceSessionState updateStatus(VoiceSessionStatus status) {
    _state = _state.copyWith(status: status);
    return _state;
  }
  VoiceSessionState selectMood(Mood mood) {
    _state = _state.copyWith(
      selectedMood: mood,
      showMoodSelector: false,
      status: VoiceSessionStatus.loading, // As per contract
    );
    return _state;
  }
  VoiceSessionState selectDuration(Duration duration) {
    _state = _state.copyWith(
      selectedDuration: duration,
      showDurationSelector: false,
      showMoodSelector: true,
    );
    return _state;
  }
  VoiceSessionState setMoodSelectorVisibility(bool show) {
    _state = _state.copyWith(showMoodSelector: show);
    return _state;
  }
  VoiceSessionState setDurationSelectorVisibility(bool show) {
    _state = _state.copyWith(showDurationSelector: show);
    return _state;
  }
  VoiceSessionState setInitializing(bool isInitializing) {
    _state = _state.copyWith(
      status:
          isInitializing ? VoiceSessionStatus.loading : VoiceSessionStatus.idle,
    );
    return _state;
  }
  VoiceSessionState setInitialGreetingPlayed() {
    _state = _state.copyWith(isInitialGreetingPlayed: true);
    return _state;
  }
  VoiceSessionState setTherapistStyle(dynamic therapistStyle) {
    _state = _state.copyWith(therapistStyle: therapistStyle);
    return _state;
  }
  VoiceSessionState setError(String errorMessage) {
    _state = _state.copyWith(
      errorMessage: errorMessage,
      hasError: true,
    );
    return _state;
  }
  VoiceSessionState clearError() {
    _state = _state.copyWith(
      clearErrorMessage: true,
      hasError: false,
    );
    return _state;
  }
  void updateState(VoiceSessionState newState) {
    _state = newState;
  }
  bool isSessionReady() {
    return _state.selectedMood != null && _state.selectedDuration != null;
  }
  bool isSessionEndingOrEnded() {
    return _state.status == VoiceSessionStatus.ended;
  }
  String getSessionConfigSummary() {
    final mood =
        _state.selectedMood?.toString().split('.').last ?? 'not selected';
    final duration = _state.selectedDuration?.inMinutes ?? 0;
    final style = _state.activeTherapyStyleName ?? 'default';
    return 'Mood: $mood, Duration: ${duration}min, Style: $style';
  }
}
