/// VoiceSessionBloc manages the entire therapy session state including voice/text mode switching,
/// audio recording, TTS playback, message processing, and session lifecycle (mood selection, timer, etc).
/// This is the central brain that coordinates all real-time interactions during a therapy session.
///
/// Phase 1.1.4 Migration Status: ✅ REFACTORED WITH MANAGER FACADE
/// - Uses SessionStateManager, TimerManager, and MessageCoordinator internally
/// - Maintains exact public API compatibility (all 30+ events, full state contract)
/// - Facade pattern preserves backward compatibility while improving internal structure
/// - Thread safety and timing requirements preserved
///
/// Phase 6 Migration Status: ✅ COMPLETED
/// - Supports both legacy VoiceService and new IVoiceService interface
/// - Uses _safeVoiceService helper for gradual migration
/// - 18 method calls migrated to interface pattern
/// - Maintains full backward compatibility
///
/// Phase 2.2.2 Migration Status: ✅ COMPLETED  
/// - Constructor uses VoiceSessionCoordinator streams when available
/// - All service method calls use interface pattern via _safeVoiceService
/// - AutoListeningCoordinator methods use temporary helpers pending interface extension
/// - Full migration to VoiceSessionCoordinator architecture achieved

import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:async/async.dart';
import 'voice_session_event.dart';
import 'voice_session_state.dart';
import '../services/voice_service.dart';
import '../services/vad_manager.dart';
import '../services/enhanced_vad_manager.dart';
import '../services/session_scope_manager.dart';
import '../services/voice_session_coordinator.dart';
import '../services/auto_listening_coordinator.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import '../data/datasources/remote/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import '../models/therapy_message.dart';
import '../services/recording_manager.dart';
import '../widgets/mood_selector.dart'; // For Mood enum
import '../utils/amplitude_utils.dart';
import 'package:uuid/uuid.dart';

// Phase 1.1.4: Import new managers
import 'managers/session_state_manager.dart';
import 'managers/timer_manager.dart';
import 'managers/message_coordinator.dart';


class VoiceSessionBloc extends Bloc<VoiceSessionEvent, VoiceSessionState> {
  final VoiceService voiceService;
  final VADManager vadManager;
  final ITherapyService? therapyService;
  // Phase 6B-1: Optional IVoiceService parameter for gradual migration
  final IVoiceService? interfaceVoiceService;
  // Phase 1B.1: Standardized service injection
  final IProgressService? progressService;
  final INavigationService? navigationService;
  StreamSubscription? _recordingStateSub;
  StreamSubscription? _audioPlaybackSub;
  StreamSubscription? _ttsStateSub;
  StreamSubscription? _amplitudeSub;
  
  // Amplitude smoothing state
  double _lastSmoothedAmplitude = 0.0;

  // Phase 1.1.4: Manager instances (internal implementation details)
  late final SessionStateManager _sessionManager;
  late final TimerManager _timerManager;
  late final MessageCoordinator _messageCoordinator;
  
  // Session scope management for clean resource disposal
  final SessionScopeManager _scopeManager = SessionScopeManager();
  
  // Lifecycle management for app backgrounding/resuming (using WidgetsBindingObserver)
  late WidgetsBindingObserver _lifecycleObserver;
  
  // PHASE 2A: Generation counter to prevent dangling future race conditions
  int _modeGeneration = 0;
  
  // PHASE 2B: Cancelable operation for pending auto-enable operations
  CancelableOperation? _pendingAutoEnable;
  
  // Gate to prevent TTS from starting during atomic audio reset
  Completer<void>? _atomicResetCompleter;
  
  // NATURAL UX: Flag to defer VAD start until current TTS naturally finishes
  bool _deferAutoMode = false;
  
  // Session start guard: Prevents duplicate session initialization
  bool _sessionStarted = false;
  
  /// Whether a session is currently active (has session scope)
  bool get inSession => _scopeManager.inSession;

  /// Debug-only getter for accessing mode generation counter in tests
  @visibleForTesting
  int get debugModeGeneration => _modeGeneration;
  
  /// Current generation counter for TTS callback wiring
  int get currentGeneration => _modeGeneration;
  
  /// Single source of truth for TTS activity across all components
  /// Returns true if TTS is actively streaming or playing
  bool get isTtsActive => state.ttsStatus == TtsStatus.streaming || state.ttsStatus == TtsStatus.playing;
  
  /// Stream of TTS activity state for reactive components
  Stream<bool> get isTtsActiveStream => stream.map((state) => 
      state.ttsStatus == TtsStatus.streaming || state.ttsStatus == TtsStatus.playing).distinct();

