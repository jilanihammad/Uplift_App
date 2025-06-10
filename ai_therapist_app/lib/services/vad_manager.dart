import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import 'path_manager.dart';
import 'recording_manager.dart'; // For SharedRecorderManager

/// Manages voice activity detection (VAD) functionality
///
/// This simplified implementation uses amplitude-based detection
/// to determine when a user starts and stops speaking
class VADManager {
  // Singleton instance
  static VADManager? _instance;

  // Single recorder instance - never null after initialize (Option B)
  late final AudioRecorder _recorder;

  // Timer for polling amplitude
  Timer? _amplitudeTimer;

  // Simple lock for mutual exclusion to prevent race conditions
  bool _operationInProgress = false;

  // Track recorder disposal to prevent double-dispose
  bool _recorderDisposed = false;

  // Amplitude thresholds
  final double _speechStartThreshold =
      -15.0; // dB (higher means more sensitive)
  final double _speechEndThreshold = -25.0; // dB (made less strict - was -45.0)

  // Processing options
  final int _consecutiveLoudFramesRequired =
      2; // More responsive speech detection
  final int _consecutiveQuietFramesRequired =
      10; // Faster speech end detection (was 10)

  // Silence timeouts (ms)
  final int _maxSilenceDuration =
      1500; // Stop recording after this much silence (was 700)

  // State tracking
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeechDetected = false;
  Timer? _silenceTimer;
  DateTime? _speechStartTime;

  // Removed unused debounce timers to avoid confusion

  // Counter for consecutive frames below/above threshold
  int _consecutiveQuietFrames = 0;
  int _consecutiveLoudFrames = 0;

  // Stream controllers
  final StreamController<void> _speechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _speechEndController =
      StreamController<void>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Amplitude stream controller for visualization
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  // Streams for external components to listen to
  Stream<void> get onSpeechStart => _speechStartController.stream;
  Stream<void> get onSpeechEnd => _speechEndController.stream;
  Stream<String> get onError => _errorController.stream;

  // Public debounced amplitude stream for UI visualization
  Stream<double> get amplitudeStream => _amplitudeController.stream
      .throttleTime(const Duration(milliseconds: 120));

  // Factory constructor
  factory VADManager() {
    _instance ??= VADManager._internal();
    return _instance!;
  }

  // Private constructor
  VADManager._internal();

