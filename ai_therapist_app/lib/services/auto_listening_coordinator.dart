import 'dart:async';
import 'package:flutter/foundation.dart';

import 'audio_player_manager.dart';
import 'base_voice_service.dart';
import 'recording_manager.dart';
import 'tts_manager.dart';
import 'vad_manager.dart';

/// Coordinates automatic voice detection and recording
///
/// Manages the transition between Maya speaking and automatically
/// listening for user input using VAD
class AutoListeningCoordinator {
  // Core components
  final AudioPlayerManager _audioPlayerManager;
  final RecordingManager _recordingManager;
  final TTSManager _ttsManager;
  final VADManager _vadManager;

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

  // Callback for when speech is detected and recording starts
  Function()? onSpeechDetectedCallback;

  // Callback for when recording is stopped due to silence detection
  Function(String audioPath)? onRecordingCompleteCallback;

  // Constructor
  AutoListeningCoordinator({
    required AudioPlayerManager audioPlayerManager,
    required RecordingManager recordingManager,
    required TTSManager ttsManager,
    required VADManager vadManager,
  })  : _audioPlayerManager = audioPlayerManager,
        _recordingManager = recordingManager,
        _ttsManager = ttsManager,
        _vadManager = vadManager {
    _setupListeners();
  }

  // Set up listeners for component events
  void _setupListeners() {
    // Listen for audio playback state changes
    _audioPlayerManager.isPlayingStream.listen((isPlaying) {
      if (_autoModeEnabled) {
        if (!isPlaying) {
          // Maya finished speaking, start listening for user speech
          if (kDebugMode) {
            print(
                '🤖 Auto mode: Audio playback ended, will start listening after delay');
          }

          // Only start listening if TTS is also not speaking
          // This helps ensure we don't have race conditions
          if (!_ttsManager.isCurrentlySpeaking) {
            _startListeningAfterDelay();
          } else if (kDebugMode) {
            print(
                '🤖 Auto mode: Not starting listening yet because TTS is still marked as speaking');
          }
        } else {
          // Maya is speaking, make sure we're not listening/recording
          if (kDebugMode) {
            print('🤖 Auto mode: Audio playing, stopping listening/recording');
          }
          _stopListeningAndRecording();
          _updateState(AutoListeningState.aiSpeaking);
        }
      }
    });

    // Listen for TTS state changes
    _ttsManager.ttsStateStream.listen((isSpeaking) {
      if (_autoModeEnabled) {
        if (isSpeaking) {
          if (kDebugMode) {
            print(
                '🤖 Auto mode: TTS is speaking, stopping listening/recording');
          }
          _stopListeningAndRecording();
          _updateState(AutoListeningState.aiSpeaking);
        } else if (_currentState == AutoListeningState.aiSpeaking) {
          if (kDebugMode) {
            print(
                '🤖 Auto mode: TTS stopped speaking, will start listening after delay');
          }

          // Force a short delay to ensure everything is settled
          Future.delayed(const Duration(milliseconds: 300), () {
            _startListeningAfterDelay();
          });
        }
      }
    });

    // Listen for VAD speech start events
    _vadManager.onSpeechStart.listen((_) {
      if (_autoModeEnabled && _currentState == AutoListeningState.listening) {
        if (kDebugMode) {
          print('🤖 Auto mode: VAD detected speech start');
        }
        _cancelSpeechEndTimer();

        // Start recording when speech is detected
        _startRecording();
      }
    });

    // Listen for VAD speech end events
    _vadManager.onSpeechEnd.listen((_) {
      if (_autoModeEnabled &&
          _currentState == AutoListeningState.userSpeaking) {
        if (kDebugMode) {
          print('🤖 Auto mode: VAD detected speech end, starting end timer');
        }
        // Debounce the speech end event to avoid cutting off speech too early
        _startSpeechEndTimer();
      }
    });

    // Listen for recording state changes
    _recordingManager.recordingStateStream.listen((state) {
      if (state == RecordingState.recording) {
        _updateState(AutoListeningState.userSpeaking);
      } else if (state == RecordingState.stopped &&
          _currentState == AutoListeningState.userSpeaking) {
        _updateState(AutoListeningState.processing);
      }
    });

    // Error handling
    _vadManager.onError.listen((error) {
      _errorController.add('VAD error: $error');
    });
  }