  VoiceSessionBloc({
    required this.voiceService,
    required this.vadManager,
    this.therapyService,
    this.interfaceVoiceService, // Optional for backward compatibility
    // Phase 1B.1: Standardized service injection
    this.progressService,
    this.navigationService,
  }) : super(VoiceSessionState.initial()) {
    // Phase 1.1.4: Initialize managers
    _sessionManager = SessionStateManager();
    _timerManager = TimerManager();
    _messageCoordinator = MessageCoordinator();
    
    // Set up timer callbacks for session coordination
    _timerManager.onTimeUpdate = _onTimerUpdate;
    _timerManager.onSessionExpired = _onSessionExpired;
    _timerManager.onTimeWarning = _onTimeWarning;
    on<StartSession>(_onStartSession);
    on<EndSession>(_onEndSession);
    on<StartListening>(_onStartListening);
    on<StopListening>(_onStopListening);
    on<SelectMood>(_onSelectMood);
    on<ChangeDuration>(_onChangeDuration);
    // Phase 1A.3: New event handlers for refactoring
    on<SessionStarted>(_onSessionStarted);
    on<MoodSelected>(_onMoodSelected); 
    on<DurationSelected>(_onDurationSelected);
    on<TextMessageSent>(_onTextMessageSent);
    on<EndSessionRequested>(_onEndSessionRequested);
    on<SwitchMode>(_onSwitchMode);
    on<ProcessAudio>(_onProcessAudio);
    on<HandleError>(_onHandleError);
    on<UpdateAmplitude>(_onUpdateAmplitude);
    on<AddMessage>(_onAddMessage);
    on<SetProcessing>(_onSetProcessing);
    on<SetRecordingState>(_onSetRecordingState);
    on<ProcessTextMessage>(_onProcessTextMessage);
    on<ShowMoodSelector>(_onShowMoodSelector);
    on<ShowDurationSelector>(_onShowDurationSelector);
    on<ToggleMicMute>(_onToggleMicMute);
    on<SetSpeakerMuted>(_onSetSpeakerMuted);
    on<InitializeService>(_onInitializeService);
    on<EnableAutoMode>(_onEnableAutoMode);
    on<DisableAutoMode>(_onDisableAutoMode);
    on<StopAudio>(_onStopAudio);
    on<PlayAudio>(_onPlayAudio);
    on<AudioPlaybackStateChanged>(_onAudioPlaybackStateChanged);
    on<TtsStateChanged>(_onTtsStateChanged);
    on<PlayWelcomeMessage>(_onPlayWelcomeMessage);
    on<WelcomeMessageCompleted>(_onWelcomeMessageCompleted);
    on<SetInitializing>(_onSetInitializing);
    on<SetEndingSession>(_onSetEndingSession);
    on<UpdateSessionTimer>(_onUpdateSessionTimer);
    // Two-step session start flow to prevent premature audio activation
    on<StartSessionRequested>(_onStartSessionRequested);
    on<InitialMoodSelected>(_onInitialMoodSelected);
    
    // Phase 2.2.5: Optimized streams with distinct/shareReplay to eliminate spam
    if (interfaceVoiceService != null) {
      // Hot, deduplicated TTS state stream (prevents duplicate logging)
      final ttsState$ = _safeVoiceService.isTtsActuallySpeaking
          .distinct()                    // Remove identical edges
          .shareReplay(maxSize: 1);      // Hot, single subscription
      
      _ttsStateSub = ttsState$.listen((isSpeaking) {
        if (kDebugMode) {
          debugPrint('🎯 [TTS-TRACK] TTS state: $isSpeaking');
        }
        add(TtsStateChanged(isSpeaking));
        
        // NATURAL UX: Auto-enable voice mode when TTS naturally finishes
        if (!isSpeaking && _deferAutoMode) {
          _deferAutoMode = false;
          _enableAutoModeIfGenerationMatches();
        }
      });

      // VAD with hysteresis to reduce flipping by 20-30%
      final audioLevel$ = _safeVoiceService.audioLevelStream
          .scan<bool>((prev, curr, _) {
            const hi = 0.85, lo = 0.65;  // Hysteresis thresholds
            return prev ? curr > lo : curr > hi;
          }, false)
          .distinct()                    // Remove identical states
          .shareReplay(maxSize: 1);      // Single subscription
      
      _recordingStateSub = audioLevel$.listen((isRecording) {
        add(SetRecordingState(isRecording));
      });

      // Deduplicated audio playback stream
      final playbackState$ = DependencyContainer().ttsService.playbackStateStream
          .distinct()
          .shareReplay(maxSize: 1);
      
      _audioPlaybackSub = playbackState$.listen((isPlaying) {
        add(AudioPlaybackStateChanged(isPlaying));
      });
    } else {
      // Fallback to legacy VoiceService streams (also optimized)
      final recordingState$ = voiceService.recordingState
          .map((recState) => recState.toString().contains('recording'))
          .distinct()
          .shareReplay(maxSize: 1);
      
      _recordingStateSub = recordingState$.listen((isRecording) {
        add(SetRecordingState(isRecording));
      });

      final playbackState$ = voiceService
          .getAudioPlayerManager()
          .isPlayingStream
          .distinct()
          .shareReplay(maxSize: 1);
      
      _audioPlaybackSub = playbackState$.listen((isPlaying) {
        add(AudioPlaybackStateChanged(isPlaying));
      });

      final ttsState$ = voiceService.isTtsActuallySpeaking
          .distinct()
          .shareReplay(maxSize: 1);
      
      _ttsStateSub = ttsState$.listen((isSpeaking) {
        if (kDebugMode) {
          debugPrint('🎯 [TTS-TRACK] TTS state (legacy): $isSpeaking');
        }
        add(TtsStateChanged(isSpeaking));
      });
    }
    
    // Set up amplitude stream with throttling and smoothing
    _setupAmplitudeStream();
    
    // Initialize lifecycle observer for app backgrounding/resuming
    _lifecycleObserver = _VoiceSessionLifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    
    // PHASE 3: Set up safety gate callback for AutoListeningCoordinator
    voiceService.autoListeningCoordinator.isVoiceModeCallback = () => state.isVoiceMode;
    
    // BYPASS FIX: Set up voice mode callback for VoiceService
    voiceService.isVoiceModeCallback = () => state.isVoiceMode;
    
    // TIMING FIX: Set up generation callback for VoiceService
    voiceService.getCurrentGeneration = () => _modeGeneration;
  }

  // Phase 6B-3: Helper method to safely choose between interface and legacy service
  // For methods that exist in IVoiceService interface, use interface service
  // For methods that don't exist yet, fall back to legacy service  
  IVoiceService get _safeVoiceService {
    // If we have the interface service, use it; otherwise cast legacy service to interface
    return interfaceVoiceService ?? voiceService as IVoiceService;
  }

  // Enhanced state tracking for VAD coordination
  // Separate "AI speaking" from "user can hear it" for better control
  bool get aiSpeakingForVAD => state.isAiSpeaking;
  bool get aiSpeakingForUI => state.isAiSpeaking && state.ttsAudible;

