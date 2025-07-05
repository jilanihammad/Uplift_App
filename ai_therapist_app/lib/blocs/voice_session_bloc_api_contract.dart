/// VoiceSessionBloc API Contract - Phase 0.5.3
/// 
/// This file defines the FROZEN public API contract for VoiceSessionBloc.
/// These interfaces MUST be maintained during refactoring to ensure backward compatibility.
/// Any changes to these contracts require migration strategies and deprecation cycles.
/// 
/// Created: Phase 0.5.3 - API Contract Definition (Safety-First Approach)
/// Status: FROZEN - Do not modify without careful consideration

import 'package:flutter_bloc/flutter_bloc.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';
import '../di/interfaces/interfaces.dart';

/// Public API Contract for VoiceSessionBloc
/// This abstract class defines the complete public interface that must be preserved
abstract class IVoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  IVoiceSessionBloc(VoiceSessionState initialState) : super(initialState);
  
  /// Required constructor parameters that must be maintained
  /// Note: These are constructor contracts, not method contracts
  /// 
  /// Required:
  /// - VoiceService voiceService
  /// - VADManager vadManager
  /// 
  /// Optional (for backward compatibility):
  /// - ITherapyService? therapyService
  /// - IVoiceService? interfaceVoiceService
  /// - IProgressService? progressService
  /// - INavigationService? navigationService
}

/// Event Processing Contract
/// All these events MUST continue to be accepted and processed
abstract class VoiceSessionEventContract {
  // Session Lifecycle Events
  static const Type startSession = StartSession;
  static const Type sessionStarted = SessionStarted;
  static const Type endSession = EndSession;
  static const Type endSessionRequested = EndSessionRequested;
  
  // Audio Control Events
  static const Type startListening = StartListening;
  static const Type stopListening = StopListening;
  static const Type switchMode = SwitchMode;
  static const Type processAudio = ProcessAudio;
  static const Type stopAudio = StopAudio;
  static const Type playAudio = PlayAudio;
  
  // State Management Events
  static const Type selectMood = SelectMood;
  static const Type moodSelected = MoodSelected;
  static const Type changeDuration = ChangeDuration;
  static const Type durationSelected = DurationSelected;
  static const Type showMoodSelector = ShowMoodSelector;
  static const Type showDurationSelector = ShowDurationSelector;
  
  // Message Processing Events
  static const Type processTextMessage = ProcessTextMessage;
  static const Type textMessageSent = TextMessageSent;
  static const Type addMessage = AddMessage;
  
  // Service Control Events
  static const Type initializeService = InitializeService;
  static const Type enableAutoMode = EnableAutoMode;
  static const Type disableAutoMode = DisableAutoMode;
  static const Type setSpeakerMuted = SetSpeakerMuted;
  static const Type toggleMicMute = ToggleMicMute;
  
  // Internal State Events
  static const Type setProcessing = SetProcessing;
  static const Type setRecordingState = SetRecordingState;
  static const Type updateAmplitude = UpdateAmplitude;
  static const Type handleError = HandleError;
  
  // TTS and Playback Events
  static const Type playWelcomeMessage = PlayWelcomeMessage;
  static const Type welcomeMessageCompleted = WelcomeMessageCompleted;
  static const Type audioPlaybackStateChanged = AudioPlaybackStateChanged;
  static const Type ttsStateChanged = TtsStateChanged;
  
  // Session State Events
  static const Type setInitializing = SetInitializing;
  static const Type setEndingSession = SetEndingSession;
  static const Type updateSessionTimer = UpdateSessionTimer;
}

/// State Contract - All state properties and computed getters that must be maintained
abstract class VoiceSessionStateContract {
  // Core State Properties
  VoiceSessionStatus get status;
  List<dynamic> get messages; // TherapyMessage type
  String? get errorMessage;
  String? get currentSessionId;
  
  // Audio State Properties
  bool get isListening;
  bool get isRecording;
  bool get isProcessingAudio;
  bool get isAiSpeaking;
  bool get isAutoListeningEnabled;
  bool get isMicEnabled;
  bool get speakerMuted;
  
  // UI State Properties
  bool get isVoiceMode;
  bool get showMoodSelector;
  bool get showDurationSelector;
  bool get showMicButton;
  bool get showSendButton;
  
  // Session Configuration
  dynamic get selectedMood; // Mood type
  Duration? get selectedDuration;
  String? get currentSystemPrompt;
  String? get activeTherapyStyleName;
  dynamic get therapistStyle; // TherapistStyle type
  
  // Tracking Properties
  bool get hasError;
  String? get transcribedText;
  bool get isInitialGreetingPlayed;
  int get currentMessageSequence;
  
  // Computed Properties (getters that must be maintained)
  bool get canSend; // => !isProcessingAudio && !isVoiceMode
  bool get isInitializing; // => status == VoiceSessionStatus.loading
  int get sessionDurationMinutes; // => selectedDuration?.inMinutes ?? 0
  int get sessionTimerSeconds; // => 0 (TODO placeholder)
  bool get isEndingSession; // => status == VoiceSessionStatus.ended
  double get amplitude; // => 0.0 (TODO placeholder)
  bool get isProcessing; // => isProcessingAudio
  bool get isSpeakerMuted; // => speakerMuted
  bool get isVADActive; // => isAutoListeningEnabled
  bool get isListeningForVoice; // => isVADActive && !isRecording && !isProcessing && !isAiSpeaking
  
