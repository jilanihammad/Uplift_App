import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';

import 'audio_player_manager.dart';
import 'base_voice_service.dart' as base_voice;
import 'recording_manager.dart';
import 'vad_manager.dart';
import 'enhanced_vad_manager.dart';
import 'voice_service.dart';
import '../utils/logging_config.dart';
import '../utils/disposable.dart';
import '../utils/box_logger.dart';
import '../utils/log_channels.dart';
import '../utils/feature_flags.dart';

/// Coordinates automatic voice detection and recording
///
/// Manages the transition between Maya speaking and automatically
/// listening for user input using VAD
///
/// Simplified voice detection and recording coordination
/// Manages the transition between AI speaking and automatically
/// listening for user input using VAD
class AutoListeningCoordinator with SessionDisposable {
  // Core components
  final AudioPlayerManager _audioPlayerManager;
  final RecordingManager _recordingManager;
  final VoiceService _voiceService;

  // NEW: Combined stream for robust AI audio state tracking
  late final Stream<bool> _aiAudioActiveStream;
  final BehaviorSubject<bool> _aiAudioActivitySubject =
      BehaviorSubject<bool>.seeded(false);
  StreamSubscription<bool>? _aiAudioSourceSub;
  StreamSubscription<bool>? _startListeningSub;
  StreamSubscription<String>? _vadErrorSub;
  Completer<void>? _pendingDisableCompleter;
  bool _aiAudioActive = false;
  bool _autoModeEnabledDuringAiAudio = false;
  Timer? _aiAudioGuardTimer;
  static const Duration _aiAudioGuardTimeout = Duration(seconds: 10);
  final bool _voiceGuardEnabled;

  // Unified TTS activity stream (set after initialization if available)
  Stream<bool>? _ttsActivityStream;

  // VAD configuration - can switch between regular and enhanced VAD
  static bool _useEnhancedVAD =
      true; // Configuration flag - ENABLED for RNNoise integration
  late final dynamic _vadManager; // Can be VADManager or EnhancedVADManager

  bool get _vadTraceEnabled => kDebugMode && LogChannels.vadTrace;
  bool get _isPipelineIdle => !_isRecordingActive && !_isVadActive && !_aiAudioActive;

  void _logAutoEvent(
    String message, {
    String emoji = '🎤',
    Map<String, String>? details,
    bool trace = false,
  }) {
    if (trace && !_vadTraceEnabled) {
      return;
    }
    BoxLogger.debug(emoji, 'AutoListening', message, details: details);
  }

  void _trace(String message) {
    if (_vadTraceEnabled) {
      debugPrint(message);
    }
  }

  void _traceEntryPoint(String method) {
    if (!kDebugMode) {
      return;
    }
    if (FeatureFlags.isVoicePipelineControllerEnabled) {
      return;
    }
    debugPrint(
        '[AutoListeningCoordinator] $method called while controller flag disabled');
    debugPrint(StackTrace.current.toString());
  }

  // Configuration method to enable/disable Enhanced VAD
  static void setEnhancedVAD(bool enabled) {
    _useEnhancedVAD = enabled;
    if (kDebugMode) {
      AppLogger.d(
          ' AutoListeningCoordinator: Enhanced VAD ${enabled ? 'ENABLED' : 'DISABLED'}');
    }
  }

  static bool get isEnhancedVADEnabled => _useEnhancedVAD;

  /// RACE CONDITION FIX: Public getter to access VAD manager for worker synchronization
  dynamic get vadManager => _vadManager;

  // Stream controllers
  final StreamController<bool> _autoModeEnabledController =
      StreamController<bool>.broadcast();
  final StreamController<AutoListeningState> _stateController =
      StreamController<AutoListeningState>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  // Streams for external components to listen to
  Stream<bool> get autoModeEnabledStream => _autoModeEnabledController.stream;
  Stream<AutoListeningState> get stateStream => _stateController.stream;
  Stream<String?> get errorStream => _errorController.stream;

  // State tracking
  bool _autoModeEnabled = false;
  bool get autoModeEnabled => _autoModeEnabled;

  AutoListeningState _currentState = AutoListeningState.idle;
  AutoListeningState get currentState => _currentState;

  // Public getter for recording state
  bool get isRecording => _isRecordingActive;

  // Debounce timer for voice activity
  Timer? _speechEndDebounceTimer;

  // Timer to prevent stuck states
  Timer? _stuckStateTimer;

  // NEW: Handle speech events during processing state
  Timer? _pendingSpeechEndTimer;
  bool _hasPendingSpeechEnd = false;

  // RACE CONDITION FIX: Monotonic speech sequence counter
  int _speechSeq = 0;

  // VAD FLAPPING FIX: Track speech sessions to prevent rapid start/end cycles
  DateTime? _lastSpeechStartTime;
  bool _inSpeechSession = false;
  static const Duration _minSpeechGap = Duration(milliseconds: 300);

  // ADAPTIVE TIMER FIX: Track speech bursts to reduce latency
  int _speechBurstCount = 0;
  DateTime? _lastSpeechEndTime;
  static const Duration _burstResetThreshold = Duration(seconds: 3);
  static const Duration _baseSpeechTimeout = Duration(milliseconds: 1500);
  static const Duration _secondBurstTimeout = Duration(milliseconds: 1000);
  static const Duration _subsequentBurstTimeout = Duration(milliseconds: 800);
  static const Duration kPostStopDelay = Duration(milliseconds: 120);

  // RACE CONDITION FIX: Configurable ring-down delay for speaker silence and worker thread synchronization
  // Engineer note: Use 150-180ms for Bluetooth SCO/AAudio, 100ms for standard audio
  static const Duration kRingDownDelay = Duration(milliseconds: 100);
  static const Duration kWorkerSyncDelay = Duration(
      milliseconds: 50); // Extra safety buffer for worker thread cleanup

  // Callback for when speech is detected and recording starts
  Function()? onSpeechDetectedCallback;

  // Callback for when recording is stopped due to silence detection
  Function(String audioPath)? onRecordingCompleteCallback;

  // PHASE 3: Safety gate callback to check if we're in voice mode
  bool Function()? isVoiceModeCallback;

  // Guard flag to prevent duplicate stopRecording calls
  bool _isStoppingRecording = false;

  // Resource state tracking for safety guards
  bool _isVadActive = false;
  bool _isRecordingActive = false;

  // Transition guard to prevent duplicate calls
  bool _isTransitionInProgress = false;

  // Safety guard for _enterAiSpeakingComplete
  bool _awaitingPlaybackEnd = false;

  // CRITICAL: Guard flag to prevent multiple VAD restart attempts
  bool _vadRestartScheduled = false;

  // VAD transition serialization
  Completer<void>? _vadTransitionLock;
  int _vadGeneration = 0;
  int _activeListeningGeneration = 0;

  // VAD retry configuration
  static const int _maxVadRetries = 3;
  static const List<int> _retryDelays = [
    100,
    200,
    400
  ]; // Exponential backoff in milliseconds

  Future<void> _awaitVadTransition() async {
    final lock = _vadTransitionLock;
    if (lock != null && !lock.isCompleted) {
      await lock.future;
    }
  }

  Completer<void> _beginVadTransition() {
    final lock = Completer<void>();
    _vadTransitionLock = lock;
    _logAutoEvent(
      'Transition begin',
      details: {
        'gen': '$_vadGeneration',
        'timestamp': DateTime.now().toIso8601String(),
      },
      trace: true,
    );
    return lock;
  }

