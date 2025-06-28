import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import 'audio_player_manager.dart';
import 'base_voice_service.dart' as base_voice;
import 'recording_manager.dart';
import 'vad_manager.dart';
import 'enhanced_vad_manager.dart';
import 'voice_service.dart';

/// Coordinates automatic voice detection and recording
///
/// Manages the transition between Maya speaking and automatically
/// listening for user input using VAD
///
/// Simplified voice detection and recording coordination
/// Manages the transition between AI speaking and automatically
/// listening for user input using VAD
class AutoListeningCoordinator {
  // Core components
  final AudioPlayerManager _audioPlayerManager;
  final RecordingManager _recordingManager;
  final VoiceService _voiceService;
  
  // NEW: Combined stream for robust AI audio state tracking
  late Stream<bool> _aiAudioActiveStream;
  StreamSubscription<bool>? _startListeningSub;
  
  // VAD configuration - can switch between regular and enhanced VAD
  static bool _useEnhancedVAD = true; // Configuration flag - ENABLED for RNNoise integration
  late final dynamic _vadManager; // Can be VADManager or EnhancedVADManager
  
  // Configuration method to enable/disable Enhanced VAD
  static void setEnhancedVAD(bool enabled) {
    _useEnhancedVAD = enabled;
    if (kDebugMode) {
      print('🎙️ AutoListeningCoordinator: Enhanced VAD ${enabled ? 'ENABLED' : 'DISABLED'}');
    }
  }
  
  static bool get isEnhancedVADEnabled => _useEnhancedVAD;

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

  // Debounce timer for voice activity
  Timer? _speechEndDebounceTimer;

  // Timer to prevent stuck states
  Timer? _stuckStateTimer;

  // NEW: Handle speech events during processing state
  Timer? _pendingSpeechEndTimer;
  bool _hasPendingSpeechEnd = false;
  
  // RACE CONDITION FIX: Monotonic speech sequence counter
  int _speechSeq = 0;

  // Callback for when speech is detected and recording starts
  Function()? onSpeechDetectedCallback;

  // Callback for when recording is stopped due to silence detection
  Function(String audioPath)? onRecordingCompleteCallback;

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
  
  // VAD retry configuration
  static const int _maxVadRetries = 3;
  static const List<int> _retryDelays = [100, 200, 400]; // Exponential backoff in milliseconds

  
  // Constructor
  AutoListeningCoordinator({
    required AudioPlayerManager audioPlayerManager,
    required RecordingManager recordingManager,
    required VoiceService voiceService,
  })  : _audioPlayerManager = audioPlayerManager,
        _recordingManager = recordingManager,
        _voiceService = voiceService {
    // Initialize appropriate VAD manager based on configuration
    if (_useEnhancedVAD) {
      _vadManager = EnhancedVADManager();
      if (kDebugMode) {
        print('🎙️ AutoListeningCoordinator: Using Enhanced VAD Manager');
      }
    } else {
      _vadManager = VADManager();
      if (kDebugMode) {
        print('🎙️ AutoListeningCoordinator: Using Standard VAD Manager');
      }
    }
    
    // NEW: Create combined stream that tracks if AI is making ANY sound
    // This fixes race conditions between TTS generation and audio playback
    _aiAudioActiveStream = Rx.combineLatest2<bool, bool, bool>(
      _audioPlayerManager.isPlayingStream,  // true while audio player outputs sound
      // For now, use VoiceService.isAiSpeaking - TODO: migrate to TTSService stream
      Stream.periodic(const Duration(milliseconds: 100), (_) => _voiceService.isAiSpeaking).distinct(),
      (playing, speaking) => playing || speaking,
    ).distinct();
    
    if (kDebugMode) {
      print('🎙️ AutoListeningCoordinator: Set up combined AI audio stream');
    }
    
    _setupListeners();
  }