  // Start VAD listening after a short delay
  void _startListeningAfterDelay() {
    // Short delay to allow for audio playback to fully complete
    if (kDebugMode) {
      print('🤖 Auto mode: Scheduling listening to start after delay');
    }

    // Use a more robust approach to ensure listening starts
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (_autoModeEnabled) {
        if (kDebugMode) {
          print('🤖 Auto mode: Delay completed, now starting listening');
          print('🤖 Auto mode: Current state: $_currentState');
        }

        // Force the state to idle first to ensure clean transition
        if (_currentState == AutoListeningState.aiSpeaking) {
          _updateState(AutoListeningState.idle);
        }

        // Start listening for VAD input
        _updateState(AutoListeningState.listeningForVoice);

        _vadManager.startListening();

        if (kDebugMode) {
          print('🤖 Auto mode: VAD listening has started');
        }
      } else if (kDebugMode) {
        print(
            '🤖 Auto mode: Auto mode disabled during delay, not starting listening');
      }
    });
  }

  // Start listening for voice activity
  Future<void> _startListening() async {
    if (_currentState == AutoListeningState.idle ||
        _currentState == AutoListeningState.processing) {
      try {
        final success = await _vadManager.startListening();
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
        await _recordingManager.startRecording();

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
    _cancelSpeechEndTimer();

    // Wait for silence to be detected for X seconds before stopping recording
    _speechEndDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (_currentState == AutoListeningState.userSpeaking) {
        _stopRecording();
      }
    });
  }

  // Cancel the speech end timer
  void _cancelSpeechEndTimer() {
    _speechEndDebounceTimer?.cancel();
    _speechEndDebounceTimer = null;
  }

  // Stop recording and process the audio
  Future<void> _stopRecording() async {
    if (_currentState == AutoListeningState.userSpeaking) {
      try {
        final audioPath = await _recordingManager.stopRecording();

        if (audioPath.isNotEmpty) {
          // Notify listeners that recording has completed
          if (onRecordingCompleteCallback != null) {
            onRecordingCompleteCallback!(audioPath);
          }

          if (kDebugMode) {
            print('🎤 AutoListening: Stopped recording, file at: $audioPath');
          }
        }
      } catch (e) {
        _errorController.add('Failed to stop recording: $e');
        if (kDebugMode) {
          print('❌ AutoListening stop recording error: $e');
        }
      }
    }
  }

  // Stop both listening and recording
  Future<void> _stopListeningAndRecording() async {
    try {
      // Cancel any pending timers
      _cancelSpeechEndTimer();

      // Stop VAD
      await _vadManager.stopListening();

      // Stop recording if currently recording
      if (_currentState == AutoListeningState.userSpeaking) {
        await _stopRecording();
      }

      if (kDebugMode) {
        print('🎤 AutoListening: Stopped listening and recording');
      }
    } catch (e) {
      _errorController.add('Error stopping listening/recording: $e');
      if (kDebugMode) {
        print('❌ AutoListening stop error: $e');
      }
    }
  }

  // Enable automatic listening mode
  Future<void> enableAutoMode() async {
    if (!_autoModeEnabled) {
      _autoModeEnabled = true;
      _autoModeEnabledController.add(true);

      // If AI is not currently speaking, start listening
      if (!_audioPlayerManager.isPlaying) {
        await _startListening();
      } else {
        _updateState(AutoListeningState.aiSpeaking);
      }

      if (kDebugMode) {
        print('🔄 AutoListening: Automatic mode enabled');
      }
    }
  }

  // Disable automatic listening mode
  Future<void> disableAutoMode() async {
    if (_autoModeEnabled) {
      _autoModeEnabled = false;
      _autoModeEnabledController.add(false);

      // Stop listening and recording
      await _stopListeningAndRecording();
      _updateState(AutoListeningState.idle);

      if (kDebugMode) {
        print('🔄 AutoListening: Automatic mode disabled');
      }
    }
  }

  // Update the current state and notify listeners
  void _updateState(AutoListeningState state) {
    _currentState = state;
    _stateController.add(state);

    if (kDebugMode) {
      print('🔄 AutoListening: State changed to $state');
    }
  }

  // Clean up resources
  Future<void> dispose() async {
    _cancelSpeechEndTimer();
    await _autoModeEnabledController.close();
    await _stateController.close();
    await _errorController.close();
  }

  // Initialize the coordinator
  Future<void> initialize() async {
    try {
      // Initialize components that need it
      await _vadManager.initialize();
      _autoModeEnabled = true;
      _autoModeEnabledController.add(true);

      if (kDebugMode) {
        print('🤖 Auto listening coordinator initialized');
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