  void _endVadTransition(Completer<void> lock) {
    if (!lock.isCompleted) {
      lock.complete();
    }
    if (identical(_vadTransitionLock, lock)) {
      _vadTransitionLock = null;
    }
    _logAutoEvent(
      'Transition end',
      details: {
        'gen': '$_vadGeneration',
        'timestamp': DateTime.now().toIso8601String(),
      },
      trace: true,
    );
  }

  int _nextVadGeneration() => ++_vadGeneration;

  void _invalidateVadGeneration() {
    _vadGeneration++;
    _activeListeningGeneration = _vadGeneration;
  }

  void _cancelAllTimers({String reason = 'transition'}) {
    _cancelSpeechEndTimer(reason: reason);
    _pendingSpeechEndTimer?.cancel();
    _pendingSpeechEndTimer = null;
    _stuckStateTimer?.cancel();
    _stuckStateTimer = null;
    _cancelAiAudioGuardTimer();
  }

  void _markAutoModeAwaitingAiSilence() {
    if (!_voiceGuardEnabled || !_autoModeEnabled) {
      return;
    }
    _autoModeEnabledDuringAiAudio = true;
    _startAiAudioGuardTimer();
  }

  void _clearAutoModeAwaitingAiSilence({bool cancelTimer = true}) {
    if (!_voiceGuardEnabled) {
      return;
    }
    _autoModeEnabledDuringAiAudio = false;
    if (cancelTimer) {
      _cancelAiAudioGuardTimer();
    }
  }