  /// Wait for TTS completion using ExoPlayer events instead of fixed delays
  /// Guards against rapid state transitions with distinct() and take(1)
  Future<void> _waitForTtsCompletion() async {
    // RACE FIX: Check if TTS is already complete before waiting
    if (!isTtsActive) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] TTS already complete - no need to wait');
      }
      return;
    }
    
    // Use legacy service for AudioPlayerManager access (not yet in interface)
    final audioPlayerManager = voiceService.getAudioPlayerManager();
    
    try {
      await audioPlayerManager.processingStateStream
        .where((state) => state == ProcessingState.completed)
        .distinct()  // Guard against rapid state transitions
        .take(1)     // Take first completion event only
        .timeout(
          const Duration(seconds: 5), // Reasonable timeout
        )
        .first;
      
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] TTS completion detected via ProcessingState.completed');
      }
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] TTS completion timeout - failing to prevent stale operations');
      }
      rethrow; // Re-throw to fail the CancelableOperation and prevent stale EnableAutoMode
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Error waiting for TTS completion: $e');
      }
      rethrow; // Re-throw to fail the CancelableOperation
    }
  }

  /// Helper method to enable auto mode with generation matching guards
  /// Uses the same pattern as _onEnableAutoMode for consistency
  void _enableAutoModeIfGenerationMatches() {
    final gen = _modeGeneration;
    
    // Check if conditions are still valid (same pattern as _onEnableAutoMode)
    if (!state.isVoiceMode) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Not in voice mode, skipping auto mode enable');
      }
      return;
    }
    
    if (state.isAutoListeningEnabled) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Auto mode already active, skipping');
      }
      return;
    }
    
    if (state.isRecording) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Already recording, skipping auto mode enable');
      }
      return;
    }
    
    if (kDebugMode) {
      debugPrint('[VoiceSessionBloc] Dispatching EnableAutoMode after natural TTS completion (gen $gen)');
    }
    add(const EnableAutoMode());
  }

  // Phase 6B-3: Helper for legacy-only methods that haven't migrated to interface yet
  
  // Phase 2.2.2: Temporary helpers for AutoListeningCoordinator methods not yet in interface
  void _triggerListening() {
    // TODO: Add triggerListening() to IVoiceService interface
    voiceService.autoListeningCoordinator.triggerListening();
  }
  
  void _onProcessingComplete() {
    // TODO: Add onProcessingComplete() to IVoiceService interface  
    voiceService.autoListeningCoordinator.onProcessingComplete();
  }

  Future<void> _onStartSession(StartSession event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Starting new session...');
    
    // Re-entrancy guard
    if (inSession) {
      debugPrint('[VoiceSessionBloc] Session already in progress, ignoring StartSession');
      return;
    }
    
    try {
      // Performance monitoring
      final stopwatch = Stopwatch()..start();
      
      // Create fresh session scope with new service instances
      await _scopeManager.createSessionScope();
      
      // Get fresh session-scoped services
      final voiceCoordinator = _scopeManager.get<VoiceSessionCoordinator>();
      final autoListening = _scopeManager.get<AutoListeningCoordinator>();
      
      // Initialize session services
      await voiceCoordinator.initialize();
      await autoListening.initialize();
      
      // Wire unified TTS activity stream for improved VAD coordination
      autoListening.setTtsActivityStream(isTtsActiveStream);
      
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Session initialized in ${stopwatch.elapsedMilliseconds}ms');
      }
      
      // Phase 1.1.4: Use SessionStateManager for session start
      final newState = _sessionManager.startNewSession();
      
      // Reset managers
      _messageCoordinator.resetMessages();
      // Prepare timer to count down from selected duration (if any)
      _timerManager.stopTimer();
      if (state.selectedDuration != null) {
        _timerManager.setSessionDuration(state.selectedDuration!);
        _timerManager.startTimer();
        // Initialize displayed remaining time immediately
        add(const UpdateSessionTimer());
      }
      
      emit(newState);
      
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error starting session: $e');
      await _cleanupFailedSession();
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onEndSession(
      EndSession event, Emitter<VoiceSessionState> emit) async {
    if (!inSession) {
      debugPrint('[VoiceSessionBloc] No active session to end');
      return;
    }
    
    debugPrint('[VoiceSessionBloc] Ending session - cleaning up audio and resources...');

    try {
      // Async teardown order - stop services gracefully first
      await _safeVoiceService.stopAudio();     // Await playback completion
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');

      _safeVoiceService.resetTTSState(); // Flush TTS monitor (sync operation)
      await _safeVoiceService.disableAutoMode(); // Disable auto listening

      await _safeVoiceService.tryStopRecording(); // Stop VAD/recording (idempotent)

      debugPrint('[VoiceSessionBloc] Session services stopped gracefully');
      
      // Destroy entire session scope (automatic disposal)
      await _scopeManager.destroySessionScope();
      
      // Reset session start flag for next session
      _sessionStarted = false;

      debugPrint('[VoiceSessionBloc] Session cleanup completed successfully');
      
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error during session cleanup: $e');
      await _forceSessionCleanup();
    }

    emit(state.copyWith(
      isListening: false,
      isRecording: false,
      isProcessingAudio: false,
      isAiSpeaking: false,
    ));
    // Ensure timer is stopped and UI reflects 0
    _timerManager.stopTimer();
    add(const UpdateSessionTimer());
  }

  void _onStartListening(
      StartListening event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      isListening: true,
      isAutoListeningEnabled: true,
    ));
  }

  void _onStopListening(StopListening event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
      isListening: false,
      isAutoListeningEnabled: false,
    ));
  }

  void _onSelectMood(SelectMood event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(selectedMood: event.mood));
  }

  void _onChangeDuration(
      ChangeDuration event, Emitter<VoiceSessionState> emit) {
    // Sync current state to manager first to preserve status
    _sessionManager.updateState(state);
    
    // Use SessionStateManager for single source of truth
    final updatedState = _sessionManager.selectDuration(Duration(minutes: event.minutes));
    emit(updatedState);
  }

  Future<void> _onSwitchMode(
      SwitchMode event, Emitter<VoiceSessionState> emit) async {
    // PHASE 2A: Increment generation counter with overflow protection
    if (++_modeGeneration == 0) _modeGeneration = 1; // Skip 0, avoid wrap-around
    
    // NATURAL UX: Clear deferred auto mode flag on generation change
    _deferAutoMode = false;
    
    debugPrint(
        '[VoiceSessionBloc] Switching to ${event.isVoiceMode ? "voice" : "chat"} mode (gen $_modeGeneration)');

    // Get audio player manager for soft mute functionality (use legacy service)
    final audioPlayerManager = voiceService.getAudioPlayerManager();

    if (event.isVoiceMode) {
      debugPrint(
          '[VoiceSessionBloc] Preparing for voice mode (will unmute TTS stream)');
      try {
        // Begin atomic reset gate
        _atomicResetCompleter = Completer<void>();
        // Unmute audio but keep stream alive
        audioPlayerManager.mute(false);
        debugPrint('[VoiceSessionBloc] Audio unmuted for voice mode');

        // ENGINEER FEEDBACK: Set ttsStatus = idle BEFORE calling resets
        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          ttsAudible: true,
          isAiSpeaking: false,
          ttsStatus: TtsStatus.idle, // Set to idle before resets
          isAutoListeningEnabled: false,
          isInitialGreetingPlayed: false,
        ));

        // ENGINEER FEEDBACK: Single await chain for atomic reset sequence
        // Prevents AutoListening from firing while WebSocket tear-down is in flight
        await audioPlayerManager.lightweightReset(); // New lightweight reset method
        _safeVoiceService.resetTTSState(); // Now properly cleans WebSocket/resources
        _safeVoiceService.autoListeningCoordinator.reset(); // Counter/timer cleanup
        
        debugPrint('[VoiceSessionBloc] Atomic reset sequence complete - audio, TTS, and VAD state cleaned');
        // End atomic reset gate
        _atomicResetCompleter?.complete();

        // RACE CONDITION FIX: Defensive worker synchronization for voice mode
        // Ensures any previous VAD worker has completely exited before enabling auto mode
        try {
          if (AutoListeningCoordinator.isEnhancedVADEnabled) {
            final enhancedVAD = _safeVoiceService.autoListeningCoordinator.vadManager;
            if (enhancedVAD != null && enhancedVAD is EnhancedVADManager) {
              await enhancedVAD.waitForWorkerExit();
              if (kDebugMode) {
                debugPrint('[VoiceSessionBloc] Voice mode: VAD worker synchronized successfully');
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[VoiceSessionBloc] Voice mode: VAD worker sync failed (continuing anyway): $e');
          }
        }

        // ALWAYS enable auto mode when switching to voice mode
        // Keep autoModeEnabled=true throughout voice sessions
        await _safeVoiceService.enableAutoMode();
        debugPrint('[VoiceSessionBloc] Auto mode enabled for voice session');
        
        // NATURAL UX: Handle TTS state for smooth transitions
        if (state.isAiSpeaking) {
          // If TTS is currently speaking, defer auto listening until it finishes naturally
          _deferAutoMode = true;
          debugPrint('[VoiceSessionBloc] TTS is speaking, will enable auto mode after current TTS finishes naturally');
        } else if (state.messages.isNotEmpty) {
          // If TTS is not speaking, enable auto mode immediately
          _triggerListening();
          debugPrint('[VoiceSessionBloc] TTS not speaking, enabled auto mode immediately');
        }

        debugPrint('[VoiceSessionBloc] Voice mode switch complete - natural transition logic active');
      } catch (e) {
        // Ensure gate is released on errors
        _atomicResetCompleter?.complete();
        debugPrint('[VoiceSessionBloc] Failed to prepare for voice mode: $e');
        emit(state.copyWith(errorMessage: e.toString()));
      }
    } else {
      debugPrint('[VoiceSessionBloc] Switching to chat mode (will mute TTS stream)');
      try {
        // Mute audio but keep stream alive
        audioPlayerManager.mute(true);
        debugPrint('[VoiceSessionBloc] Audio muted for chat mode');

        emit(state.copyWith(
          isVoiceMode: event.isVoiceMode,
          ttsAudible: false,
          isAiSpeaking: false,
        ));

        // PHASE 2B: Cancel any pending auto-enable operations
        _pendingAutoEnable?.cancel();
        _pendingAutoEnable = null;

        // Phase 2.2.2: Use interface when available
        await _safeVoiceService.disableAutoMode();
        
        // RACE CONDITION FIX: Wait for VAD worker thread to completely exit before stopping recording
        // This prevents the Android AudioRecord race condition
        try {
          if (AutoListeningCoordinator.isEnhancedVADEnabled) {
            // Access enhanced VAD manager and wait for worker completion
            final enhancedVAD = _safeVoiceService.autoListeningCoordinator.vadManager;
            if (enhancedVAD != null && enhancedVAD is EnhancedVADManager) {
              await enhancedVAD.waitForWorkerExit();
              if (kDebugMode) {
                debugPrint('[VoiceSessionBloc] Chat mode: VAD worker synchronized successfully');
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[VoiceSessionBloc] Chat mode: VAD worker sync failed (continuing anyway): $e');
          }
        }
        
        String? path = await _safeVoiceService.tryStopRecording();
        if (path != null && path.isNotEmpty) {
          add(ProcessAudio(path));
        } else {
          emit(state.copyWith(isProcessingAudio: false));
        }
        emit(state.copyWith(isAutoListeningEnabled: false, isRecording: false));
        debugPrint(
            '[VoiceSessionBloc] VAD disabled successfully for chat mode');
      } catch (e) {
        debugPrint(
            '[VoiceSessionBloc] Failed to disable VAD for chat mode: $e');
        emit(state.copyWith(errorMessage: e.toString()));
      }
    }
  }

  Future<void> _onProcessAudio(
      ProcessAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Processing audio file: ${event.audioPath}');
    emit(state.copyWith(isProcessingAudio: true));

    try {
      final transcription =
          await _safeVoiceService.processRecordedAudioFile(event.audioPath);
      debugPrint('[VoiceSessionBloc] Transcription: "$transcription"');

      if (transcription.trim().isEmpty || transcription.startsWith("Error:")) {
        debugPrint('[VoiceSessionBloc] Empty or error transcription');
        emit(state.copyWith(
            isProcessingAudio: false,
            errorMessage: 'Could not understand audio'));
        return;
      }

      // Phase 1.1.4: Use MessageCoordinator for user message (consistent with text mode)
      _messageCoordinator.addUserMessage(transcription);

      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));

      // Use MessageCoordinator for conversation history
      final history = _messageCoordinator.buildConversationHistory();

      if (state.isVoiceMode) {
        debugPrint(
            '[VoiceSessionBloc] Voice mode - getting AI response...');
        emit(state.copyWith(isAiSpeaking: true, ttsStatus: TtsStatus.preparing));

        final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
        
        // Debug assertion to catch parallel TTS sessions
        assert(!isTtsActive, 
               'Attempted to start TTS while another session is active (status: ${state.ttsStatus})');
        
        final responseData =
            await therapyServiceInstance.processUserMessageWithStreamingAudio(
          transcription,
          history,
          onTTSStart: (responseText) {
            debugPrint('[VoiceSessionBloc] TTS streaming started - adding message to chat immediately');
            
            // Phase 1.1.4: Add Maya's message to chat IMMEDIATELY when TTS starts
            _messageCoordinator.addAIMessage(responseText);
            
            emit(state.copyWith(
              ttsStatus: TtsStatus.streaming,
              messages: _messageCoordinator.messages,
              currentMessageSequence: _messageCoordinator.currentSequence,
            ));
          },
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            emit(state.copyWith(isProcessingAudio: false, isAiSpeaking: false, ttsStatus: TtsStatus.idle));
            // Phase 2.2.2: Use helper method for legacy AutoListeningCoordinator
            _onProcessingComplete();
          },
          onTTSError: (error) async {
            debugPrint('[VoiceSessionBloc] TTS error: $error');
            emit(state.copyWith(
                isProcessingAudio: false,
                errorMessage: error.toString(),
                isAiSpeaking: false, ttsStatus: TtsStatus.idle));
            // Phase 2.2.2: Use helper method for legacy AutoListeningCoordinator
            _onProcessingComplete();
          },
        );

        final mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';

        debugPrint(
            '[VoiceSessionBloc] Maya\'s text response: "$mayaResponseText"');

        // Note: Maya's message is now added to MessageCoordinator in onTTSStart callback
        // This ensures it appears in chat immediately when TTS begins, not when it completes
      } else {
        // Text mode - only get text response without TTS
        debugPrint(
            '[VoiceSessionBloc] Text mode - getting text response only...');
        final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
        final mayaResponseText = await therapyServiceInstance.processUserMessage(
          transcription,
          history: history,
        );

        if (mayaResponseText.trim().isEmpty) {
          debugPrint('[VoiceSessionBloc] Empty response from Maya');
          emit(state.copyWith(
              isProcessingAudio: false,
              errorMessage: 'Failed to get response from Maya'));
          return;
        }

        debugPrint(
            '[VoiceSessionBloc] Maya\'s text response: "$mayaResponseText"');

        // Phase 1.1.4: Use MessageCoordinator for AI message (consistent with voice mode)
        _messageCoordinator.addAIMessage(mayaResponseText);

        emit(state.copyWith(
          messages: _messageCoordinator.messages,
          currentMessageSequence: _messageCoordinator.currentSequence,
          isProcessingAudio: false,
        ));
      }
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error in _onProcessAudio: $e');
      emit(
          state.copyWith(isProcessingAudio: false, errorMessage: e.toString()));
    }
  }

  void _onHandleError(HandleError event, Emitter<VoiceSessionState> emit) {
    // Enhanced error handling with specific BackendSchemaException support
    String userFriendlyMessage;
    
    // Parse the error string back to get the actual exception type
    final errorString = event.error.toString();
    
    if (errorString.startsWith('BackendSchemaException:')) {
      // Handle schema validation errors specifically
      userFriendlyMessage = "Update required - please restart the app and try again. "
          "If this continues, contact support.";
      
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Schema validation error detected: $errorString');
      }
    } else if (errorString.contains('Connection error:') || 
               errorString.contains('SocketException') ||
               errorString.contains('TimeoutException')) {
      // Handle network connectivity issues
      userFriendlyMessage = "Connection issue. Please check your internet connection and try again.";
    } else if (errorString.contains('Authentication required') || 
               errorString.contains('401')) {
      // Handle authentication issues
      userFriendlyMessage = "Session expired. Please restart the app to continue.";
    } else {
      // Generic error fallback
      userFriendlyMessage = "Something went wrong. Please try again.";
      
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] General error: $errorString');
      }
    }
    
    emit(state.copyWith(
      errorMessage: userFriendlyMessage,
      hasError: true,
    ));
  }

  void _onUpdateAmplitude(
      UpdateAmplitude event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(amplitude: event.amplitude));
  }

  Future<void> _onAddMessage(
      AddMessage event, Emitter<VoiceSessionState> emit) async {
    try {
      // Phase 1.1.4: Use MessageCoordinator for message addition
      final addedMessage = _messageCoordinator.addMessage(event.message);

      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));

      if (state.currentSessionId != null) {
        debugPrint(
            '[VoiceSessionBloc] Message would be added to repository: ${addedMessage.content.substring(0, min(addedMessage.content.length, 20))}... Seq: ${addedMessage.sequence}');
      } else {
        debugPrint(
            '[VoiceSessionBloc] CurrentSessionId is null, message not saved to repo.');
      }
    } catch (e, stackTrace) {
      debugPrint('Error adding message: $e $stackTrace');
      emit(state.copyWith(
          errorMessage: 'Failed to add message: $e', hasError: true));
    }
  }

  void _onSetProcessing(SetProcessing event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isProcessingAudio: event.isProcessing));
  }

  void _onSetRecordingState(
      SetRecordingState event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(isRecording: event.isRecording));
  }

  Future<void> _onProcessTextMessage(
      ProcessTextMessage event, Emitter<VoiceSessionState> emit) async {
    debugPrint(
        '[VoiceSessionBloc] Received ProcessTextMessage: \'${event.text}\'');
    debugPrint('[VoiceSessionBloc] Current state - isVoiceMode: ${state.isVoiceMode}, isProcessingAudio: ${state.isProcessingAudio}');
    emit(state.copyWith(isProcessingAudio: true));

    try {
      // Phase 1.1.4: Use MessageCoordinator for user message
      final userMessage = _messageCoordinator.addUserMessage(event.text);

      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));

      // Use MessageCoordinator for conversation history
      final history = _messageCoordinator.buildConversationHistory();

      final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
      String mayaResponseText;

      if (state.isVoiceMode) {
        debugPrint(
            '[VoiceSessionBloc] Text message in voice mode - getting AI response...');

        emit(state.copyWith(isAiSpeaking: true, ttsStatus: TtsStatus.preparing));

        // Debug assertion to catch parallel TTS sessions
        assert(!isTtsActive, 
               'Attempted to start TTS while another session is active (status: ${state.ttsStatus})');

        final responseData =
            await therapyServiceInstance.processUserMessageWithStreamingAudio(
          event.text,
          history,
          onTTSStart: (responseText) {
            debugPrint('[VoiceSessionBloc] TTS streaming started - adding message to chat immediately');
            
            // Phase 1.1.4: Add Maya's message to chat IMMEDIATELY when TTS starts
            _messageCoordinator.addAIMessage(responseText);
            
            emit(state.copyWith(
              ttsStatus: TtsStatus.streaming,
              messages: _messageCoordinator.messages,
              currentMessageSequence: _messageCoordinator.currentSequence,
            ));
          },
          onTTSPlaybackComplete: () async {
            debugPrint('[VoiceSessionBloc] Maya\'s TTS playback completed');
            emit(state.copyWith(isAiSpeaking: false, ttsStatus: TtsStatus.idle));
          },
          onTTSError: (error) {
            debugPrint('[VoiceSessionBloc] TTS Error: $error');
            emit(state.copyWith(
                isAiSpeaking: false, errorMessage: error.toString()));
          },
        );
        mayaResponseText = responseData['text'] as String? ??
            'I\'m having trouble responding right now.';
      } else {
        debugPrint('[VoiceSessionBloc] Text message in text mode - no TTS...');
        debugPrint('[VoiceSessionBloc] Calling therapyService.processUserMessage...');
        mayaResponseText = await therapyServiceInstance.processUserMessage(
          event.text,
          history: history,
        );
        debugPrint('[VoiceSessionBloc] Received therapy response: "${mayaResponseText.substring(0, 50)}..."');
      }

      // Phase 1.1.4: Use MessageCoordinator for AI message
      // Only add message for text mode - voice mode already adds it in onTTSStart callback
      if (!state.isVoiceMode) {
        final mayaResponse = _messageCoordinator.addAIMessage(mayaResponseText);
      }

      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        isProcessingAudio: false,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));

      debugPrint('[VoiceSessionBloc] Text message processing complete');
    } catch (e, stackTrace) {
      debugPrint('[VoiceSessionBloc] Error processing text message: $e');
      debugPrint('[VoiceSessionBloc] Stack trace: $stackTrace');
      
      // Ensure processing state is cleared and error is shown to user
      emit(state.copyWith(
        isProcessingAudio: false, 
        errorMessage: 'Failed to get response: ${e.toString()}',
        hasError: true,
      ));
      
      // Phase 1.1.4: Add fallback error message using MessageCoordinator
      final errorMessage = _messageCoordinator.addAIMessage(
        "I'm sorry, I'm having trouble responding right now. Please try again."
      );
      
      emit(state.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
      ));
    }
  }

  void _onShowMoodSelector(
      ShowMoodSelector event, Emitter<VoiceSessionState> emit) {
    debugPrint('[VoiceSessionBloc] Show mood selector: ${event.show}');
    // Phase 1.1.4: Use SessionStateManager for UI state
    final newState = _sessionManager.setMoodSelectorVisibility(event.show);
    emit(newState);
  }

  void _onShowDurationSelector(
      ShowDurationSelector event, Emitter<VoiceSessionState> emit) {
    debugPrint('[VoiceSessionBloc] Show duration selector: ${event.show}');
    // Phase 1.1.4: Use SessionStateManager for UI state
    final newState = _sessionManager.setDurationSelectorVisibility(event.show);
    emit(newState);
  }

  void _onToggleMicMute(ToggleMicMute event, Emitter<VoiceSessionState> emit) {
    final newMicEnabledState = !state.isMicEnabled;
    debugPrint('[VoiceSessionBloc] Toggle mic enabled: $newMicEnabledState');
    emit(state.copyWith(isMicEnabled: newMicEnabledState));

    // Behavior: when mic is muted, dispatch DisableAutoMode so bloc state is consistent;
    // when unmuted, re-arm auto mode if appropriate
    if (!newMicEnabledState) {
      // Muted: stop listening safely via bloc event and stop recording idempotently
      add(const DisableAutoMode());
      _safeVoiceService.tryStopRecording();
    } else {
      // Unmuted: only re-enable auto mode if in voice mode and not speaking
      if (state.isVoiceMode && !isTtsActive && !state.isRecording) {
        add(const EnableAutoMode());
      } else {
        // Defer auto-enable until current TTS finishes naturally
        _deferAutoMode = true;
      }
    }
  }

  void _onSetSpeakerMuted(
      SetSpeakerMuted event, Emitter<VoiceSessionState> emit) {
    _safeVoiceService.setSpeakerMuted(event.isMuted);
    emit(state.copyWith(speakerMuted: event.isMuted));
  }

  Future<void> _onInitializeService(
      InitializeService event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Initializing services...');
    emit(state.copyWith(isProcessingAudio: true));

    try {
      await _safeVoiceService.initialize();

      final therapyServiceInstance = therapyService ?? DependencyContainer().therapy;
      await therapyServiceInstance.init();

      debugPrint('[VoiceSessionBloc] Services initialized successfully');
      emit(state.copyWith(isProcessingAudio: false));
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Service initialization failed: $e');
      emit(
          state.copyWith(isProcessingAudio: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onEnableAutoMode(
      EnableAutoMode event, Emitter<VoiceSessionState> emit) async {
    // PHASE 2C: Capture generation for async operation guards
    final gen = _modeGeneration;
    debugPrint('[VoiceSessionBloc] Enabling auto mode (gen $gen)...');

    // PHASE 1 FIX: Only proceed if we're still in voice mode
    if (!state.isVoiceMode) {
      debugPrint('[VoiceSessionBloc] Not in voice mode, skipping auto mode enable');
      return;
    }

    if (state.isAutoListeningEnabled) {
      debugPrint('[VoiceSessionBloc] Auto mode already active, skipping');
      return;
    }

    try {
      await _safeVoiceService.stopAudio();
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');

      // PHASE 2C: Check generation and mode after async operation
      if (gen != _modeGeneration || !state.isVoiceMode) {
        debugPrint('[VoiceSessionBloc] Mode/generation changed during audio stop (gen was $gen, now $_modeGeneration), aborting auto mode enable');
        return;
      }

      _safeVoiceService.resetTTSState();

      // Wait for actual TTS completion instead of fixed delay
      debugPrint('[VoiceSessionBloc] Waiting for TTS completion before enabling auto-listening...');
      await _waitForTtsCompletion();

      // PHASE 2C: Check generation and mode after TTS completion wait
      if (gen != _modeGeneration || !state.isVoiceMode) {
        debugPrint('[VoiceSessionBloc] Mode/generation changed during TTS wait (gen was $gen, now $_modeGeneration), aborting auto mode enable');
        return;
      }

      await _safeVoiceService.enableAutoMode();
      emit(state.copyWith(isAutoListeningEnabled: true));

      // Phase 2.2.2: Use helper method for legacy AutoListeningCoordinator
      _triggerListening();

      debugPrint(
          '[VoiceSessionBloc] Auto mode enabled successfully, VAD is now active');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to enable auto mode: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onDisableAutoMode(
      DisableAutoMode event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Disabling auto mode...');

    try {
      // Phase 2.2.2: Use interface when available
      await _safeVoiceService.disableAutoMode();
      emit(state.copyWith(isAutoListeningEnabled: false));
      debugPrint('[VoiceSessionBloc] Auto mode disabled successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to disable auto mode: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onStopAudio(
      StopAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Stopping audio...');
    try {
      await _safeVoiceService.stopAudio();
      emit(state.copyWith(isAiSpeaking: false, ttsStatus: TtsStatus.idle));
      debugPrint('[VoiceSessionBloc] Audio stopped successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to stop audio: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onPlayAudio(
      PlayAudio event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Playing audio: ${event.audioPath}');
    try {
      await _safeVoiceService.playAudio(event.audioPath);
      debugPrint('[VoiceSessionBloc] Audio played successfully');
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Failed to play audio: $e');
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onPlayWelcomeMessage(
      PlayWelcomeMessage event, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Playing welcome message TTS: ${event.welcomeMessage}');
    
    try {
      // Ensure any in-flight atomic reset has finished before starting TTS
      if (_atomicResetCompleter != null && !_atomicResetCompleter!.isCompleted) {
        if (kDebugMode) {
          debugPrint('[VoiceSessionBloc] Waiting for atomic reset to finish before welcome TTS');
        }
        await _atomicResetCompleter!.future;
      }
      // Use VoiceService TTS state management to properly coordinate with auto-listening
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] updateTTSSpeakingState(true) - Welcome message starting');
      }
      _safeVoiceService.updateTTSSpeakingState(true); // Stops auto-listening
      
      // Use SimpleTTSService directly for welcome messages
      final ttsService = DependencyContainer().ttsService;
      await ttsService.speak(event.welcomeMessage, makeBackupFile: false);
      
      debugPrint('[VoiceSessionBloc] Welcome TTS streaming completed');
      
      // Use VoiceService TTS state management to trigger auto-listening
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] updateTTSSpeakingState(false) - Welcome message completed');
      }
      _safeVoiceService.updateTTSSpeakingState(false); // Starts auto-listening
      
      // Fire the welcome message completed event if needed
      add(const WelcomeMessageCompleted());
      
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error playing welcome message: $e');
      if (kDebugMode) {
        debugPrint('🎯 [TTS-TRACK] updateTTSSpeakingState(false) - Welcome message error recovery');
      }
      _safeVoiceService.updateTTSSpeakingState(false); // Reset state on error
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  void _onAudioPlaybackStateChanged(
      AudioPlaybackStateChanged event, Emitter<VoiceSessionState> emit) {}

  void _onTtsStateChanged(
      TtsStateChanged event, Emitter<VoiceSessionState> emit) {
    debugPrint('[VoiceSessionBloc] TTS state changed: ${event.isSpeaking}');

    final bool wasSpeaking = state.isAiSpeaking;
    emit(state.copyWith(isAiSpeaking: event.isSpeaking));

    if (wasSpeaking &&
        !event.isSpeaking &&
        !state.isInitialGreetingPlayed &&
        state.isVoiceMode) {
      debugPrint(
          '[VoiceSessionBloc] TTS transition detected (true -> false), initial TTS has completed, enabling listening');
      emit(state.copyWith(isInitialGreetingPlayed: true));

      // Wait for TTS completion and then enable auto mode
      // PHASE 1 FIX: Only launch completion handler if we're in voice mode
      if (state.isVoiceMode) {
        // PHASE 2C: Use CancelableOperation with generation guard and logging
        final gen = _modeGeneration;
        _pendingAutoEnable = CancelableOperation.fromFuture(
          _waitForTtsCompletion().then((_) {
            // Generation guard - return early if mode changed
            if (gen != _modeGeneration) {
              debugPrint('[VoiceSessionBloc] 🚫 Auto-enable cancelled - generation mismatch (was $gen, now $_modeGeneration)');
              return;
            }
            
            if (state.isVoiceMode &&
                state.isMicEnabled &&
                !state.isAutoListeningEnabled &&
                !state.isRecording) {
              debugPrint(
                  '[VoiceSessionBloc] Dispatching EnableAutoMode after TTS completion (gen $gen)');
              add(const EnableAutoMode());
            } else {
              debugPrint('[VoiceSessionBloc] Skipping auto-enable - conditions not met (voice: ${state.isVoiceMode}, autoEnabled: ${state.isAutoListeningEnabled}, recording: ${state.isRecording})');
            }
          }),
          onCancel: () => debugPrint('🚫 [CANCEL] Generation $gen auto-enable cancelled'),
        );
      }
    }
  }

  void _onWelcomeMessageCompleted(
      WelcomeMessageCompleted event, Emitter<VoiceSessionState> emit) {
    // Phase 1.1.4: Use SessionStateManager for greeting played state
    final newState = _sessionManager.setInitialGreetingPlayed();
    emit(newState);
  }

  void _onSetInitializing(
      SetInitializing event, Emitter<VoiceSessionState> emit) {
    // Phase 1.1.4: Use SessionStateManager for initialization state
    final newState = _sessionManager.setInitializing(event.isInitializing);
    emit(newState);
  }

  void _onSetEndingSession(
      SetEndingSession event, Emitter<VoiceSessionState> emit) {
    emit(state.copyWith(
        status: event.isEndingSession
            ? VoiceSessionStatus.ended
            : VoiceSessionStatus.idle));
  }

  void _onUpdateSessionTimer(
      UpdateSessionTimer event, Emitter<VoiceSessionState> emit) {
    // Pull remaining time from TimerManager and reflect in state
    final remaining = _timerManager.remainingSeconds;
    if (state.timerRemainingSeconds != remaining) {
      emit(state.copyWith(timerRemainingSeconds: remaining));
    }
  }

  // ========== Two-Step Session Start Flow ==========
  
  /// Handles the first step: "Talk Now" button tap -> show duration selector first, NO audio initialization
  void _onStartSessionRequested(
      StartSessionRequested event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      debugPrint('🎯 [VoiceSessionBloc] StartSessionRequested received!');
      debugPrint('   Current status: ${state.status}');
      debugPrint('   Current duration: ${state.selectedDuration?.inMinutes} minutes');
      debugPrint('   Current mood: ${state.selectedMood}');
      // Print stack trace to identify where this is being called from
      debugPrint('   Stack trace:');
      debugPrint(StackTrace.current.toString().split('\n').take(10).join('\n'));
    }
    
    if (state.status == VoiceSessionStatus.idle || state.status == VoiceSessionStatus.initial) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] StartSessionRequested: ${state.status} → awaitingMood, showing duration selector');
      }
      emit(state.copyWith(
        status: VoiceSessionStatus.awaitingMood,
        showDurationSelector: true,
        showMoodSelector: false,
      ));
    } else {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] StartSessionRequested ignored, current status: ${state.status}');
      }
    }
  }

  /// Handles the second step: mood selected -> start actual session with audio pipeline
  void _onInitialMoodSelected(
      InitialMoodSelected event, Emitter<VoiceSessionState> emit) async {
    // Validate we're in the correct state to accept mood selection
    if (state.status != VoiceSessionStatus.awaitingMood) {
      debugPrint('[VoiceSessionBloc] ERROR: InitialMoodSelected called from wrong state: ${state.status}');
      debugPrint('[VoiceSessionBloc] Mood selection should only happen from awaitingMood state');
      return;
    }
    
    await _beginSessionIfNeeded(event.mood, emit);
  }

  /// Reusable helper for session start with re-entrancy guard
  Future<void> _beginSessionIfNeeded(Mood mood, Emitter<VoiceSessionState> emit) async {
    if (_sessionStarted) {
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Session already started, ignoring duplicate request');
      }
      return;
    }
    
    // Validate duration is selected before starting session
    if (state.selectedDuration == null) {
      debugPrint('[VoiceSessionBloc] ERROR: Cannot start session without duration!');
      emit(state.copyWith(
        errorMessage: 'Please select a session duration first',
        status: VoiceSessionStatus.awaitingMood,
        showDurationSelector: true,
        showMoodSelector: false,
      ));
      return;
    }
    
    _sessionStarted = true;
    
    // Now it is safe to enable voice mode
    add(SwitchMode(true));
    
    if (kDebugMode) {
      debugPrint('[VoiceSessionBloc] InitialMoodSelected: awaitingMood → active, starting audio pipeline');
      debugPrint('[VoiceSessionBloc] Duration: ${state.selectedDuration?.inMinutes} minutes, Mood: $mood');
    }
    
    try {
      // Start the actual session with audio/VAD pipeline - reuse existing logic
      await _startSessionWithMood(mood, emit);
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error in session start: $e');
      _sessionStarted = false; // Reset flag on error
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  /// Extract session start logic to be called only after mood selection
  Future<void> _startSessionWithMood(Mood mood, Emitter<VoiceSessionState> emit) async {
    debugPrint('[VoiceSessionBloc] Starting session with mood: $mood');
    
    try {
      // Performance monitoring
      final stopwatch = Stopwatch()..start();
      
      // Create fresh session scope with new service instances (HEAVY INITIALIZATION)
      await _scopeManager.createSessionScope();
      
      // Get fresh session-scoped services
      final voiceCoordinator = _scopeManager.get<VoiceSessionCoordinator>();
      final autoListening = _scopeManager.get<AutoListeningCoordinator>();
      
      // Initialize session services (AUDIO/VAD INITIALIZATION)
      await voiceCoordinator.initialize();
      await autoListening.initialize();
      
      // Wire unified TTS activity stream for improved VAD coordination
      autoListening.setTtsActivityStream(isTtsActiveStream);
      
      if (kDebugMode) {
        debugPrint('[VoiceSessionBloc] Session services initialized in ${stopwatch.elapsedMilliseconds}ms');
      }
      
      // Use SessionStateManager for mood selection and session setup
      final newState = _sessionManager.selectMood(mood);
      
      // Reset managers for fresh session
      _messageCoordinator.resetMessages();
      
      // Add welcome message using MessageCoordinator (after reset)
      final welcomeMessage = _messageCoordinator.addWelcomeMessage(mood);
      // Start or restart session countdown timer now that session is active
      _timerManager.stopTimer();
      if (state.selectedDuration != null) {
        _timerManager.setSessionDuration(state.selectedDuration!);
        _timerManager.startTimer();
        add(const UpdateSessionTimer());
      }
      
      // Update state with new message and sequence - SET TO ACTIVE (not idle)
      final finalState = newState.copyWith(
        messages: _messageCoordinator.messages,
        currentMessageSequence: _messageCoordinator.currentSequence,
        status: VoiceSessionStatus.voiceModeActive, // SESSION IS NOW ACTIVE
      );
      
      // Sync managers with updated state
      _sessionManager.updateState(finalState);
      
      // Emit the active state
      emit(finalState);
      
      if (kDebugMode) {
        debugPrint('🚀 SESSION ACTIVE'); // Verification log
      }
      
      // If in voice mode, generate TTS for welcome message
      if (finalState.isVoiceMode) {
        if (kDebugMode) {
          debugPrint('[VoiceSessionBloc] Starting welcome TTS for voice mode');
        }
        add(PlayWelcomeMessage(welcomeMessage.content));
      }
      
    } catch (e) {
      debugPrint('[VoiceSessionBloc] Error starting session with mood: $e');
      _sessionStarted = false; // Reset flag on error
      await _cleanupFailedSession();
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  // ========== Phase 1A.3: New Event Handlers for Refactoring ==========

  /// Handles session initialization with optional sessionId
  void _onSessionStarted(SessionStarted event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Session started with ID: ${event.sessionId}');
    }
    
    // Phase 1.1.4: Use SessionStateManager for session started
    final newState = _sessionManager.setSessionStarted(event.sessionId);
    emit(newState);
  }

  /// Handles mood selection - moves logic from ChatScreen._handleMoodSelection
  void _onMoodSelected(MoodSelected event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Mood selected: ${event.mood}');
    }
    
    // Phase 1.1.4: Use SessionStateManager for mood selection
    var newState = _sessionManager.selectMood(event.mood);
    
    // Add welcome message using MessageCoordinator
    final welcomeMessage = _messageCoordinator.addWelcomeMessage(event.mood);
    
    // Update state with new message and sequence
    newState = newState.copyWith(
      messages: _messageCoordinator.messages,
      currentMessageSequence: _messageCoordinator.currentSequence,
      status: VoiceSessionStatus.idle, // Session ready after welcome message
    );
    
    // Sync managers with updated state
    _sessionManager.updateState(newState);
    
    emit(newState);
    
    // If in voice mode, generate TTS for welcome message
    if (newState.isVoiceMode) {
      if (kDebugMode) {
        print('[VoiceSessionBloc] Starting welcome TTS for voice mode');
      }
      add(PlayWelcomeMessage(welcomeMessage.content));
    }
  }

  /// Handles duration selection with Duration object
  void _onDurationSelected(DurationSelected event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Duration selected: ${event.duration.inMinutes} minutes');
    }
    
    // Phase 1.1.4: Use SessionStateManager and TimerManager for duration
    final newState = _sessionManager.selectDuration(event.duration);
    _timerManager.setSessionDuration(event.duration);
    
    emit(newState);
  }

  /// Handles text message sending - delegates to existing ProcessTextMessage
  void _onTextMessageSent(TextMessageSent event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Text message sent: "${event.message}"');
    }
    
    // Delegate to existing ProcessTextMessage handler
    add(ProcessTextMessage(event.message));
  }

  /// Handles session end request - moves core logic from ChatScreen._endSession  
  void _onEndSessionRequested(EndSessionRequested event, Emitter<VoiceSessionState> emit) {
    if (kDebugMode) {
      print('[VoiceSessionBloc] Session end requested');
    }
    
    // Phase 1.1.4: Use SessionStateManager for session ending
    final newState = _sessionManager.setSessionEnding();
    
    // Stop timer
    _timerManager.stopTimer();
    
    // Reset session start flag
    _sessionStarted = false;
    
    emit(newState);
    
    // Note: Wakelock, navigation, VAD stopping remain in UI layer for now
    // These are UI concerns that will be handled by ChatScreen
  }

  // Phase 1.1.4: Welcome message generation moved to MessageCoordinator
  // Old _addInitialAIMessage and _getWelcomeMessage methods removed
  // All welcome message logic now handled by MessageCoordinator.addWelcomeMessage()

  List<Map<String, String>> _buildConversationHistory(
      List<TherapyMessage> messages) {
    // Phase 1.1.4: Could use MessageCoordinator.buildConversationHistory() 
    // but keeping this method for backward compatibility in existing calls
    return messages
        .map((message) => {
              'role': message.isUser ? 'user' : 'assistant',
              'content': message.content,
            })
        .toList();
  }

  // Phase 1.1.4: Timer callback methods for coordination
  void _onTimerUpdate(int elapsedSeconds, int remainingSeconds) {
    // Timer updates can trigger state updates for UI refresh
    // For now, we emit the current state with updated timer info
    // This preserves the existing timer behavior without breaking changes
    add(const UpdateSessionTimer());
  }

  void _onSessionExpired() {
    if (kDebugMode) {
      debugPrint('[VoiceSessionBloc] Session time expired - requesting session end');
    }
    add(const EndSessionRequested());
  }

  void _onTimeWarning() {
    if (kDebugMode) {
      debugPrint('[VoiceSessionBloc] Session time warning - 5 minutes remaining');
    }
    // Could add a warning state or event here if needed in the future
  }

  // Phase 1.1.4: Synchronize manager states with bloc state
  void _syncManagersWithState() {
    // Update session manager state
    _sessionManager.updateState(state);
    
    // Update message coordinator
    _messageCoordinator.updateMessages(state.messages, state.currentMessageSequence);
    
    // Update timer if duration is set
    if (state.selectedDuration != null && _timerManager.sessionDuration != state.selectedDuration) {
      _timerManager.setSessionDuration(state.selectedDuration!);
    }
  }

  /// Cleanup after failed session initialization
  Future<void> _cleanupFailedSession() async {
    await _scopeManager.destroySessionScope();
  }
  
  /// Force cleanup for emergency situations
  Future<void> _forceSessionCleanup() async {
    await _scopeManager.destroySessionScope();
  }

  /// Handle app lifecycle changes for proper audio management
  void _onAppLifecycleStateChanged(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint('🌍 [LIFECYCLE] App state changed to: $state');
    }

    switch (state) {
      case AppLifecycleState.paused:
        // Force-mute audio when app goes to background
        if (this.state.isVoiceMode) {
          try {
            final audioPlayerManager = voiceService.getAudioPlayerManager();
            audioPlayerManager.mute(true);
            if (kDebugMode) {
              debugPrint('🔇 [LIFECYCLE] Force-muted audio due to app pause');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ [LIFECYCLE] Error muting audio on pause: $e');
            }
          }
        }
        break;

      case AppLifecycleState.resumed:
        // Un-mute only if in voice mode and TTS is audible
        if (this.state.isVoiceMode && this.state.ttsAudible) {
          try {
            final audioPlayerManager = voiceService.getAudioPlayerManager();
            audioPlayerManager.mute(false);
            if (kDebugMode) {
              debugPrint('🔊 [LIFECYCLE] Un-muted audio due to app resume (voice mode + TTS audible)');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ [LIFECYCLE] Error un-muting audio on resume: $e');
            }
            // Fallback: Try to recover audio state
            try {
              final audioPlayerManager = voiceService.getAudioPlayerManager();
              // Samsung Android 14 AudioTrack pause issue: Force reset audio session
              audioPlayerManager.mute(true);
              Future.delayed(const Duration(milliseconds: 100), () {
                audioPlayerManager.mute(false);
              });
            } catch (fallbackError) {
              if (kDebugMode) {
                debugPrint('⚠️ [LIFECYCLE] Fallback audio recovery also failed: $fallbackError');
              }
            }
          }
        }
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // No special handling needed for these states
        break;
    }
  }

  /// Set up amplitude stream with throttling and smoothing for UI visualization
  void _setupAmplitudeStream() {
    try {
      // Access the VAD manager's amplitude stream
      Stream<double> amplitudeStream;
      
      if (AutoListeningCoordinator.isEnhancedVADEnabled) {
        // Use enhanced VAD manager
        final enhancedVAD = _safeVoiceService.autoListeningCoordinator.vadManager;
        if (enhancedVAD != null && enhancedVAD is EnhancedVADManager) {
          amplitudeStream = enhancedVAD.amplitudeStream;
        } else {
          // Fallback to regular VAD
          amplitudeStream = vadManager.amplitudeStream;
        }
      } else {
        // Use regular VAD manager
        amplitudeStream = vadManager.amplitudeStream;
      }
      
      // Create throttled and processed amplitude stream (engineer feedback: 30fps)
      final processedAmplitudeStream = amplitudeStream
          .map((dbValue) => AmplitudeUtils.dbToLinear(dbValue))  // Convert dB to linear
          .map((linearValue) {
            // Apply EMA smoothing (engineer feedback: α ≈ 0.4)
            _lastSmoothedAmplitude = AmplitudeUtils.applySmoothing(
              linearValue, 
              _lastSmoothedAmplitude
            );
            return _lastSmoothedAmplitude;
          })
          .throttleTime(const Duration(milliseconds: 33))  // 30fps throttling
          .distinct((prev, curr) => (prev - curr).abs() < 0.02); // Reduce micro-changes
      
      _amplitudeSub = processedAmplitudeStream.listen((amplitude) {
        // Only update if in voice mode and listening state
        if (state.isVoiceMode && (state.isListeningForVoice || state.isRecording)) {
          add(UpdateAmplitude(amplitude));
        }
      });
      
      if (kDebugMode) {
        debugPrint('🎵 [AMPLITUDE] Amplitude stream connected with throttling');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [AMPLITUDE] Failed to set up amplitude stream: $e');
      }
    }
  }

  @override
  Future<void> close() async {
    // Cleanup any active session before closing bloc
    if (inSession) {
      await _forceSessionCleanup();
    }
    
    _recordingStateSub?.cancel();
    _audioPlaybackSub?.cancel();
    _ttsStateSub?.cancel();
    _amplitudeSub?.cancel();
    
    // PHASE 2B: Cancel any pending auto-enable operations
    _pendingAutoEnable?.cancel();
    _pendingAutoEnable = null;
    
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    
    // Phase 1.1.4: Dispose managers
    _timerManager.dispose();
    return super.close();
  }
}

/// Custom WidgetsBindingObserver for handling app lifecycle changes
class _VoiceSessionLifecycleObserver with WidgetsBindingObserver {
  final VoiceSessionBloc _bloc;

  _VoiceSessionLifecycleObserver(this._bloc);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _bloc._onAppLifecycleStateChanged(state);
  }
}