  // Required Factory Method
  static VoiceSessionState initial({
    String? sessionId,
    String? systemPrompt,
    String? therapyStyleName,
  }) => VoiceSessionState.initial(
    sessionId: sessionId,
    systemPrompt: systemPrompt,
    therapyStyleName: therapyStyleName,
  );
}

/// Stream Subscription Contract
/// These streams MUST be subscribed to in constructor and cleaned up in close()
abstract class VoiceSessionStreamContract {
  /// Recording state stream from VoiceService
  /// Maps RecordingState to SetRecordingState events
  /// Thread: Main thread only
  static const String recordingStateStream = 'voiceService.recordingState';
  
  /// Audio playback state from AudioPlayerManager  
  /// Maps bool to AudioPlaybackStateChanged events
  /// Thread: Main thread only
  static const String audioPlaybackStream = 'audioPlayerManager.isPlayingStream';
  
  /// TTS speaking state from VoiceService
  /// Maps bool to TtsStateChanged events
  /// Critical for auto-listening coordination
  /// Thread: Main thread only
  static const String ttsStateStream = 'voiceService.isTtsActuallySpeaking';
}

/// Behavioral Contract - Critical behaviors that must be preserved
abstract class VoiceSessionBehaviorContract {
  /// Welcome Message Generation
  /// Must generate mood-appropriate welcome messages
  /// Must add to messages list with sequence number 1
  /// In voice mode, must trigger TTS playback
  static const String welcomeMessageBehavior = 'mood-based-welcome-generation';
  
  /// Auto-Listening Coordination
  /// Must respect 125ms buffer after TTS stops
  /// Must enable auto-mode when switching to voice
  /// Must disable auto-mode when switching to chat
  static const String autoListeningBehavior = 'tts-vad-coordination';
  
  /// Message Sequencing
  /// Must increment sequence for each message
  /// Must maintain order in messages list
  /// Must start from 0 on session start
  static const String messageSequencingBehavior = 'incremental-message-sequence';
  
  /// Error Handling
  /// Must propagate service errors to errorMessage
  /// Must set hasError flag appropriately
  /// Must clear processing state on error
  static const String errorHandlingBehavior = 'error-state-propagation';
  
  /// Mode Switching
  /// Voice mode: Stop audio, reset TTS, enable auto-mode
  /// Chat mode: Disable auto-mode, stop recording if active
  /// Must maintain 200ms delay for voice mode switch
  static const String modeSwitchingBehavior = 'voice-chat-mode-transition';
}

/// Timing Contract - Critical timing that must be preserved
abstract class VoiceSessionTimingContract {
  /// Buffer delay before enabling auto-listening after TTS
  /// Prevents Maya from hearing her own voice
  static const Duration autoListeningBuffer = Duration(milliseconds: 125);
  
  /// Delay when switching to voice mode
  /// Allows audio cleanup before mode transition
  static const Duration voiceModeSwitchDelay = Duration(milliseconds: 200);
  
  /// These delays are CRITICAL and must not be modified
}

/// Migration Strategy Contract
/// Defines how to handle the refactoring while maintaining compatibility
abstract class VoiceSessionMigrationContract {
  /// Phase 1: Internal refactoring with facade pattern
  /// - Create internal managers (SessionStateManager, TimerManager, etc.)
  /// - VoiceSessionBloc becomes a facade coordinating managers
  /// - All public API remains unchanged
  /// 
  /// Phase 2: Gradual API evolution (if needed)
  /// - Add new events/states with @deprecated on old ones
  /// - Maintain both old and new APIs simultaneously
  /// - Document migration path for consumers
  /// 
  /// Phase 3: Cleanup (future major version)
  /// - Remove deprecated APIs after migration period
  /// - Simplify internal structure
  /// - Update all consumers
}

/// Test Contract - What tests must continue to pass
abstract class VoiceSessionTestContract {
  /// All characterization tests in voice_session_bloc_characterization_test.dart
  /// must continue to pass (excluding mock/setup issues)
  /// 
  /// Key test scenarios:
  /// - Initial state structure
  /// - Event processing for all 30+ events  
  /// - State transitions and computed properties
  /// - Stream subscription lifecycle
  /// - Welcome message generation by mood
  /// - Mode switching behavior
  /// - Error propagation
  /// - Message sequencing
  
  static const String characterizationTests = 'test/blocs/voice_session_bloc_characterization_test.dart';
}

/// IMPORTANT: Facade Pattern Implementation Strategy
/// 
/// During refactoring, VoiceSessionBloc will become a facade that:
/// 1. Maintains this exact public API
/// 2. Delegates to internal managers (SessionStateManager, etc.)
/// 3. Coordinates between managers
/// 4. Preserves all timing and threading requirements
/// 
/// Example structure:
/// ```
/// class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
///   final SessionStateManager _sessionManager;
///   final TimerManager _timerManager;
///   final MessageCoordinator _messageCoordinator;
///   // ... other managers
///   
///   // All existing public API maintained
///   // Internal implementation delegated to managers
/// }
/// ```
/// 
/// This ensures ZERO breaking changes while achieving the refactoring goals.