  // Initialize the VAD manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _errorController.add('Microphone permission not granted for VAD');
        return;
      }

      // Create single recorder instance (Option B: Single Recorder Instance)
      _recorder = AudioRecorder();
      _recorderDisposed = false;

      _isInitialized = true;
      if (kDebugMode) {
        print('🎙️ VAD manager initialized with single recorder instance');
      }
    } catch (e) {
      _errorController.add('Error initializing VAD: $e');
      if (kDebugMode) {
        print('❌ VAD initialization error: $e');
      }
    }
  }

  // Start listening for voice activity (Option B: Single Recorder Instance)
  Future<bool> startListening() async {
    if (kDebugMode)
      print(
          '[VADManager] startListening() called. _isInitialized=$_isInitialized, _isListening=$_isListening');

    // Check if RecordingManager is using the recorder
    final sharedRecorder = SharedRecorderManager.instance;
    if (sharedRecorder.isInUse && sharedRecorder.currentUser != 'VADManager') {
      if (kDebugMode) {
        print(
            '🎙️ VAD: Cannot start - recorder in use by ${sharedRecorder.currentUser}');
      }
      return false;
    }

    // Prevent race conditions with simple lock
    if (_operationInProgress) {
      if (kDebugMode) print('[VADManager] Operation in progress, waiting...');
      await Future.delayed(Duration(milliseconds: 10));
      return startListening(); // Retry
    }

    _operationInProgress = true;

    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (_isListening) {
        if (kDebugMode) print('[VADManager] Already listening, returning true');
        if (kDebugMode) {
          print('🎙️ VAD is already listening');
        }
        return true;
      }

      // Option B: Reuse existing recorder instead of creating new one
      if (await _recorder.isRecording()) {
        // Edge case: still recording from previous session - reuse it
        if (kDebugMode)
          print(
              '[VADManager] Recorder still active from previous session, reusing');
        _isListening = true;
        _isSpeechDetected = false;
        _consecutiveLoudFrames = 0;
        _consecutiveQuietFrames = 0;
        _startAmplitudePolling();
        return true;
      }

      // Ensure PathManager is initialized before creating paths
      if (kDebugMode) print('[VADManager] Ensuring PathManager is initialized');
      await PathManager.instance.init();

      if (kDebugMode) print('[VADManager] Creating monitor file path');
      // Create a temporary file path for monitoring
      final String monitorFilePath = PathManager.instance.vadMonitorFile();

      if (kDebugMode)
        print('[VADManager] Starting recorder for VAD (reusing instance)');

      // Register VADManager as the current user for coordination
      await sharedRecorder.requestAccess('VADManager');

      // Start recording with monitoring mode using existing recorder
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
          bitRate: 64000,
        ),
        path: monitorFilePath, // This file will be overwritten each time
      );

      if (kDebugMode)
        print('[VADManager] Recorder started, starting amplitude polling');
      // Start polling amplitude
      _startAmplitudePolling();

      _isListening = true;
      _isSpeechDetected = false;
      _consecutiveLoudFrames = 0;
      _consecutiveQuietFrames = 0;

      if (kDebugMode) {
        print('🎙️ VAD: Started listening for voice activity');
        print('[VADManager] VAD is now listening for voice activity');
      }
      return true;
    } catch (e) {
      _errorController.add('Error starting VAD: $e');
      if (kDebugMode) {
        print('❌ VAD start error: $e');
        print('[VADManager] ERROR in startListening: $e');
      }
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  // Start polling for amplitude values
  void _startAmplitudePolling() {
    // Cancel any existing timer
    _amplitudeTimer?.cancel();

    // Poll amplitude every 100ms (10 times per second)
    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        // Get average amplitude in decibels (dB)
        final amplitude = await _recorder.getAmplitude();
        final double level = amplitude.current ?? -60.0;

        // Emit amplitude for visualization
        _amplitudeController.add(level);

        // Process the amplitude
        _processAmplitude(level);
      } catch (e) {
        // Handle errors during amplitude polling
        if (kDebugMode) {
          print('⚠️ VAD amplitude polling error: $e');
        }
        // For critical errors (permissions, recorder issues), stop gracefully
        if (e.toString().contains('permission') ||
            e.toString().contains('recording') ||
            e.toString().contains('disposed')) {
          if (kDebugMode) {
            print('⚠️ VAD: Critical error, stopping speech detection');
          }
          _stopSpeechDetection().catchError((e2) {
            if (kDebugMode)
              print('⚠️ Error in emergency _stopSpeechDetection: $e2');
          });
        }
      }
    });
  }

  // Process amplitude and detect speech
  void _processAmplitude(double level) {
    if (!_isListening) return;

    if (kDebugMode) {
      // Print every 10 amplitude readings (to avoid flooding the console)
      if (Random().nextInt(10) == 0) {
        print(
            '🎙️ VAD amplitude: $level dB (start threshold: $_speechStartThreshold, end threshold: $_speechEndThreshold, speech detected: $_isSpeechDetected)');
      }
    }

    if (_isSpeechDetected) {
      // Already detecting speech, check if it ended
      if (level < _speechEndThreshold) {
        _consecutiveQuietFrames++;
        _consecutiveLoudFrames = 0; // Reset loud frames when quiet

        if (kDebugMode && _consecutiveQuietFrames % 3 == 0) {
          print(
              '🎙️ VAD: Quiet frames: $_consecutiveQuietFrames/$_consecutiveQuietFramesRequired (level: $level dB)');
        }

        if (_consecutiveQuietFrames >= _consecutiveQuietFramesRequired) {
          // Check minimum speech duration
          final now = DateTime.now();
          final speechDuration = _speechStartTime != null
              ? now.difference(_speechStartTime!).inMilliseconds
              : 0;

          if (speechDuration > 200) {
            // Handle very short utterances (was 800ms, now 200ms for edge cases)
            if (kDebugMode) {
              print(
                  '🎙️ VAD: Speech ended after ${speechDuration}ms (quiet frames)');
            }
            _stopSpeechDetection().catchError((e) {
              if (kDebugMode) print('⚠️ Error in _stopSpeechDetection: $e');
            });
          } else if (kDebugMode) {
            print(
                '🎙️ VAD: Ignoring very brief speech fragment (${speechDuration}ms < 200ms)');
            // Reset counters to continue listening
            _consecutiveQuietFrames = 0;
          }
        }
      } else {
        // Reset quiet frame counter if volume is still loud enough
        if (_consecutiveQuietFrames > 0) {
          if (kDebugMode) {
            print('🎙️ VAD: Speech resumed, resetting quiet frames');
          }
        }
        _consecutiveQuietFrames = 0;
        _consecutiveLoudFrames++;

        // Cancel any active silence timer since we're still speaking
        _silenceTimer?.cancel();

        // Start a new silence timer
        _silenceTimer = Timer(Duration(milliseconds: _maxSilenceDuration), () {
          if (_isSpeechDetected) {
            final speechDuration = _speechStartTime != null
                ? DateTime.now().difference(_speechStartTime!).inMilliseconds
                : 0;
            if (kDebugMode) {
              print(
                  '🎙️ VAD: Speech ended due to silence timeout after ${speechDuration}ms');
            }
            _stopSpeechDetection().catchError((e) {
              if (kDebugMode) print('⚠️ Error in _stopSpeechDetection: $e');
            });
          }
        });
      }
    } else {
      // Not yet detecting speech, check if it started
      if (level >= _speechStartThreshold) {
        _consecutiveLoudFrames++;
        _consecutiveQuietFrames = 0; // Reset quiet frames when loud

        if (_consecutiveLoudFrames >= _consecutiveLoudFramesRequired) {
          if (kDebugMode) {
            print(
                '🎙️ VAD: Speech detected! Starting recording (level: $level dB)');
          }
          _startSpeechDetection();
        }
      } else {
        _consecutiveLoudFrames = 0;
      }
    }
  }

  // Start speech detection
  void _startSpeechDetection() {
    if (!_isSpeechDetected) {
      _isSpeechDetected = true;
      _speechStartTime = DateTime.now();
      _speechStartController.add(null);

      // Note: Silence timer is handled in _processAmplitude, not here
      // This avoids duplicate timers and timer overlap issues
    }
  }

  // Stop speech detection *and* tear down recording
  Future<void> _stopSpeechDetection() async {
    // OPTION ➋: Removed guard condition - always perform full teardown
    // if (!_isSpeechDetected) return;  // <-- REMOVED: This was preventing proper cleanup
    if (kDebugMode) {
      print(
          '[VADManager][DEBUG] _stopSpeechDetection: Tearing down recorder and state (unconditional)');
      print(StackTrace.current);
    }

    // Cancel any queued silence timeouts
    _silenceTimer?.cancel();
    _silenceTimer = null;

    // Stop polling amplitude
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    // Stop the recorder but keep it alive for reuse (Option B: Single Recorder Instance)
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
        if (kDebugMode)
          print(
              '🎙️ VAD: Recorder stopped during speech end (keeping instance alive)');
      }
      // NOTE: No longer disposing recorder here - reuse the instance!
    } catch (e) {
      if (kDebugMode) print('⚠️ Error stopping recorder: $e');
    }

    // Flip all state flags
    _isSpeechDetected = false;
    _isListening = false;
    _consecutiveLoudFrames = 0;
    _consecutiveQuietFrames = 0;

    // Debounce timers removed for simplicity

    if (kDebugMode) {
      print(
          '🎙️ VAD: Complete teardown finished, emitting onSpeechEnd with debounce');
    }

    // Add a tiny post-speech debounce to batch any quick amplitude bounces
    await Future.delayed(Duration(milliseconds: 50));

    // Finally, emit the end event
    _speechEndController.add(null);
  }

  // Removed debounce timer methods (unused)

  // Stop listening for voice activity
  Future<void> stopListening() async {
    if (kDebugMode) print('[VADManager] stopListening() called.');

    // Release access to shared recorder
    SharedRecorderManager.instance.releaseAccess('VADManager');

    // FIX A: Always cancel the amplitude timer FIRST, before any early returns
    // This prevents the "smoking gun" bug where timer keeps running after we think we stopped
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    // Safe-guard: if we haven't even started, nothing to do
    if (!_isListening && !_isSpeechDetected) {
      if (kDebugMode) print('[VADManager] Not listening, nothing to stop.');
      return;
    }

    // Let _stopSpeechDetection handle all the teardown
    await _stopSpeechDetection();

    if (kDebugMode) {
      print('🎙️ VAD: Stopped listening for voice activity');
    }
  }

  // Clean up resources (Option B: Single final disposal)
  Future<void> dispose() async {
    try {
      if (_isListening) {
        await stopListening();
      }

      _amplitudeTimer?.cancel();
      // Debounce timers removed for simplicity

      // OPTION B: Only dispose recorder here, at final cleanup
      if (!_recorderDisposed && _isInitialized) {
        try {
          if (await _recorder.isRecording()) {
            await _recorder.stop();
          }
          await _recorder.dispose();
          _recorderDisposed = true;
          if (kDebugMode) {
            print('🎙️ VAD: Recorder finally disposed during full cleanup');
          }
        } catch (e) {
          if (kDebugMode) print('⚠️ Error disposing recorder: $e');
        }
      }

      await _speechStartController.close();
      await _speechEndController.close();
      await _errorController.close();
      await _amplitudeController.close();

      if (kDebugMode) {
        print('🎙️ VAD manager disposed completely');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ VAD dispose error: $e');
      }
    }
  }
}