  void _startAiAudioGuardTimer() {
    if (!_voiceGuardEnabled) {
      return;
    }
    _aiAudioGuardTimer?.cancel();
    _aiAudioGuardTimer = Timer(_aiAudioGuardTimeout, () {
      if (!_autoModeEnabledDuringAiAudio || !_autoModeEnabled) {
        return;
      }
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [GUARD] AI audio timeout hit; forcing listening restart');
      }
      _autoModeEnabledDuringAiAudio = false;
      _aiAudioActive = false;
      unawaited(_startListeningAfterDelay());
    });
  }

  void _cancelAiAudioGuardTimer() {
    if (!_voiceGuardEnabled) {
      return;
    }
    _aiAudioGuardTimer?.cancel();
    _aiAudioGuardTimer = null;
  }

  void _forceAiAudioIdle() {
    _aiAudioActive = false;
    _clearAutoModeAwaitingAiSilence();
    _cancelAiAudioGuardTimer();
    if (!_aiAudioActivitySubject.isClosed) {
      _aiAudioActivitySubject.add(false);
    }
  }

  Future<void> _waitForAiAudioSilence() async {
    if (!_aiAudioActive) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '[AutoListeningCoordinator] Waiting for AI audio to go idle before disabling auto mode');
    }

    try {
      await _aiAudioActiveStream
          .firstWhere((active) => !active)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Timed out waiting for AI audio to idle: $e');
      }
    }
  }

  void _completeDisableIfIdle() {
    final completer = _pendingDisableCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (!_isPipelineIdle) {
      return;
    }
    completer.complete();
    _pendingDisableCompleter = null;
  }

  void _setAutoModeEnabled(bool value, {String context = ''}) {
    if (_autoModeEnabled == value) {
      return;
    }
    _autoModeEnabled = value;
    if (!value) {
      _clearAutoModeAwaitingAiSilence();
    }
    _logAutoEvent(
      'Auto mode ${value ? 'enabled' : 'disabled'}'
      '${context.isNotEmpty ? ' ($context)' : ''}',
      emoji: value ? '🟢' : '⚪️',
    );
    _autoModeEnabledController.add(value);
  }

  // Constructor
  AutoListeningCoordinator({
    required AudioPlayerManager audioPlayerManager,
    required RecordingManager recordingManager,
    required VoiceService voiceService,
    Stream<bool>? ttsActivityStream, // Optional unified TTS state stream
    dynamic vadManager,
  })  : _audioPlayerManager = audioPlayerManager,
        _recordingManager = recordingManager,
        _voiceService = voiceService,
        _voiceGuardEnabled = FeatureFlags.isCoordinatorVoiceGuardEnabled {
    _vadManager = vadManager ??
        (_useEnhancedVAD ? EnhancedVADManager() : VADManager());
    if (kDebugMode) {
      _logAutoEvent(
        vadManager != null
            ? 'Using injected VAD Manager for testing'
            : 'Using ${_useEnhancedVAD ? 'Enhanced' : 'Standard'} VAD Manager',
        trace: true,
      );
    }

    // Store the initial TTS activity stream if provided
    _ttsActivityStream = ttsActivityStream;
    _aiAudioActiveStream = _aiAudioActivitySubject.stream;

    // NEW: Create combined stream that tracks if AI is making ANY sound
    // This fixes race conditions between TTS generation and audio playback
    _rebuildAiAudioActiveStream();
    _aiAudioActive = _voiceGuardEnabled
        ? (_audioPlayerManager.isPlaybackActive || _voiceService.isTtsActive)
        : false;
    _aiAudioActivitySubject.add(_aiAudioActive);

    if (kDebugMode) {
      AppLogger.d(' AutoListeningCoordinator: Set up combined AI audio stream');
    }

    _setupListeners();
  }

  /// Set unified TTS activity stream for improved coordination
  /// Call this after VoiceSessionBloc is initialized to use unified TTS state
  void setTtsActivityStream(Stream<bool> ttsActivityStream) {
    _ttsActivityStream = ttsActivityStream;
    _rebuildAiAudioActiveStream();
    if (kDebugMode) {
      AppLogger.d(
          ' AutoListeningCoordinator: Updated to use unified TTS activity stream');
    }
  }

  /// Rebuild the combined AI audio stream with current TTS stream
  void _rebuildAiAudioActiveStream() {
    _aiAudioSourceSub?.cancel();
    final combined = Rx.combineLatest2<bool, bool, bool>(
      _audioPlayerManager
          .isPlayingStream, // true while audio player outputs sound
      // Use unified TTS activity stream if available, otherwise fallback to polling VoiceService
      _ttsActivityStream ??
          Stream.periodic(const Duration(milliseconds: 100),
              (_) => _voiceService.isAiSpeaking).distinct(),
      (playing, speaking) => playing || speaking,
    ).distinct();

    _aiAudioSourceSub = combined.listen((isActive) {
      if (_aiAudioActivitySubject.isClosed) {
        return;
      }
      _aiAudioActivitySubject.add(isActive);
    });
  }

  // Safe VAD management with resource tracking and native crash protection
  Future<bool> _safeStartVAD() async {
    if (_isVadActive) {
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] VAD already active, skipping start');
      }
      return true;
    }
    try {
      final success = await _vadManager.startListening();
      if (success) {
        _isVadActive = true;
        if (kDebugMode) {
          _trace('[AutoListeningCoordinator] VAD started successfully');
        }
      }
      return success;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] CRITICAL: VAD start failed (native crash protection): $e');
      }
      _isVadActive = false; // Ensure state is consistent on failure
      return false;
    }
  }

  // NEW: VAD start with retry mechanism and exponential backoff
  Future<bool> _startVADWithRetry() async {
    if (_isVadActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [RETRY] VAD already active, skipping start');
      }
      return true;
    }

    for (int attempt = 1; attempt <= _maxVadRetries; attempt++) {
      try {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [RETRY] VAD start attempt $attempt/$_maxVadRetries');
        }

        final success = await _vadManager.startListening();
        if (success) {
          _isVadActive = true;
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [RETRY] VAD started successfully on attempt $attempt');
          }
          return true;
        } else {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [RETRY] VAD start returned false on attempt $attempt');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [RETRY] VAD start failed on attempt $attempt: $e');
        }
      }

      // If not the last attempt, wait before retrying
      if (attempt < _maxVadRetries) {
        final delayMs = _retryDelays[attempt - 1];
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [RETRY] Waiting ${delayMs}ms before retry ${attempt + 1}');
        }
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    // All retries failed
    _isVadActive = false;
    if (kDebugMode) {
      debugPrint(
          '[AutoListeningCoordinator] [RETRY] CRITICAL: All VAD start attempts failed after $_maxVadRetries retries');
    }

    // Emit error and transition to idle state
    _errorController
        .add('VAD startup failed after $_maxVadRetries retry attempts');
    _updateState(AutoListeningState.idle);

    return false;
  }

  Future<void> _safeStopVAD() async {
    if (!_isVadActive) {
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] VAD not active, skipping stop');
      }
      return;
    }
    try {
      await _vadManager.stopListening();
      _isVadActive = false;
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] VAD stopped successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] CRITICAL: VAD stop failed (native crash protection): $e');
      }
      _isVadActive = false; // Ensure state is consistent even on failure
    }
  }

  // Safe recording management with resource tracking
  Future<void> _safeStartRecording() async {
    if (_isRecordingActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Recording already active, skipping start');
      }
      return;
    }
    try {
      await _recordingManager.startRecording();
      _isRecordingActive = true;
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] Recording started successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] Recording start failed: $e');
      }
    }
  }

  Future<void> _safeStopRecording() async {
    if (!_isRecordingActive) {
      if (kDebugMode) {
        _trace(
            '[AutoListeningCoordinator] Recording not active, skipping stop');
      }
      return;
    }
    try {
      await _recordingManager.tryStopRecording();
      _isRecordingActive = false;
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] Recording stopped successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] Recording stop failed: $e');
      }
    }
  }

  // Set up listeners for component events
  void _setupListeners() {
    // Listen for audio playback state changes (UI updates only - NO VAD restarts)
    _audioPlayerManager.playbackActiveStream.listen((isPlaying) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [AUDIO] playbackActiveStream emitted: $isPlaying | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
      }
      if (_autoModeEnabled) {
        if (!isPlaying) {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [AUDIO] Playback ended - UI update only (VAD restart handled by TTS completion)');
          }
          // REMOVED: VAD restart logic from audio playback events to prevent race conditions
          // Only update UI state - TTS completion will handle VAD restart
        } else {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [AUDIO] Audio playing, stopping listening/recording and cancelling post-audio delay');
          }
          _stopListeningAndRecording();
          _updateState(AutoListeningState.aiSpeaking);
        }
      } else if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [AUDIO] Ignored isPlayingStream event because autoMode is disabled');
      }
    });

    // Subscribe to the combined AI audio stream (includes both TTS and audio playback)
    _subscribeToAiAudioActivity();

    // Listen for VAD speech start events
    _vadManager.onSpeechStart.listen((_) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] onSpeechStart emitted | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
      }
      if (_autoModeEnabled) {
        // VAD FLAPPING FIX: Only increment sequence for new speech sessions
        final now = DateTime.now();
        final isNewSession = !_inSpeechSession ||
            (_lastSpeechStartTime != null &&
                now.difference(_lastSpeechStartTime!) > _minSpeechGap);

        if (isNewSession) {
          _speechSeq++;
          _inSpeechSession = true;
          _lastSpeechStartTime = now;

          // ADAPTIVE TIMER FIX: Track speech bursts for adaptive timeout
          if (_lastSpeechEndTime != null) {
            final timeSinceLastEnd = now.difference(_lastSpeechEndTime!);
            if (timeSinceLastEnd <= _burstResetThreshold) {
              _speechBurstCount++;
              if (kDebugMode) {
                debugPrint(
                    '[AutoListeningCoordinator] [ADAPTIVE-TIMER] Speech burst detected, count: $_speechBurstCount (gap: ${timeSinceLastEnd.inMilliseconds}ms)');
              }
            } else {
              _speechBurstCount = 1; // Reset burst count after long pause
              if (kDebugMode) {
                debugPrint(
                    '[AutoListeningCoordinator] [ADAPTIVE-TIMER] Long pause detected, resetting burst count to 1 (gap: ${timeSinceLastEnd.inMilliseconds}ms)');
              }
            }
          } else {
            _speechBurstCount = 1; // First speech of session
          }

          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [VAD-FLAPPING-FIX] New speech session started, sequence: $_speechSeq, burst: $_speechBurstCount');
          }
        } else {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [VAD-FLAPPING-FIX] Continuing speech session $_speechSeq (gap < ${_minSpeechGap.inMilliseconds}ms)');
          }
        }

        if (_currentState == AutoListeningState.listening) {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [VAD] VAD detected speech start, cancelling speech end timer and starting recording');
          }
          _cancelSpeechEndTimer();

          // CRITICAL FIX: Always transition to userSpeaking, even if recording was already active
          if (!_isRecordingActive) {
            _startRecording(_activeListeningGeneration);
          } else {
            if (kDebugMode) {
              debugPrint(
                  '[AutoListeningCoordinator] [VAD] Recording already active, but transitioning to userSpeaking anyway');
            }
          }
          // Always transition to userSpeaking state to prevent endless loop
          _updateState(AutoListeningState.userSpeaking);
        } else if (_currentState == AutoListeningState.processing) {
          // CRITICAL FIX: Cancel pending speech end if user resumes speaking
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator][DEBUG] Speech started during processing - cancelling pending stop');
          }
          _cancelPendingSpeechEnd();
        } else if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [VAD] Ignored onSpeechStart event (autoModeEnabled=$_autoModeEnabled, currentState=$_currentState)');
        }
      }
    });

    // Listen for VAD speech end events
    _vadManager.onSpeechEnd.listen((_) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] onSpeechEnd event received | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
        if (loggingConfig.isVerboseDebugEnabled) {
          debugPrint(StackTrace.current.toString());
        }
      }
      if (_autoModeEnabled) {
        if (_currentState == AutoListeningState.userSpeaking) {
          // VAD FLAPPING FIX: Add hysteresis - don't start timer if speech just started
          final now = DateTime.now();
          if (_lastSpeechStartTime != null) {
            final timeSinceSpeechStart = now.difference(_lastSpeechStartTime!);
            if (timeSinceSpeechStart < const Duration(milliseconds: 200)) {
              if (kDebugMode) {
                debugPrint(
                    '[AutoListeningCoordinator][VAD-FLAPPING-FIX] Ignoring speech end - too soon after start (${timeSinceSpeechStart.inMilliseconds}ms < 200ms)');
              }
              return; // Ignore this speech end event
            }
          }

          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator][DEBUG] Calling _startSpeechEndTimer() after onSpeechEnd');
          }
          _startSpeechEndTimer();
        } else if (_currentState == AutoListeningState.processing) {
          // CRITICAL FIX: Handle speech end during processing with debounce
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator][DEBUG] Speech end during processing - scheduling immediate stop with 200ms debounce');
          }
          _handleSpeechEndDuringProcessing();
        } else if (_currentState == AutoListeningState.listening) {
          // CRITICAL FIX: Handle stray recording when stuck in listening state
          if (_isRecordingActive) {
            if (kDebugMode) {
              debugPrint(
                  '[AutoListeningCoordinator][DEBUG] Speech ended while in listening state but recording is active - cleaning up stray recording');
            }
            _stopRecording();
          }
        } else if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] Ignored onSpeechEnd event (autoModeEnabled=$_autoModeEnabled, currentState=$_currentState)');
        }
      }
    });

    // Listen for recording state changes
    _recordingManager.recordingStateStream.listen((state) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [RECORDING] recordingStateStream emitted: $state | currentState=$_currentState');
      }
      if (state == base_voice.RecordingState.recording) {
        _updateState(AutoListeningState.userSpeaking);
      } else if (state == base_voice.RecordingState.stopped &&
          _currentState == AutoListeningState.userSpeaking) {
        _updateState(AutoListeningState.processing);
      }
    });

    // Error handling
    _vadErrorSub = _vadManager.onError.listen((error) {
      _errorController.add('VAD error: $error');
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] [VAD] ERROR: $error');
      }
    });
  }

  void _subscribeToAiAudioActivity() {
    if (_aiAudioActivitySubject.isClosed) {
      return;
    }
    _startListeningSub?.cancel();
    _startListeningSub =
        _aiAudioActiveStream.listen(_handleAiAudioActivityChange);
  }

  void _handleAiAudioActivityChange(bool aiAudioActive) {
    _aiAudioActive = aiAudioActive;
    if (kDebugMode) {
      debugPrint(
          '[AutoListeningCoordinator] [UNIFIED-TTS] AI audio active: $aiAudioActive | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
    }
    if (!_autoModeEnabled) {
      _clearAutoModeAwaitingAiSilence();
      return;
    }

    if (!_voiceGuardEnabled) {
      if (aiAudioActive) {
        _updateState(AutoListeningState.aiSpeaking);
        _stopListeningAndRecording();
      } else if ((_currentState == AutoListeningState.aiSpeaking ||
              _currentState == AutoListeningState.idle) &&
          !_vadRestartScheduled) {
        _vadRestartScheduled = true;
        _enterAiSpeakingCompleteWithDebounce();
      }
      return;
    }

    if (aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      _vadRestartScheduled = false;
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [UNIFIED-TTS] AI audio active, stopping listening/recording');
      }
      _updateState(AutoListeningState.aiSpeaking);
      _stopListeningAndRecording();
    } else {
      _cancelAiAudioGuardTimer();
      if (!_autoModeEnabledDuringAiAudio) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [UNIFIED-TTS] AI audio stopped but no pending auto-mode restart');
        }
        return;
      }
      if ((_currentState == AutoListeningState.aiSpeaking ||
              _currentState == AutoListeningState.idle) &&
          !_vadRestartScheduled) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [UNIFIED-TTS] AI audio complete - scheduling VAD restart');
        }
        _vadRestartScheduled = true;
        _enterAiSpeakingCompleteWithDebounce();
      } else if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [UNIFIED-TTS] AI audio stopped but restart already scheduled or inappropriate state ($_currentState)');
      }
    }
  }

  // ENGINEER FEEDBACK: Event-driven VAD restart with 100ms debounce for speaker ring-down
  Future<void> _enterAiSpeakingCompleteWithDebounce() async {
    // Safety guard to prevent multiple invocations
    if (_awaitingPlaybackEnd) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [DEBOUNCED] Already awaiting playback end, skipping duplicate call');
      }
      return;
    }
    _awaitingPlaybackEnd = true;

    try {
      // ENGINEER FEEDBACK: Debounce ~100ms post-playback silence for speaker ring-down
      // ENHANCED: Ensure any previous VAD worker threads have exited
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [DEBOUNCED] Debouncing VAD restart for 100ms + worker sync (speaker ring-down)');
      }

      // Wait for ring-down delay (configurable for different audio backends)
      await Future.delayed(kRingDownDelay);

      // RACE CONDITION FIX: Ensure previous VAD stop has completed worker thread cleanup
      // Since _safeStopVAD() was called in _stopListeningAndRecording(), the worker should be done,
      // but add a small additional safety buffer for any remaining cleanup
      await Future.delayed(kWorkerSyncDelay);

      // Verify we're still in the right state after debounce
      if (_currentState == AutoListeningState.aiSpeaking &&
          _autoModeEnabled &&
          _vadRestartScheduled) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [DEBOUNCED] Debounce complete, starting VAD');
        }

        // Start VAD immediately after debounce
        final vadStarted = await _startVADWithRetry();
        if (vadStarted) {
          await _startListeningAfterDelay();
        } else {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [DEBOUNCED] VAD restart failed after retries, transitioning to idle');
          }
          _updateState(AutoListeningState.idle);
        }
      } else {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [DEBOUNCED] State changed during debounce, skipping VAD restart');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [DEBOUNCED] Error during debounced VAD restart: $e');
      }
      _updateState(AutoListeningState.idle);
    } finally {
      _awaitingPlaybackEnd = false;
      _vadRestartScheduled = false;
    }
  }

  // NEW: Engineer's robust solution - wait for stable "not busy" state with crash protection
  Future<void> _enterAiSpeakingComplete() async {
    // Safety guard to prevent multiple invocations
    if (_awaitingPlaybackEnd) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [ROBUST] Already awaiting playback end, skipping duplicate call');
      }
      return;
    }
    _awaitingPlaybackEnd = true;

    try {
      // Use await with firstWhere - this returns a Future<bool>, not a StreamSubscription
      await _aiAudioActiveStream.firstWhere((busy) => !busy);

      if (_currentState == AutoListeningState.aiSpeaking &&
          _autoModeEnabled &&
          _vadRestartScheduled) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [ROBUST] AI audio definitively finished, starting VAD immediately');
        }

        // Start VAD immediately without delay
        final vadStarted = await _startVADWithRetry();
        if (vadStarted) {
          await _startListeningAfterDelay();
        } else {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator] [ROBUST] VAD restart failed after retries, transitioning to idle');
          }
          _updateState(AutoListeningState.idle);
        }
      } else if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [ROBUST] State changed, auto mode disabled, or restart not scheduled - skipping VAD start');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [ROBUST] CRITICAL: Error waiting for AI audio completion (native crash protection): $error');
      }
      // Ensure Maya doesn't get stuck by transitioning to idle on error
      _updateState(AutoListeningState.idle);
    } finally {
      // Always reset the safety guards
      _awaitingPlaybackEnd = false;
      _vadRestartScheduled =
          false; // Clear restart flag when operation completes
    }
  }

  Future<bool> _beginListeningIfAllowed({
    required String context,
    int? expectedGeneration,
    Set<AutoListeningState>? allowedStates,
    required Future<void> Function() onAllowed,
  }) async {
    final states = allowedStates ??
        {AutoListeningState.idle, AutoListeningState.aiSpeaking};

    if (expectedGeneration != null && expectedGeneration != _vadGeneration) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Listen start stale (context: $context, gen: $expectedGeneration vs $_vadGeneration)');
      }
      return false;
    }

    if (_aiAudioActive) {
      _markAutoModeAwaitingAiSilence();
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Listen start blocked – AI audio active (context: $context)');
      }
      return false;
    }

    if (!_autoModeEnabled) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Listen start blocked – auto mode disabled (context: $context)');
      }
      return false;
    }

    if (!states.contains(_currentState)) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Listen start blocked – invalid state $_currentState (context: $context)');
      }
      return false;
    }

    await onAllowed();
    return true;
  }

  // Start VAD listening after a short delay
  Future<void> _startListeningAfterDelay() async {
    _trace(
        '[AutoListeningCoordinator] [VAD] _startListeningAfterDelay called | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');

    if (_aiAudioActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] Deferred listening restart – AI audio still active');
      }
      _markAutoModeAwaitingAiSilence();
      return;
    }
    _clearAutoModeAwaitingAiSilence();

    // BYPASS FIX: Check voice mode before starting
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) return;

    await _beginListeningIfAllowed(
      context: 'deferred',
      allowedStates: {
        AutoListeningState.idle,
        AutoListeningState.aiSpeaking,
      },
      onAllowed: () async {
        await _awaitVadTransition();
        final transitionLock = _beginVadTransition();

        if (_isTransitionInProgress) {
          _trace(
              '[AutoListeningCoordinator] [VAD] Transition already in progress, ignoring duplicate call');
          _endVadTransition(transitionLock);
          return;
        }

        _isTransitionInProgress = true;
        _cancelAllTimers(reason: 'startListeningAfterDelay');
        final currentGeneration = _nextVadGeneration();

        try {
          _trace(
              '[AutoListeningCoordinator] [TRACE] startListeningAfterDelay begin gen=$currentGeneration time=${DateTime.now().toIso8601String()} state=$_currentState');

          if (_currentState == AutoListeningState.idle) {
            _updateState(AutoListeningState.listening);
            await _executeListeningStart(currentGeneration);
            return;
          }

          _updateState(AutoListeningState.listeningForVoice);
          _stuckStateTimer?.cancel();
          _stuckStateTimer = Timer(const Duration(seconds: 1), () {
            if (_currentState == AutoListeningState.listeningForVoice) {
              _trace(
                  '[AutoListeningCoordinator] [VAD] Stuck in listeningForVoice state, resetting to idle');
              _updateState(AutoListeningState.idle);
              _startListeningAfterDelay();
            }
          });

          if (!_autoModeEnabled) {
            if (kDebugMode) {
              debugPrint(
                  '[AutoListeningCoordinator] [VAD] Auto mode disabled, not starting listening');
            }
            _stuckStateTimer?.cancel();
            return;
          }

          await _executeListeningStart(currentGeneration);
        } finally {
          _isTransitionInProgress = false;
          _trace(
              '[AutoListeningCoordinator] [TRACE] startListeningAfterDelay end gen=$currentGeneration time=${DateTime.now().toIso8601String()} state=$_currentState autoMode=$_autoModeEnabled');
          _endVadTransition(transitionLock);
        }
      },
    );
  }

  // New method to handle the actual listening start
  Future<void> _executeListeningStart(int generation) async {
    _trace('[AutoListeningCoordinator] [VAD] Starting listening '
        '(generation=$generation, currentState=$_currentState, '
        'autoMode=$_autoModeEnabled, aiAudio=$_aiAudioActive)');

    if (_aiAudioActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] _executeListeningStart aborted – AI audio detected');
      }
      _markAutoModeAwaitingAiSilence();
      return;
    }

    // Only stop playback if something is actually playing
    if (_audioPlayerManager.isPlaybackActive) {
      await _voiceService.stopAudio();
    }

    // SERIALIZE RECORDING STARTUP: Start VAD first and let it settle (with crash protection)
    try {
      // Use retry mechanism for VAD startup
      final vadStarted = await _startVADWithRetry();
      if (!vadStarted) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [VAD] VAD startup failed with retries, aborting listening start');
        }
        return;
      }

      if (generation != _vadGeneration) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [VAD] Generation mismatch after VAD start (expected $generation, current $_vadGeneration)');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] VAD listening has started (mic unmuted after TTS)');
      }

      // VAD should be ready to start recording immediately
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] VAD settled, now starting recording pipeline');
      }

      // Start the actual recording pipeline as well
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [RECORDING] Calling voiceService.startRecording() after VAD start');
      }

      try {
        _activeListeningGeneration = generation;
        await _startRecording(generation);
        // Transition to listening state now that VAD is active
        _updateState(AutoListeningState.listening);
        // Cancel the stuck state timer since we successfully started
        _stuckStateTimer?.cancel();
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [VAD] Transitioned to listening state');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [RECORDING] CRITICAL: Error starting recording (native crash protection): $e');
        }
        // Clean up VAD on recording failure to prevent resource leak
        await _safeStopVAD();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] CRITICAL: Error in VAD startup sequence (native crash protection): $e');
      }
    }
    _trace('[AutoListeningCoordinator] [TRACE] _executeListeningStart completed '
        'gen=$generation state=$_currentState autoMode=$_autoModeEnabled '
        'time=${DateTime.now().toIso8601String()}');
  }

  // Start listening for voice activity
  Future<void> _startListening([int? generationOverride]) async {
    if (_aiAudioActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [VAD] _startListening blocked – AI audio active');
      }
      _markAutoModeAwaitingAiSilence();
      return;
    }
    _clearAutoModeAwaitingAiSilence();

    await _beginListeningIfAllowed(
      context: 'direct',
      allowedStates: {
        AutoListeningState.idle,
        AutoListeningState.processing,
      },
      onAllowed: () async {
        await _awaitVadTransition();
        final transitionLock = _beginVadTransition();
        final generation = generationOverride ?? _nextVadGeneration();
        _cancelAllTimers(reason: 'startListening');
        try {
          _trace(
              '[AutoListeningCoordinator] [TRACE] _startListening begin gen=$generation time=${DateTime.now().toIso8601String()} state=$_currentState autoMode=$_autoModeEnabled');
          try {
            final success = await _startVADWithRetry();
            if (success && generation == _vadGeneration) {
              _activeListeningGeneration = generation;
              _updateState(AutoListeningState.listening);
              _logAutoEvent(
                'Listening for voice activity',
                details: {
                  'gen': '$generation',
                  'state': _currentState.name,
                },
              );
            } else if (!success && kDebugMode) {
              _logAutoEvent(
                'VAD startup failed after retries',
                emoji: '⚠️',
                details: {'state': _currentState.name},
              );
            }
          } catch (e) {
            _errorController.add('Failed to start VAD listening: $e');
            _logAutoEvent('VAD listening error: $e', emoji: '❌');
          }
        } finally {
          _endVadTransition(transitionLock);
          _trace(
              '[AutoListeningCoordinator] [TRACE] _startListening end gen=$generation time=${DateTime.now().toIso8601String()} state=$_currentState autoMode=$_autoModeEnabled');
        }
      },
    );
  }

  // Start the audio recording
  Future<void> _startRecording(int generation) async {
    // PHASE 3: Safety gate - check if we're still in voice mode
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
      _logAutoEvent('Start recording blocked - not in voice mode', emoji: '⚠️');
      return;
    }
    if (_aiAudioActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [RECORDING] Start recording blocked - AI audio active');
      }
      _markAutoModeAwaitingAiSilence();
      return;
    }

    if (generation != _vadGeneration) {
      _trace(
          '[AutoListeningCoordinator] [RECORDING] Generation mismatch ($generation vs $_vadGeneration) - aborting start');
      return;
    }

    if (_currentState == AutoListeningState.listening) {
      try {
        _trace(
            '[AutoListeningCoordinator] [TRACE] _startRecording begin gen=$generation time=${DateTime.now().toIso8601String()}');
        await _safeStartRecording();

        // Notify listeners that recording has started
        if (onSpeechDetectedCallback != null) {
          onSpeechDetectedCallback!();
        }

        _logAutoEvent(
          'Recording started',
          details: {
            'gen': '$generation',
            'state': _currentState.name,
          },
        );
      } catch (e) {
        _errorController.add('Failed to start recording: $e');
        _logAutoEvent('Recording error: $e', emoji: '❌');
      }
    } else {
      _trace(
          '[AutoListeningCoordinator] [TRACE] _startRecording skipped - state=$_currentState gen=$generation time=${DateTime.now().toIso8601String()}');
    }
  }

  // Start timer to wait for speech to actually end
  void _startSpeechEndTimer() {
    _cancelSpeechEndTimer(reason: 'Starting new timer');

    // RACE CONDITION FIX: Capture current speech sequence
    final int currentSeq = _speechSeq;
    final int currentGen = _activeListeningGeneration;

    // ADAPTIVE TIMER FIX: Calculate timeout based on speech burst count
    final Duration timeout = _getAdaptiveSpeechTimeout();

    _trace(
        '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Starting ${timeout.inMilliseconds}ms timer (burst: $_speechBurstCount). Current state: $_currentState, sequence: $currentSeq');
    if (_vadTraceEnabled && loggingConfig.isVerboseDebugEnabled) {
      debugPrint(StackTrace.current.toString());
    }

    // Wait for silence to be detected for adaptive duration before stopping recording
    _speechEndDebounceTimer = Timer(timeout, () {
      _trace(
          '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired. Current state: $_currentState, timer seq: $currentSeq, current seq: $_speechSeq');
      if (_vadTraceEnabled && loggingConfig.isVerboseDebugEnabled) {
        debugPrint(StackTrace.current.toString());
      }

      // RACE CONDITION FIX: Only execute if sequence matches (no newer speech detected)
      if (currentGen == _activeListeningGeneration &&
          currentSeq == _speechSeq &&
          _currentState == AutoListeningState.userSpeaking) {
        // VAD FLAPPING FIX: End the speech session when timer fires
        _inSpeechSession = false;

        // ADAPTIVE TIMER FIX: Track when speech ends for burst calculation
        _lastSpeechEndTime = DateTime.now();

        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer firing _stopRecording() (sequence valid, session ended, burst: $_speechBurstCount)');
        }
        _stopRecording();
      } else {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired but sequence/gen mismatch or invalid state - ignoring (seq: $currentSeq vs $_speechSeq, gen: $currentGen vs $_activeListeningGeneration, state: $_currentState)');
        }
      }
    });
  }

  // Cancel the speech end timer
  void _cancelSpeechEndTimer({String reason = 'unknown'}) {
    if (_speechEndDebounceTimer != null && _speechEndDebounceTimer!.isActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] _cancelSpeechEndTimer: Cancelling timer. Reason: $reason | Current state: $_currentState');
        if (loggingConfig.isVerboseDebugEnabled) {
          debugPrint(StackTrace.current.toString());
        }
      }
      _speechEndDebounceTimer?.cancel();
    }
  }

  // ADAPTIVE TIMER FIX: Calculate timeout based on speech burst pattern
  Duration _getAdaptiveSpeechTimeout() {
    if (_speechBurstCount == 1) {
      // First speech burst - use base timeout (1.5s)
      return _baseSpeechTimeout;
    } else if (_speechBurstCount == 2) {
      // Second burst - reduce to 1.0s
      return _secondBurstTimeout;
    } else {
      // Third or subsequent burst - reduce to 0.8s for fastest response
      return _subsequentBurstTimeout;
    }
  }

  // CRITICAL FIX: Handle speech end during processing with immediate response and debounce
  void _handleSpeechEndDuringProcessing() {
    if (kDebugMode) {
      debugPrint(
          '[AutoListeningCoordinator][DEBUG] _handleSpeechEndDuringProcessing: Setting up 200ms debounce for immediate stop');
    }

    // Cancel any existing pending timer
    _cancelPendingSpeechEnd();

    // RACE CONDITION FIX: Capture current speech sequence
    final int currentSeq = _speechSeq;

    // Set flag and start debounce timer
    _hasPendingSpeechEnd = true;
    _pendingSpeechEndTimer = Timer(const Duration(milliseconds: 200), () {
      // RACE CONDITION FIX: Only execute if sequence matches
      if (_hasPendingSpeechEnd &&
          currentSeq == _speechSeq &&
          _currentState == AutoListeningState.processing) {
        // ENGINEER'S FIX: Only call _stopRecording if actually recording (reduces log noise)
        if (_isRecordingActive) {
          // ADAPTIVE TIMER FIX: Track when speech ends for burst calculation
          _lastSpeechEndTime = DateTime.now();

          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator][DEBUG] Pending speech end confirmed - stopping recording immediately (sequence: $currentSeq, burst: $_speechBurstCount)');
          }
          // Call stopRecording directly - this bypasses the 1.5s timer
          _stopRecording();
        } else if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] Pending speech end confirmed but recording not active - skipping no-op _stopRecording()');
        }
        _hasPendingSpeechEnd = false;
      } else if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] Pending speech end timer fired but conditions not met - ignoring (sequence: $currentSeq vs $_speechSeq, state: $_currentState, hasPending: $_hasPendingSpeechEnd)');
      }
    });
  }

  // CRITICAL FIX: Cancel pending speech end (called when user resumes speaking)
  void _cancelPendingSpeechEnd() {
    if (_pendingSpeechEndTimer != null && _pendingSpeechEndTimer!.isActive) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] _cancelPendingSpeechEnd: User resumed speaking, cancelling pending stop');
      }
      _pendingSpeechEndTimer?.cancel();
    }
    _hasPendingSpeechEnd = false;
  }

  // Stop recording and process the audio
  Future<void> _stopRecording() async {
    if (_isStoppingRecording) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] _stopRecording ignored: already stopping');
      }
      return;
    }
    _isStoppingRecording = true;
    try {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] _stopRecording called. Current state: $_currentState, _isStoppingRecording=$_isStoppingRecording');
        if (loggingConfig.isVerboseDebugEnabled) {
          debugPrint(StackTrace.current.toString());
        }
      }
      if (_currentState == AutoListeningState.userSpeaking) {
        // CRITICAL FIX: Stop VAD before stopping recording to prevent buffer race (with crash protection)
        try {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator][DEBUG] _stopRecording: Stopping VAD first to prevent buffer race');
          }
          await _vadManager.stopListening();
          _isVadActive = false; // Update state tracking
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[AutoListeningCoordinator][DEBUG] CRITICAL: VAD stop error during recording stop (native crash protection): $e');
          }
          _isVadActive = false; // Ensure consistent state even on failure
        }

        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] _stopRecording: About to call _recordingManager.stopRecording()');
        }
        final audioPath = await _recordingManager.tryStopRecording();

        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] _stopRecording: stopRecording() returned path: $audioPath');
        }
        if (audioPath != null && audioPath.isNotEmpty) {
          // RACE CONDITION FIX: Mark file as pending transcription to prevent path reuse
          _recordingManager.markFileAsPendingTranscription(audioPath);

          // Notify listeners that recording has completed
          if (onRecordingCompleteCallback != null) {
            onRecordingCompleteCallback!(audioPath);
          }

          if (kDebugMode) {
            _trace('🎤 AutoListening: Stopped recording, file at: $audioPath');
          }
        }
        // Cancel backup timer since recording stopped successfully
        _cancelSpeechEndTimer(reason: 'Recording stopped successfully');

        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] _stopRecording: About to call _updateState(processing)');
        }
        _updateState(AutoListeningState.processing);
      } else {
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator][DEBUG] _stopRecording called but not in userSpeaking state or already stopping, skipping.');
        }
      }
    } finally {
      // CRITICAL FIX: Always clear recording flag, even on error (engineer's fix)
      _isRecordingActive = false;
      _isStoppingRecording = false;
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator][DEBUG] _isStoppingRecording and _isRecordingActive reset to false');
      }
    }
  }

  // Stop both listening and recording
  Future<void> _stopListeningAndRecording() async {
    await _awaitVadTransition();
    final transitionLock = _beginVadTransition();
    final generation = _nextVadGeneration();
    try {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [TRACE] _stopListeningAndRecording begin gen=$generation time=${DateTime.now().toIso8601String()} state=$_currentState');
      }
      // Cancel any pending timers
      _cancelAllTimers(reason: 'stopListening');

      // CRITICAL FIX: Stop VAD stream FIRST and wait for complete shutdown
      await _safeStopVAD();
      if (kDebugMode) {
        _trace('🛑 AutoListening: VAD stopped and buffers released');
      }

      // Allow native recorder threads to settle
      await Future.delayed(kPostStopDelay);

      // Now safely stop recording
      if (_currentState == AutoListeningState.userSpeaking) {
        await _stopRecording();
        if (kDebugMode) {
          debugPrint(
              '🎤 AutoListening: Recording stopped safely after VAD shutdown');
        }
      }

      _activeListeningGeneration = generation;

      if (kDebugMode) {
        _trace('🎤 AutoListening: Complete shutdown sequence finished');
      }
    } catch (e) {
      _errorController.add('Error stopping listening/recording: $e');
      if (kDebugMode) {
        _trace('❌ AutoListening stop error: $e');
      }
    } finally {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [TRACE] _stopListeningAndRecording end gen=$generation time=${DateTime.now().toIso8601String()} state=$_currentState');
      }
      _endVadTransition(transitionLock);
    }
  }

  // Enable automatic listening mode with explicit audio state from Bloc
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
    _traceEntryPoint('enableAutoModeWithAudioState');
    // Cancel any post-audio delay when manually enabling auto mode

    if (!_autoModeEnabled) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [MODE] enableAutoModeWithAudioState called with isAudioPlaying=$isAudioPlaying');
      }
      _setAutoModeEnabled(true,
          context:
              'enableAutoModeWithAudioState(isAudioPlaying=$isAudioPlaying)');

      // Use the audio state provided by the Bloc instead of checking AudioPlayerManager
      final shouldDefer = isAudioPlaying || _aiAudioActive;
      if (shouldDefer) {
        _markAutoModeAwaitingAiSilence();
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [MODE] Audio active (bloc signal), setting state to aiSpeaking');
        }
        _updateState(AutoListeningState.aiSpeaking);
      } else {
        _clearAutoModeAwaitingAiSilence();
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [MODE] Bloc says audio idle, calling _startListening()');
        }
        await _startListening();
      }
    } else if (kDebugMode) {
      debugPrint(
          '[AutoListeningCoordinator] [MODE] enableAutoModeWithAudioState called, but autoModeEnabled already true');
    }
  }

  // Enable automatic listening mode (original method using AudioPlayerManager)
  Future<void> enableAutoMode() async {
    _traceEntryPoint('enableAutoMode');
    // STATE VALIDATION: Guard against unexpected state
    if (_currentState != AutoListeningState.idle) {
      final shouldResetState =
          !_voiceGuardEnabled || _currentState != AutoListeningState.aiSpeaking;
      if (shouldResetState) {
        if (kDebugMode) {
          AppLogger.w(
              '🚨 [ALS] enableAutoMode called in unexpected state=$_currentState - resetting to idle');
        }
        _updateState(AutoListeningState.idle);
      } else if (kDebugMode) {
        AppLogger.w(
            '⚪️ [ALS] enableAutoMode called while aiSpeaking; guard will handle restart');
      }
    }

    // CONTAMINATION CHECK: Warn about stale state that should have been reset
    if (_vadRestartScheduled || _speechSeq > 0 || _inSpeechSession) {
      if (kDebugMode) {
        AppLogger.w('⚠️ [ALS] enableAutoMode: Detected stale state - '
            'vadRestart=$_vadRestartScheduled seq=$_speechSeq inSession=$_inSpeechSession');
      }
    }

    if (!_autoModeEnabled) {
      if (kDebugMode) {
        _trace('[AutoListeningCoordinator] [MODE] enableAutoMode called');
      }
      _setAutoModeEnabled(true, context: 'enableAutoMode');

      final isAudioPlaying =
          _audioPlayerManager.isPlaybackActive || _aiAudioActive || _voiceService.isTtsActive;
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] [MODE] Audio active during enable: $isAudioPlaying');
      }

      if (isAudioPlaying) {
        _markAutoModeAwaitingAiSilence();
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [MODE] Audio is playing, setting state to aiSpeaking');
        }
        _updateState(AutoListeningState.aiSpeaking);
      } else {
        _clearAutoModeAwaitingAiSilence();
        if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [MODE] Audio idle, calling _startListening()');
        }
        await _startListening();
      }
    } else if (kDebugMode) {
      debugPrint(
          '[AutoListeningCoordinator] [MODE] enableAutoMode called, but autoModeEnabled already true');
    }
  }

  // Disable automatic listening mode
  Future<void> disableAutoMode() {
    _traceEntryPoint('disableAutoMode');
    final existing = _pendingDisableCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<void>();
    _pendingDisableCompleter = completer;

    () async {
      try {
        _cancelAllTimers(reason: 'disableAutoMode');
        final wasEnabled = _autoModeEnabled;
        if (wasEnabled) {
          if (kDebugMode) {
            _trace('[AutoListeningCoordinator] [MODE] disableAutoMode called');
          }
        } else if (kDebugMode) {
          debugPrint(
              '[AutoListeningCoordinator] [MODE] disableAutoMode called, but autoModeEnabled already false');
        }

        await _stopListeningAndRecording();
        await _waitForAiAudioSilence();

        if (wasEnabled && _autoModeEnabled) {
          _setAutoModeEnabled(false, context: 'disableAutoMode');
        }

        _invalidateVadGeneration();
        _forceAiAudioIdle();
        _updateState(AutoListeningState.idle);
        _completeDisableIfIdle();
      } catch (error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
        _pendingDisableCompleter = null;
        return;
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
      _pendingDisableCompleter = null;
    }();

    return completer.future;
  }

  // Validate state transitions to prevent race conditions
  bool _isValidTransition(AutoListeningState from, AutoListeningState to) {
    const validTransitions = {
      AutoListeningState.idle: {
        AutoListeningState.aiSpeaking,
        AutoListeningState.listening,
      },
      AutoListeningState.aiSpeaking: {
        AutoListeningState.idle,
        AutoListeningState.listening,
        AutoListeningState.listeningForVoice,
      },
      AutoListeningState.listening: {
        AutoListeningState.userSpeaking,
        AutoListeningState.aiSpeaking,
        AutoListeningState.idle,
      },
      AutoListeningState.userSpeaking: {
        AutoListeningState.processing,
        AutoListeningState.aiSpeaking, // Emergency transition
        AutoListeningState.idle,
      },
      AutoListeningState.processing: {
        AutoListeningState.aiSpeaking,
        AutoListeningState.idle,
        AutoListeningState.listening,
      },
      AutoListeningState.listeningForVoice: {
        AutoListeningState.listening,
        AutoListeningState.aiSpeaking,
        AutoListeningState.idle,
      },
    };

    return validTransitions[from]?.contains(to) ?? false;
  }

  // Update the current state and notify listeners
  void _updateState(AutoListeningState newState) {
    // Validate transition (unless it's the same state)
    final previousState = _currentState;
    final changed = previousState != newState;
    if (changed && !_isValidTransition(previousState, newState)) {
      _logAutoEvent(
        'Blocked transition ${previousState.name} → ${newState.name}',
        emoji: '⚠️',
        trace: true,
      );
      return; // Prevent invalid transitions
    }

    _currentState = newState;
    _stateController.add(_currentState);

    if (changed) {
      BoxLogger.stateChange(
        'AutoListening',
        previousState.name,
        newState.name,
        emoji: '🎤',
        generation: _vadGeneration,
      );
    }

    // VAD FLAPPING FIX: Reset speech session when transitioning to idle or listening
    if (newState == AutoListeningState.idle ||
        newState == AutoListeningState.listening) {
      _inSpeechSession = false;
      if (_vadTraceEnabled && _lastSpeechStartTime != null) {
        _logAutoEvent(
          'Speech session reset',
          trace: true,
          details: {'state': newState.name},
        );
      }
    }
  }

  /// Comprehensive state reset for clean mode transitions
  /// Call this during chat→voice switches to eliminate state contamination
  void reset({bool full = false, bool? preserveAutoMode}) {
    _traceEntryPoint('reset(full: $full, preserveAutoMode: $preserveAutoMode)');
    // ENGINEER FEEDBACK: Keep debug log of generation number for stray callback detection
    final int oldSeq = _speechSeq;
    final bool shouldPreserveAutoMode = preserveAutoMode ?? !full;
    if (kDebugMode) {
      AppLogger.d(
          '🔄 [ALS] reset() full=$full preserveAutoMode=$shouldPreserveAutoMode '
          'seq=$_speechSeq->0 vadRestart=$_vadRestartScheduled '
          'burst=$_speechBurstCount inSession=$_inSpeechSession');
    }

    _cancelAllTimers(reason: 'reset');
    _autoModeEnabledDuringAiAudio = false;
    _invalidateVadGeneration();
    _forceAiAudioIdle();
    _subscribeToAiAudioActivity();

    // Reset speech sequence and timing state
    _speechSeq = 0;

    if (kDebugMode) {
      AppLogger.d(
          '🔄 [ALS] Generation counter reset: $oldSeq -> $_speechSeq (future stray callbacks with seq $oldSeq should be ignored)');
    }
    _speechBurstCount = 0;
    _inSpeechSession = false;
    _lastSpeechStartTime = null;
    _lastSpeechEndTime = null;

    // Clear all guard flags that prevent clean initialization
    _vadRestartScheduled = false;
    _awaitingPlaybackEnd = false;
    _isTransitionInProgress = false;
    _isStoppingRecording = false;
    _hasPendingSpeechEnd = false;

    // Cancel all timers to prevent stale callbacks

    // Reset state to idle for clean start
    _updateState(AutoListeningState.idle);

    if (!shouldPreserveAutoMode) {
      _setAutoModeEnabled(false,
          context: full ? 'reset(full)' : 'reset(partial)');
    }

    // Full reset includes resource cleanup (for session disposal)
    if (full) {
      _isVadActive = false;
      _isRecordingActive = false;

      // Clean up subscriptions
      _startListeningSub?.cancel();
      _startListeningSub = null;
    }

    if (kDebugMode) {
      AppLogger.d('✅ [ALS] reset() completed - state reset to idle');
    }
  }

  // Clean up resources
  @override
  void performDisposal() {
    // Use comprehensive reset with full cleanup
    reset(full: true);
    _aiAudioSourceSub?.cancel();
    _aiAudioSourceSub = null;
    _startListeningSub?.cancel();
    _startListeningSub = null;
    _vadErrorSub?.cancel();
    _vadErrorSub = null;
    _aiAudioActivitySubject.close();

    // Close controllers (fire and forget)
    _autoModeEnabledController.close();
    _stateController.close();
    _errorController.close();
  }

  // Initialize the coordinator
  Future<void> initialize() async {
    _traceEntryPoint('initialize');
    try {
      // Initialize components that need it
      await _vadManager.initialize();
      // Do NOT enable auto mode during initialization
      // It will be enabled explicitly when needed (after TTS)
      _setAutoModeEnabled(false, context: 'initialize');

      if (kDebugMode) {
        debugPrint('🤖 Auto listening coordinator initialized (auto mode OFF)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🤖 Auto listening coordinator initialization error: $e');
      }
    }
  }

  // Explicitly trigger listening to start - can be called from outside
  void triggerListening() {
    // Cancel any post-audio delay when manually triggering listening

    if (_autoModeEnabled &&
        _currentState != AutoListeningState.listeningForVoice) {
      if (kDebugMode) {
        debugPrint('🤖 Auto mode: External trigger to start listening');
      }
      _startListeningAfterDelay();
    } else if (kDebugMode) {
      debugPrint(
          '🤖 Auto mode: External trigger ignored - already listening or auto mode disabled');
    }
  }

  // Called when processing is complete to resume listening
  void onProcessingComplete() {
    if (_autoModeEnabled && _currentState == AutoListeningState.processing) {
      if (kDebugMode) {
        debugPrint(
            '[AutoListeningCoordinator] Processing complete, resuming listening');
      }
      // Transition back to listening state
      _updateState(AutoListeningState.idle);
      _startListeningAfterDelay();
    }
  }

  /// Start listening directly without affecting autoModeEnabled
  /// Used for TTS completion handling to avoid autoMode toggling
  void startListening() {
    if (kDebugMode) {
      debugPrint('[ALC] >>> startListening() called');
    }

    // BYPASS FIX: Check voice mode before starting
    if (isVoiceModeCallback != null && !isVoiceModeCallback!()) {
      if (kDebugMode) {
        debugPrint('[ALC] startListening() rejected – not in voice mode');
      }
      return;
    }

    if (_autoModeEnabled) {
      triggerListening();
    } else {
      if (kDebugMode) {
        debugPrint('[ALC] >>> startListening() ignored - autoMode disabled');
      }
    }
  }

  /// Stop listening directly without affecting autoModeEnabled
  /// Used for TTS start handling to avoid autoMode toggling
  void stopListening() {
    if (kDebugMode) {
      debugPrint('[ALC] <<< stopListening() called');
    }

    if (_autoModeEnabled) {
      _updateState(AutoListeningState.aiSpeaking);
      _stopListeningAndRecording();
    } else {
      if (kDebugMode) {
        debugPrint('[ALC] <<< stopListening() ignored - autoMode disabled');
      }
    }
  }
}

/// States for the automatic listening coordinator
enum AutoListeningState {
  /// Idle, not actively listening or processing
  idle,

  /// AI assistant is currently speaking
  aiSpeaking,

  /// Actively listening for user speech
  listening,

  /// User is speaking and being recorded
  userSpeaking,

  /// Processing user speech after recording
  processing,

  /// Listening for voice input
  listeningForVoice
}