  // Safe VAD management with resource tracking and native crash protection
  Future<bool> _safeStartVAD() async {
    if (_isVadActive) {
      if (kDebugMode)
        print('[AutoListeningCoordinator] VAD already active, skipping start');
      return true;
    }
    try {
      final success = await _vadManager.startListening();
      if (success) {
        _isVadActive = true;
        if (kDebugMode)
          print('[AutoListeningCoordinator] VAD started successfully');
      }
      return success;
    } catch (e) {
      if (kDebugMode) print('[AutoListeningCoordinator] CRITICAL: VAD start failed (native crash protection): $e');
      _isVadActive = false; // Ensure state is consistent on failure
      return false;
    }
  }

  // NEW: VAD start with retry mechanism and exponential backoff
  Future<bool> _startVADWithRetry() async {
    if (_isVadActive) {
      if (kDebugMode)
        print('[AutoListeningCoordinator] [RETRY] VAD already active, skipping start');
      return true;
    }

    for (int attempt = 1; attempt <= _maxVadRetries; attempt++) {
      try {
        if (kDebugMode) {
          print('[AutoListeningCoordinator] [RETRY] VAD start attempt $attempt/$_maxVadRetries');
        }
        
        final success = await _vadManager.startListening();
        if (success) {
          _isVadActive = true;
          if (kDebugMode) {
            print('[AutoListeningCoordinator] [RETRY] VAD started successfully on attempt $attempt');
          }
          return true;
        } else {
          if (kDebugMode) {
            print('[AutoListeningCoordinator] [RETRY] VAD start returned false on attempt $attempt');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[AutoListeningCoordinator] [RETRY] VAD start failed on attempt $attempt: $e');
        }
      }

      // If not the last attempt, wait before retrying
      if (attempt < _maxVadRetries) {
        final delayMs = _retryDelays[attempt - 1];
        if (kDebugMode) {
          print('[AutoListeningCoordinator] [RETRY] Waiting ${delayMs}ms before retry ${attempt + 1}');
        }
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    // All retries failed
    _isVadActive = false;
    if (kDebugMode) {
      print('[AutoListeningCoordinator] [RETRY] CRITICAL: All VAD start attempts failed after $_maxVadRetries retries');
    }
    
    // Emit error and transition to idle state
    _errorController.add('VAD startup failed after $_maxVadRetries retry attempts');
    _updateState(AutoListeningState.idle);
    
    return false;
  }

  Future<void> _safeStopVAD() async {
    if (!_isVadActive) {
      if (kDebugMode)
        print('[AutoListeningCoordinator] VAD not active, skipping stop');
      return;
    }
    try {
      await _vadManager.stopListening();
      _isVadActive = false;
      if (kDebugMode)
        print('[AutoListeningCoordinator] VAD stopped successfully');
    } catch (e) {
      if (kDebugMode) print('[AutoListeningCoordinator] CRITICAL: VAD stop failed (native crash protection): $e');
      _isVadActive = false; // Ensure state is consistent even on failure
    }
  }

  // Safe recording management with resource tracking
  Future<void> _safeStartRecording() async {
    if (_isRecordingActive) {
      if (kDebugMode)
        print(
            '[AutoListeningCoordinator] Recording already active, skipping start');
      return;
    }
    try {
      await _recordingManager.startRecording();
      _isRecordingActive = true;
      if (kDebugMode)
        print('[AutoListeningCoordinator] Recording started successfully');
    } catch (e) {
      if (kDebugMode)
        print('[AutoListeningCoordinator] Recording start failed: $e');
    }
  }

  Future<void> _safeStopRecording() async {
    if (!_isRecordingActive) {
      if (kDebugMode)
        print('[AutoListeningCoordinator] Recording not active, skipping stop');
      return;
    }
    try {
      await _recordingManager.stopRecording();
      _isRecordingActive = false;
      if (kDebugMode)
        print('[AutoListeningCoordinator] Recording stopped successfully');
    } catch (e) {
      if (kDebugMode)
        print('[AutoListeningCoordinator] Recording stop failed: $e');
    }
  }

  // Set up listeners for component events
  void _setupListeners() {
    // Listen for audio playback state changes (UI updates only - NO VAD restarts)
    _audioPlayerManager.isPlayingStream.listen((isPlaying) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [AUDIO] isPlayingStream emitted: $isPlaying | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
      }
      if (_autoModeEnabled) {
        if (!isPlaying) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [AUDIO] Playback ended - UI update only (VAD restart handled by TTS completion)');
          }
          // REMOVED: VAD restart logic from audio playback events to prevent race conditions
          // Only update UI state - TTS completion will handle VAD restart
        } else {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [AUDIO] Audio playing, stopping listening/recording and cancelling post-audio delay');
          }
          _stopListeningAndRecording();
          _updateState(AutoListeningState.aiSpeaking);
        }
      } else if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [AUDIO] Ignored isPlayingStream event because autoMode is disabled');
      }
    });

    // Listen for TTS state changes (ONLY path for VAD restart)
    _voiceService.isTtsActuallySpeaking.listen((isSpeaking) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [TTS] isTtsActuallySpeaking emitted: $isSpeaking | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
      }
      if (!_autoModeEnabled) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [TTS] Ignored TTS state change because autoMode is disabled');
        }
        return;
      }

      if (isSpeaking) {
        // TTS started speaking - clear any scheduled VAD restart
        _vadRestartScheduled = false;
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [TTS] TTS is speaking, stopping listening/recording');
        }
        // Force state to aiSpeaking every time TTS starts
        _updateState(AutoListeningState.aiSpeaking);
        _stopListeningAndRecording();
      } else {
        // TTS stopped speaking - ONLY trigger VAD restart from here
        if ((_currentState == AutoListeningState.aiSpeaking ||
            _currentState == AutoListeningState.idle) && !_vadRestartScheduled) {
          if (kDebugMode) {
            print('[AutoListeningCoordinator] [TTS] TTS definitively complete - scheduling VAD restart (single path)');
          }
          _vadRestartScheduled = true;
          _enterAiSpeakingComplete();
        } else {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [TTS] TTS stopped but restart already scheduled or inappropriate state ($_currentState)');
          }
        }
      }
    });

    // Listen for VAD speech start events
    _vadManager.onSpeechStart.listen((_) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] onSpeechStart emitted | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
      }
      if (_autoModeEnabled) {
        // RACE CONDITION FIX: Increment speech sequence on every speech start
        _speechSeq++;
        if (kDebugMode) {
          print('[AutoListeningCoordinator] [RACE-FIX] Speech sequence incremented to $_speechSeq');
        }
        
        if (_currentState == AutoListeningState.listening) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [VAD] VAD detected speech start, cancelling speech end timer and starting recording');
          }
          _cancelSpeechEndTimer();
          
          // CRITICAL FIX: Always transition to userSpeaking, even if recording was already active
          if (!_isRecordingActive) {
            _startRecording();
          } else {
            if (kDebugMode) {
              print('[AutoListeningCoordinator] [VAD] Recording already active, but transitioning to userSpeaking anyway');
            }
          }
          // Always transition to userSpeaking state to prevent endless loop
          _updateState(AutoListeningState.userSpeaking);
          
        } else if (_currentState == AutoListeningState.processing) {
          // CRITICAL FIX: Cancel pending speech end if user resumes speaking
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator][DEBUG] Speech started during processing - cancelling pending stop');
          }
          _cancelPendingSpeechEnd();
        } else if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [VAD] Ignored onSpeechStart event (autoModeEnabled=$_autoModeEnabled, currentState=$_currentState)');
        }
      }
    });

    // Listen for VAD speech end events
    _vadManager.onSpeechEnd.listen((_) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] onSpeechEnd event received | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
        print(StackTrace.current);
      }
      if (_autoModeEnabled) {
        if (_currentState == AutoListeningState.userSpeaking) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator][DEBUG] Calling _startSpeechEndTimer() after onSpeechEnd');
          }
          _startSpeechEndTimer();
        } else if (_currentState == AutoListeningState.processing) {
          // CRITICAL FIX: Handle speech end during processing with debounce
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator][DEBUG] Speech end during processing - scheduling immediate stop with 200ms debounce');
          }
          _handleSpeechEndDuringProcessing();
        } else if (_currentState == AutoListeningState.listening) {
          // CRITICAL FIX: Handle stray recording when stuck in listening state
          if (_isRecordingActive) {
            if (kDebugMode) {
              print(
                  '[AutoListeningCoordinator][DEBUG] Speech ended while in listening state but recording is active - cleaning up stray recording');
            }
            _stopRecording();
          }
        } else if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] Ignored onSpeechEnd event (autoModeEnabled=$_autoModeEnabled, currentState=$_currentState)');
        }
      }
    });

    // Listen for recording state changes
    _recordingManager.recordingStateStream.listen((state) {
      if (kDebugMode) {
        print(
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
    _vadManager.onError.listen((error) {
      _errorController.add('VAD error: $error');
      if (kDebugMode) {
        print('[AutoListeningCoordinator] [VAD] ERROR: $error');
      }
    });
  }

  // NEW: Engineer's robust solution - wait for stable "not busy" state with crash protection
  Future<void> _enterAiSpeakingComplete() async {
    // Safety guard to prevent multiple invocations
    if (_awaitingPlaybackEnd) {
      if (kDebugMode) {
        print('[AutoListeningCoordinator] [ROBUST] Already awaiting playback end, skipping duplicate call');
      }
      return;
    }
    _awaitingPlaybackEnd = true;
    
    // Cancel any previous subscription to prevent race conditions
    _startListeningSub?.cancel();
    
    try {
      // Use await with firstWhere - this returns a Future<bool>, not a StreamSubscription
      await _aiAudioActiveStream.firstWhere((busy) => !busy);
      
      if (_currentState == AutoListeningState.aiSpeaking && _autoModeEnabled && _vadRestartScheduled) {
        if (kDebugMode) {
          print('[AutoListeningCoordinator] [ROBUST] AI audio definitively finished, starting VAD immediately');
        }
        
        // Start VAD immediately without delay
        final vadStarted = await _startVADWithRetry();
        if (vadStarted) {
          await _startListeningAfterDelay();
        } else {
          if (kDebugMode) {
            print('[AutoListeningCoordinator] [ROBUST] VAD restart failed after retries, transitioning to idle');
          }
          _updateState(AutoListeningState.idle);
        }
      } else if (kDebugMode) {
        print('[AutoListeningCoordinator] [ROBUST] State changed, auto mode disabled, or restart not scheduled - skipping VAD start');
      }
    } catch (error) {
      if (kDebugMode) {
        print('[AutoListeningCoordinator] [ROBUST] CRITICAL: Error waiting for AI audio completion (native crash protection): $error');
      }
      // Ensure Maya doesn't get stuck by transitioning to idle on error
      _updateState(AutoListeningState.idle);
    } finally {
      // Always reset the safety guards
      _awaitingPlaybackEnd = false;
      _vadRestartScheduled = false; // Clear restart flag when operation completes
    }
  }

  // Start VAD listening after a short delay
  Future<void> _startListeningAfterDelay() async {
    if (kDebugMode) {
      print(
          '[AutoListeningCoordinator] [VAD] _startListeningAfterDelay called | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
    }

    // Guard against duplicate calls
    if (_isTransitionInProgress) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] Transition already in progress, ignoring duplicate call');
      }
      return;
    }

    // Only allow transition from idle or aiSpeaking states to prevent infinite loops
    if (!(_currentState == AutoListeningState.idle ||
        _currentState == AutoListeningState.aiSpeaking)) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] _startListeningAfterDelay ignored - already in state: $_currentState');
      }
      return;
    }

    // Set transition flag
    _isTransitionInProgress = true;

    try {
      // Update state - use different transition based on current state
      if (_currentState == AutoListeningState.idle) {
        // From idle, go directly to listening (more restrictive transition rules)
        _updateState(AutoListeningState.listening);
        // Start listening immediately without the intermediate listeningForVoice state
        await _executeListeningStart();
        return;
      } else {
        // From aiSpeaking, we can use the intermediate listeningForVoice state
        _updateState(AutoListeningState.listeningForVoice);
      }

      // Cancel any existing stuck state timer
      _stuckStateTimer?.cancel();

      // Set a timer to reset if we get stuck
      _stuckStateTimer = Timer(const Duration(seconds: 1), () {
        if (_currentState == AutoListeningState.listeningForVoice) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [VAD] Stuck in listeningForVoice state, resetting to idle');
          }
          _updateState(AutoListeningState.idle);
          // Try again
          _startListeningAfterDelay();
        }
      });

      // Execute VAD start logic immediately (no Future.delayed)
      if (!_autoModeEnabled) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [VAD] Auto mode disabled, not starting listening');
        }
        _stuckStateTimer?.cancel();
        return;
      }

      // Start listening immediately
      await _executeListeningStart();
    } finally {
      // Always reset the transition flag
      _isTransitionInProgress = false;
    }
  }

  // New method to handle the actual listening start
  Future<void> _executeListeningStart() async {
    if (kDebugMode) {
      print(
          '[AutoListeningCoordinator] [VAD] Starting listening (VAD should be active) | currentState=$_currentState');
    }

    // Only stop playback if something is actually playing
    if (_audioPlayerManager.isPlaying) {
      await _voiceService.stopAudio();
    }

    // SERIALIZE RECORDING STARTUP: Start VAD first and let it settle (with crash protection)
    try {
      // Use retry mechanism for VAD startup
      final vadStarted = await _startVADWithRetry();
      if (!vadStarted) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [VAD] VAD startup failed with retries, aborting listening start');
        }
        return;
      }
      
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] VAD listening has started (mic unmuted after TTS)');
      }

      // VAD should be ready to start recording immediately
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] VAD settled, now starting recording pipeline');
      }

      // Start the actual recording pipeline as well
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [RECORDING] Calling voiceService.startRecording() after VAD start');
      }

      try {
        await _voiceService.startRecording();
        // Transition to listening state now that VAD is active
        _updateState(AutoListeningState.listening);
        // Cancel the stuck state timer since we successfully started
        _stuckStateTimer?.cancel();
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [VAD] Transitioned to listening state');
        }
      } catch (e) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [RECORDING] CRITICAL: Error starting recording (native crash protection): $e');
        }
        // Clean up VAD on recording failure to prevent resource leak
        await _safeStopVAD();
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] CRITICAL: Error in VAD startup sequence (native crash protection): $e');
      }
    }
  }

  // Start listening for voice activity
  Future<void> _startListening() async {
    // Cancel any post-audio delay when starting listening
    
    if (_currentState == AutoListeningState.idle ||
        _currentState == AutoListeningState.processing) {
      try {
        // Use retry mechanism for VAD startup
        final success = await _startVADWithRetry();
        if (success) {
          _updateState(AutoListeningState.listening);
          if (kDebugMode) {
            print('🎤 AutoListening: Started listening for voice activity');
          }
        } else {
          if (kDebugMode) {
            print('❌ AutoListening: VAD startup failed after retries, remaining in current state');
          }
        }
      } catch (e) {
        _errorController.add('Failed to start VAD listening: $e');
        if (kDebugMode) {
          print('❌ AutoListening error: $e');
        }
      }
    }
  }

  // Start the audio recording
  Future<void> _startRecording() async {
    if (_currentState == AutoListeningState.listening) {
      try {
        await _safeStartRecording();

        // Notify listeners that recording has started
        if (onSpeechDetectedCallback != null) {
          onSpeechDetectedCallback!();
        }

        if (kDebugMode) {
          print('🎤 AutoListening: Started recording due to voice activity');
        }
      } catch (e) {
        _errorController.add('Failed to start recording: $e');
        if (kDebugMode) {
          print('❌ AutoListening recording error: $e');
        }
      }
    }
  }

  // Start timer to wait for speech to actually end
  void _startSpeechEndTimer() {
    _cancelSpeechEndTimer(reason: 'Starting new timer');

    // RACE CONDITION FIX: Capture current speech sequence
    final int currentSeq = _speechSeq;
    
    if (kDebugMode) {
      print(
          '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Starting 1.5s timer. Current state: $_currentState, sequence: $currentSeq');
      print(StackTrace.current);
    }
    
    // Wait for silence to be detected for 1.5 seconds before stopping recording
    _speechEndDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired. Current state: $_currentState, timer seq: $currentSeq, current seq: $_speechSeq');
        print(StackTrace.current);
      }
      
      // RACE CONDITION FIX: Only execute if sequence matches (no newer speech detected)
      if (currentSeq == _speechSeq && _currentState == AutoListeningState.userSpeaking) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer firing _stopRecording() (sequence valid)');
        }
        _stopRecording();
      } else {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired but sequence mismatch or invalid state - ignoring (sequence: $currentSeq vs $_speechSeq, state: $_currentState)');
        }
      }
    });
  }

  // Cancel the speech end timer
  void _cancelSpeechEndTimer({String reason = 'unknown'}) {
    if (_speechEndDebounceTimer != null && _speechEndDebounceTimer!.isActive) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] _cancelSpeechEndTimer: Cancelling timer. Reason: $reason | Current state: $_currentState');
        print(StackTrace.current);
      }
      _speechEndDebounceTimer?.cancel();
    }
  }

  // CRITICAL FIX: Handle speech end during processing with immediate response and debounce
  void _handleSpeechEndDuringProcessing() {
    if (kDebugMode) {
      print(
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
      if (_hasPendingSpeechEnd && currentSeq == _speechSeq && _currentState == AutoListeningState.processing) {
        // ENGINEER'S FIX: Only call _stopRecording if actually recording (reduces log noise)
        if (_isRecordingActive) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator][DEBUG] Pending speech end confirmed - stopping recording immediately (sequence: $currentSeq)');
          }
          // Call stopRecording directly - this bypasses the 1.5s timer
          _stopRecording();
        } else if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] Pending speech end confirmed but recording not active - skipping no-op _stopRecording()');
        }
        _hasPendingSpeechEnd = false;
      } else if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] Pending speech end timer fired but conditions not met - ignoring (sequence: $currentSeq vs $_speechSeq, state: $_currentState, hasPending: $_hasPendingSpeechEnd)');
      }
    });
  }

  // CRITICAL FIX: Cancel pending speech end (called when user resumes speaking)
  void _cancelPendingSpeechEnd() {
    if (_pendingSpeechEndTimer != null && _pendingSpeechEndTimer!.isActive) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] _cancelPendingSpeechEnd: User resumed speaking, cancelling pending stop');
      }
      _pendingSpeechEndTimer?.cancel();
    }
    _hasPendingSpeechEnd = false;
  }

  // Stop recording and process the audio
  Future<void> _stopRecording() async {
    if (_isStoppingRecording) {
      if (kDebugMode)
        print(
            '[AutoListeningCoordinator][DEBUG] _stopRecording ignored: already stopping');
      return;
    }
    _isStoppingRecording = true;
    try {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] _stopRecording called. Current state: $_currentState, _isStoppingRecording=$_isStoppingRecording');
        print(StackTrace.current);
      }
      if (_currentState == AutoListeningState.userSpeaking) {
        // CRITICAL FIX: Stop VAD before stopping recording to prevent buffer race (with crash protection)
        try {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator][DEBUG] _stopRecording: Stopping VAD first to prevent buffer race');
          }
          await _vadManager.stopListening();
          _isVadActive = false; // Update state tracking
        } catch (e) {
          if (kDebugMode) {
            print('[AutoListeningCoordinator][DEBUG] CRITICAL: VAD stop error during recording stop (native crash protection): $e');
          }
          _isVadActive = false; // Ensure consistent state even on failure
        }
        
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _stopRecording: About to call _recordingManager.stopRecording()');
        }
        final audioPath = await _recordingManager.stopRecording();

        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _stopRecording: stopRecording() returned path: $audioPath');
        }
        if (audioPath != null && audioPath.isNotEmpty) {
          // Notify listeners that recording has completed
          if (onRecordingCompleteCallback != null) {
            onRecordingCompleteCallback!(audioPath);
          }

          if (kDebugMode) {
            print('🎤 AutoListening: Stopped recording, file at: $audioPath');
          }
        }
        // Cancel backup timer since recording stopped successfully
        _cancelSpeechEndTimer(reason: 'Recording stopped successfully');

        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _stopRecording: About to call _updateState(processing)');
        }
        _updateState(AutoListeningState.processing);
      } else {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _stopRecording called but not in userSpeaking state or already stopping, skipping.');
        }
      }
    } finally {
      // CRITICAL FIX: Always clear recording flag, even on error (engineer's fix)
      _isRecordingActive = false;
      _isStoppingRecording = false;
      if (kDebugMode)
        print(
            '[AutoListeningCoordinator][DEBUG] _isStoppingRecording and _isRecordingActive reset to false');
    }
  }

  // Stop both listening and recording
  Future<void> _stopListeningAndRecording() async {
    try {
      // Cancel any pending timers
      _cancelSpeechEndTimer();

      // CRITICAL FIX: Stop VAD stream FIRST and wait for complete shutdown
      await _safeStopVAD();
      if (kDebugMode) {
        print('🛑 AutoListening: VAD stopped and buffers released');
      }
      
      // Wait briefly for proper cleanup

      // Now safely stop recording
      if (_currentState == AutoListeningState.userSpeaking) {
        await _stopRecording();
        if (kDebugMode) {
          print(
              '🎤 AutoListening: Recording stopped safely after VAD shutdown');
        }
      }

      if (kDebugMode) {
        print(
            '🎤 AutoListening: Complete shutdown sequence finished');
      }
    } catch (e) {
      _errorController.add('Error stopping listening/recording: $e');
      if (kDebugMode) {
        print('❌ AutoListening stop error: $e');
      }
    }
  }

  // Enable automatic listening mode with explicit audio state from Bloc
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
    // Cancel any post-audio delay when manually enabling auto mode
    
    if (!_autoModeEnabled) {
      _autoModeEnabled = true;
      _autoModeEnabledController.add(true);
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [MODE] enableAutoModeWithAudioState called with isAudioPlaying=$isAudioPlaying, autoModeEnabled set to true');
      }

      // Use the audio state provided by the Bloc instead of checking AudioPlayerManager
      if (!isAudioPlaying) {
        if (kDebugMode)
          print(
              '[AutoListeningCoordinator] [MODE] Bloc says audio not playing, calling _startListening()');
        await _startListening();
      } else {
        if (kDebugMode)
          print(
              '[AutoListeningCoordinator] [MODE] Bloc says audio is playing, setting state to aiSpeaking');
        _updateState(AutoListeningState.aiSpeaking);
      }
    } else if (kDebugMode) {
      print(
          '[AutoListeningCoordinator] [MODE] enableAutoModeWithAudioState called, but autoModeEnabled already true');
    }
  }

  // Enable automatic listening mode (original method using AudioPlayerManager)
  Future<void> enableAutoMode() async {
    // Cancel any post-audio delay when manually enabling auto mode
    
    // If we're stuck in listeningForVoice, reset to idle first
    if (_currentState == AutoListeningState.listeningForVoice) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [MODE] enableAutoMode: Resetting from stuck listeningForVoice state to idle');
      }
      _updateState(AutoListeningState.idle);
    }

    if (!_autoModeEnabled) {
      _autoModeEnabled = true;
      _autoModeEnabledController.add(true);
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [MODE] enableAutoMode called, autoModeEnabled set to true');
      }

      // Check audio playing state with detailed logging
      final isAudioPlaying = _audioPlayerManager.isPlaying;
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [MODE] Audio playing state check: isPlaying=$isAudioPlaying');
        print(
            '[AutoListeningCoordinator] [MODE] AudioPlayerManager internal state check...');
      }

      // If AI is not currently speaking, start listening
      if (!isAudioPlaying) {
        if (kDebugMode)
          print(
              '[AutoListeningCoordinator] [MODE] Not playing audio, calling _startListening()');
        await _startListening();
      } else {
        if (kDebugMode)
          print(
              '[AutoListeningCoordinator] [MODE] Audio is playing, setting state to aiSpeaking');
        _updateState(AutoListeningState.aiSpeaking);
      }
    } else if (kDebugMode) {
      print(
          '[AutoListeningCoordinator] [MODE] enableAutoMode called, but autoModeEnabled already true');
    }
  }

  // Disable automatic listening mode
  Future<void> disableAutoMode() async {
    if (_autoModeEnabled) {
      _autoModeEnabled = false;
      _autoModeEnabledController.add(false);
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [MODE] disableAutoMode called, autoModeEnabled set to false');
      }
      // Stop listening and recording
      await _stopListeningAndRecording();
      _updateState(AutoListeningState.idle);
    } else if (kDebugMode) {
      print(
          '[AutoListeningCoordinator] [MODE] disableAutoMode called, but autoModeEnabled already false');
    }
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
    if (newState != _currentState &&
        !_isValidTransition(_currentState, newState)) {
      if (kDebugMode) {
        print(
            '❌ [AutoListeningCoordinator] INVALID TRANSITION: $_currentState → $newState (BLOCKED)');
      }
      return; // Prevent invalid transitions
    }

    if (kDebugMode) {
      if (newState != _currentState) {
        print(
            '✅ [AutoListeningCoordinator] VALID TRANSITION: $_currentState → $newState');
      }
    }
    _currentState = newState;
    _stateController.add(_currentState);
  }

  // Clean up resources
  Future<void> dispose() async {
    _cancelSpeechEndTimer();
    _cancelPendingSpeechEnd();
    _stuckStateTimer?.cancel();

    // Reset resource tracking flags
    _isVadActive = false;
    _isRecordingActive = false;

    // Clean up robust solution subscriptions
    _startListeningSub?.cancel();

    await _autoModeEnabledController.close();
    await _stateController.close();
    await _errorController.close();
  }

  // Initialize the coordinator
  Future<void> initialize() async {
    try {
      // Initialize components that need it
      await _vadManager.initialize();
      // Do NOT enable auto mode during initialization
      // It will be enabled explicitly when needed (after TTS)
      _autoModeEnabled = false;
      _autoModeEnabledController.add(false);

      if (kDebugMode) {
        print('🤖 Auto listening coordinator initialized (auto mode OFF)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🤖 Auto listening coordinator initialization error: $e');
      }
    }
  }

  // Explicitly trigger listening to start - can be called from outside
  void triggerListening() {
    // Cancel any post-audio delay when manually triggering listening
    
    if (_autoModeEnabled &&
        _currentState != AutoListeningState.listeningForVoice) {
      if (kDebugMode) {
        print('🤖 Auto mode: External trigger to start listening');
      }
      _startListeningAfterDelay();
    } else if (kDebugMode) {
      print(
          '🤖 Auto mode: External trigger ignored - already listening or auto mode disabled');
    }
  }

  // Called when processing is complete to resume listening
  void onProcessingComplete() {
    if (_autoModeEnabled && _currentState == AutoListeningState.processing) {
      if (kDebugMode) {
        print(
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
      print('[ALC] >>> startListening() called');
    }
    
    if (_autoModeEnabled) {
      triggerListening();
    } else {
      if (kDebugMode) {
        print('[ALC] >>> startListening() ignored - autoMode disabled');
      }
    }
  }

  /// Stop listening directly without affecting autoModeEnabled  
  /// Used for TTS start handling to avoid autoMode toggling
  void stopListening() {
    if (kDebugMode) {
      print('[ALC] <<< stopListening() called');
    }
    
    if (_autoModeEnabled) {
      _updateState(AutoListeningState.aiSpeaking);
      _stopListeningAndRecording();
    } else {
      if (kDebugMode) {
        print('[ALC] <<< stopListening() ignored - autoMode disabled');
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
