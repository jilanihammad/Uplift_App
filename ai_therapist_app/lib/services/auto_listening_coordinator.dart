import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show unawaited;

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
class AutoListeningCoordinator {
  // Core components
  final AudioPlayerManager _audioPlayerManager;
  final RecordingManager _recordingManager;
  final VoiceService _voiceService;
  
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
    _setupListeners();
  }

  // Safe VAD management with resource tracking
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
      if (kDebugMode) print('[AutoListeningCoordinator] VAD start failed: $e');
      return false;
    }
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
      if (kDebugMode) print('[AutoListeningCoordinator] VAD stop failed: $e');
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
    // Listen for audio playback state changes
    _audioPlayerManager.isPlayingStream.listen((isPlaying) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [AUDIO] isPlayingStream emitted: $isPlaying | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
      }
      if (_autoModeEnabled) {
        if (!isPlaying) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [AUDIO] Playback ended, will check TTS state before listening. isAiSpeaking=${_voiceService.isAiSpeaking}');
          }
          // Only start listening if TTS is also not speaking
          if (!_voiceService.isAiSpeaking) {
            if (kDebugMode)
              print(
                  '[AutoListeningCoordinator] [AUDIO] TTS is not speaking, calling _startListeningAfterDelay()');
            _startListeningAfterDelay();
          } else if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [AUDIO] Not starting listening yet because TTS is still marked as speaking');
          }
        } else {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [AUDIO] Audio playing, stopping listening/recording');
          }
          _stopListeningAndRecording();
          _updateState(AutoListeningState.aiSpeaking);
        }
      } else if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [AUDIO] Ignored isPlayingStream event because autoMode is disabled');
      }
    });

    // Listen for TTS state changes
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
        // TTS started speaking
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [TTS] TTS is speaking, forcing state to aiSpeaking and stopping listening/recording (Step 1: Prevent Self-Listening)');
        }
        // Force state to aiSpeaking every time TTS starts
        _updateState(AutoListeningState.aiSpeaking);
        _stopListeningAndRecording();
      } else {
        // TTS stopped speaking
        if (_currentState == AutoListeningState.aiSpeaking ||
            _currentState == AutoListeningState.idle) {
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [TTS] TTS stopped speaking. Current state $_currentState is suitable for restarting listening. Calling _startListeningAfterDelay().');
          }
          _startListeningAfterDelay();
        } else {
          // This case would include userSpeaking, processing
          if (kDebugMode) {
            print(
                '[AutoListeningCoordinator] [TTS] TTS stopped speaking, but current state is $_currentState. Not automatically restarting listening via this path.');
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
      if (_autoModeEnabled && _currentState == AutoListeningState.listening) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator] [VAD] VAD detected speech start, cancelling speech end timer and starting recording');
        }
        _cancelSpeechEndTimer();
        _startRecording();
      } else if (kDebugMode) {
        print(
            '[AutoListeningCoordinator] [VAD] Ignored onSpeechStart event (autoModeEnabled=$_autoModeEnabled, currentState=$_currentState)');
      }
    });

    // Listen for VAD speech end events
    _vadManager.onSpeechEnd.listen((_) {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] onSpeechEnd event received | autoModeEnabled=$_autoModeEnabled | currentState=$_currentState');
        print(StackTrace.current);
      }
      if (_autoModeEnabled &&
          _currentState == AutoListeningState.userSpeaking) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] Calling _startSpeechEndTimer() after onSpeechEnd');
        }
        _startSpeechEndTimer();
      } else if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] Ignored onSpeechEnd event (autoModeEnabled=$_autoModeEnabled, currentState=$_currentState)');
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

    // SERIALIZE RECORDING STARTUP: Start VAD first and let it settle
    await _safeStartVAD();
    if (kDebugMode) {
      print(
          '[AutoListeningCoordinator] [VAD] VAD listening has started (mic unmuted after TTS)');
    }

    // Wait for VAD to fully initialize before starting recording (prevents dual codec creation)
    await Future.delayed(Duration(milliseconds: 100));
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
            '[AutoListeningCoordinator] [RECORDING] Error starting recording: $e');
      }
    }
  }

  // Start listening for voice activity
  Future<void> _startListening() async {
    if (_currentState == AutoListeningState.idle ||
        _currentState == AutoListeningState.processing) {
      try {
        final success = await _safeStartVAD();
        if (success) {
          _updateState(AutoListeningState.listening);
          if (kDebugMode) {
            print('🎤 AutoListening: Started listening for voice activity');
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

    if (kDebugMode) {
      print(
          '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Starting 1.5s timer. Current state: $_currentState');
      print(StackTrace.current);
    }
    // Wait for silence to be detected for 1.5 seconds before stopping recording
    _speechEndDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (kDebugMode) {
        print(
            '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired. Current state: $_currentState');
        print(StackTrace.current);
      }
      // Only stop recording if still in userSpeaking state
      if (_currentState == AutoListeningState.userSpeaking) {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer firing _stopRecording()');
        }
        _stopRecording();
      } else {
        if (kDebugMode) {
          print(
              '[AutoListeningCoordinator][DEBUG] _startSpeechEndTimer: Timer fired but state is $_currentState, not stopping recording');
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
      if (kDebugMode)
        print(
            '[AutoListeningCoordinator][DEBUG] _isStoppingRecording reset to false');
      _isStoppingRecording = false;
    }
  }

  // Stop both listening and recording
  Future<void> _stopListeningAndRecording() async {
    try {
      // Cancel any pending timers
      _cancelSpeechEndTimer();

      // Stop VAD
      await _safeStopVAD();
      if (kDebugMode) {
        print('🎤 [Step 1] AutoListening: VAD stopped (mic muted during TTS)');
      }

      // Stop recording if currently recording
      if (_currentState == AutoListeningState.userSpeaking) {
        await _stopRecording();
        if (kDebugMode) {
          print(
              '🎤 [Step 1] AutoListening: Recording stopped (mic muted during TTS)');
        }
      }

      if (kDebugMode) {
        print(
            '🎤 [Step 1] AutoListening: Stopped listening and recording (mic fully muted during TTS)');
      }
    } catch (e) {
      _errorController.add('Error stopping listening/recording: $e');
      if (kDebugMode) {
        print('❌ [Step 1] AutoListening stop error: $e');
      }
    }
  }

  // Enable automatic listening mode with explicit audio state from Bloc
  Future<void> enableAutoModeWithAudioState(bool isAudioPlaying) async {
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
    _stuckStateTimer?.cancel();

    // Reset resource tracking flags
    _isVadActive = false;
    _isRecordingActive = false;

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
