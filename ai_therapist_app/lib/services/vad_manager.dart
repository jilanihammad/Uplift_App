import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import 'path_manager.dart';
import 'recording_manager.dart'; // For SharedRecorderManager
import '../utils/logging_config.dart';
import '../utils/app_logger.dart';

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

  // Adaptive amplitude thresholds (will be calibrated based on ambient noise)
  double _speechStartThreshold = -20.0; // dB - will be adjusted
  double _speechEndThreshold = -30.0; // dB - will be adjusted

  // Noise floor tracking for adaptive thresholds
  double _noiseFloor = -60.0; // Current ambient noise level
  final List<double> _noiseCalibrationSamples = [];
  bool _isCalibrated = false;
  final int _calibrationSamples = 30; // Collect 3 seconds of ambient noise
  Timer? _calibrationTimer;

  // Enhanced processing options
  final int _consecutiveLoudFramesRequired = 3; // More conservative
  final int _consecutiveQuietFramesRequired = 15; // Require more silence

  // Silence timeouts (ms)
  final int _maxSilenceDuration = 2500; // Longer timeout for noisy environments

  // Signal quality thresholds
  final double _minSpeechDuration = 500; // Minimum speech length (ms)
  final double _maxNoiseFloor =
      -20.0; // If noise is louder than this, warn user

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
        AppLogger.d(
            'VAD: VAD manager initialized with single recorder instance');
      }
    } catch (e) {
      _errorController.add('Error initializing VAD: $e');
      if (kDebugMode) {
        debugPrint('❌ VAD initialization error: $e');
      }
    }
  }

  // Calibrate noise floor by sampling ambient noise
  Future<void> _calibrateNoiseFloor() async {
    if (_isCalibrated) return;

    if (kDebugMode) {
      AppLogger.d('VAD: VAD: Starting noise floor calibration...');
    }

    _noiseCalibrationSamples.clear();
    _calibrationTimer?.cancel();

    // Collect samples for calibration
    _calibrationTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_noiseCalibrationSamples.length >= _calibrationSamples) {
        timer.cancel();
        _finalizeCalibraton();
        return;
      }

      // This will be populated by amplitude polling
    });

    // Timeout calibration after 5 seconds
    Timer(const Duration(seconds: 5), () {
      if (!_isCalibrated) {
        _calibrationTimer?.cancel();
        _finalizeCalibraton();
      }
    });
  }

  // Finalize noise calibration and set adaptive thresholds
  void _finalizeCalibraton() {
    if (_noiseCalibrationSamples.isEmpty) {
      if (kDebugMode) {
        AppLogger.d(
            'VAD: VAD: No calibration samples, using default thresholds');
      }
      _isCalibrated = true;
      return;
    }

    // Calculate noise floor (average of quietest 70% of samples)
    _noiseCalibrationSamples.sort();
    final int quietSamples = (_noiseCalibrationSamples.length * 0.7).round();
    final quietSamplesList =
        _noiseCalibrationSamples.take(quietSamples).toList();
    _noiseFloor =
        quietSamplesList.reduce((a, b) => a + b) / quietSamplesList.length;

    // Set adaptive thresholds based on noise floor
    _speechStartThreshold =
        _noiseFloor + 10.0; // Speech must be 10dB above noise
    _speechEndThreshold = _noiseFloor + 5.0; // End when within 5dB of noise

    // Safety bounds
    _speechStartThreshold = _speechStartThreshold.clamp(-35.0, -10.0);
    _speechEndThreshold = _speechEndThreshold.clamp(-45.0, -15.0);

    _isCalibrated = true;

    if (kDebugMode) {
      AppLogger.d('VAD: VAD: Calibration complete!');
      debugPrint('  Noise floor: ${_noiseFloor.toStringAsFixed(1)} dB');
      debugPrint(
          '  Speech start threshold: ${_speechStartThreshold.toStringAsFixed(1)} dB');
      debugPrint(
          '  Speech end threshold: ${_speechEndThreshold.toStringAsFixed(1)} dB');

      if (_noiseFloor > _maxNoiseFloor) {
        debugPrint(
            '⚠️ VAD: Environment is very noisy (${_noiseFloor.toStringAsFixed(1)} dB). Consider finding a quieter location.');
      }
    }
  }

  // Start listening for voice activity (Option B: Single Recorder Instance)
  Future<bool> startListening() async {
    if (kDebugMode) {
      debugPrint(
          '[VADManager] startListening() called. _isInitialized=$_isInitialized, _isListening=$_isListening');
    }

    // Check if RecordingManager is using the recorder
    final sharedRecorder = SharedRecorderManager.instance;
    if (sharedRecorder.isInUse && sharedRecorder.currentUser != 'VADManager') {
      if (kDebugMode) {
        debugPrint(
            '🎙️ VAD: Cannot start - recorder in use by ${sharedRecorder.currentUser}');
      }
      return false;
    }

    // Prevent race conditions with simple lock
    if (_operationInProgress) {
      if (kDebugMode) debugPrint('[VADManager] Operation in progress, waiting...');
      await Future.delayed(const Duration(milliseconds: 10));
      return startListening(); // Retry
    }

    _operationInProgress = true;

    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (_isListening) {
        if (kDebugMode) debugPrint('[VADManager] Already listening, returning true');
        if (kDebugMode) {
          AppLogger.d('VAD: VAD is already listening');
        }
        return true;
      }

      // Option B: Reuse existing recorder instead of creating new one
      if (await _recorder.isRecording()) {
        // Edge case: still recording from previous session - reuse it
        if (kDebugMode) {
          debugPrint(
              '[VADManager] Recorder still active from previous session, reusing');
        }
        _isListening = true;
        _isSpeechDetected = false;
        _consecutiveLoudFrames = 0;
        _consecutiveQuietFrames = 0;
        _startAmplitudePolling();
        return true;
      }

      // Ensure PathManager is initialized before creating paths
      if (kDebugMode) debugPrint('[VADManager] Ensuring PathManager is initialized');
      await PathManager.instance.init();

      if (kDebugMode) debugPrint('[VADManager] Creating monitor file path');
      // Create a temporary file path for monitoring
      final String monitorFilePath = PathManager.instance.vadMonitorFile();

      if (kDebugMode) {
        debugPrint('[VADManager] Starting recorder for VAD (reusing instance)');
      }

      // Register VADManager as the current user for coordination
      await sharedRecorder.requestAccess('VADManager');

      // Start recording with monitoring mode using existing recorder
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
          bitRate: 64000,
        ),
        path: monitorFilePath, // This file will be overwritten each time
      );

      if (kDebugMode) {
        debugPrint('[VADManager] Recorder started, starting amplitude polling');
      }

      // Start polling amplitude
      _startAmplitudePolling();

      // Start noise calibration if not already done
      if (!_isCalibrated) {
        _calibrateNoiseFloor();
      }

      _isListening = true;
      _isSpeechDetected = false;
      _consecutiveLoudFrames = 0;
      _consecutiveQuietFrames = 0;

      if (kDebugMode) {
        AppLogger.d('VAD: VAD: Started listening for voice activity');
        debugPrint('[VADManager] VAD is now listening for voice activity');
      }
      return true;
    } catch (e) {
      _errorController.add('Error starting VAD: $e');
      if (kDebugMode) {
        debugPrint('❌ VAD start error: $e');
        debugPrint('[VADManager] ERROR in startListening: $e');
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

        // Collect calibration samples if not yet calibrated
        if (!_isCalibrated &&
            _calibrationTimer != null &&
            _calibrationTimer!.isActive) {
          _noiseCalibrationSamples.add(level);
        }

        // Emit amplitude for visualization
        _amplitudeController.add(level);

        // Only process for speech detection if calibrated
        if (_isCalibrated) {
          _processAmplitude(level);
        }
      } catch (e) {
        // Handle errors during amplitude polling
        if (kDebugMode) {
          debugPrint('⚠️ VAD amplitude polling error: $e');
        }
        // For critical errors (permissions, recorder issues), stop gracefully
        if (e.toString().contains('permission') ||
            e.toString().contains('recording') ||
            e.toString().contains('disposed')) {
          if (kDebugMode) {
            debugPrint('⚠️ VAD: Critical error, stopping speech detection');
          }
          _stopSpeechDetection().catchError((e2) {
            if (kDebugMode) {
              debugPrint('⚠️ Error in emergency _stopSpeechDetection: $e2');
            }
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
        debugPrint(
            '🎙️ VAD amplitude: $level dB (start threshold: $_speechStartThreshold, end threshold: $_speechEndThreshold, speech detected: $_isSpeechDetected)');
      }
    }

    if (_isSpeechDetected) {
      // Already detecting speech, check if it ended
      if (level < _speechEndThreshold) {
        _consecutiveQuietFrames++;
        _consecutiveLoudFrames = 0; // Reset loud frames when quiet

        if (kDebugMode && _consecutiveQuietFrames % 3 == 0) {
          debugPrint(
              '🎙️ VAD: Quiet frames: $_consecutiveQuietFrames/$_consecutiveQuietFramesRequired (level: $level dB)');
        }

        if (_consecutiveQuietFrames >= _consecutiveQuietFramesRequired) {
          // Check minimum speech duration
          final now = DateTime.now();
          final speechDuration = _speechStartTime != null
              ? now.difference(_speechStartTime!).inMilliseconds
              : 0;

          if (speechDuration > _minSpeechDuration) {
            // Only end speech if it's been long enough
            if (kDebugMode) {
              debugPrint(
                  '🎙️ VAD: Speech ended after ${speechDuration}ms (quiet frames)');
            }
            _stopSpeechDetection().catchError((e) {
              if (kDebugMode) debugPrint('⚠️ Error in _stopSpeechDetection: $e');
            });
          } else if (kDebugMode) {
            debugPrint(
                '🎙️ VAD: Ignoring brief speech fragment (${speechDuration}ms < ${_minSpeechDuration}ms)');
            // Reset counters to continue listening
            _consecutiveQuietFrames = 0;
          }
        }
      } else {
        // Reset quiet frame counter if volume is still loud enough
        if (_consecutiveQuietFrames > 0) {
          if (kDebugMode) {
            AppLogger.d('VAD: VAD: Speech resumed, resetting quiet frames');
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
              debugPrint(
                  '🎙️ VAD: Speech ended due to silence timeout after ${speechDuration}ms');
            }
            _stopSpeechDetection().catchError((e) {
              if (kDebugMode) debugPrint('⚠️ Error in _stopSpeechDetection: $e');
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
            debugPrint(
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
      debugPrint(
          '[VADManager][DEBUG] _stopSpeechDetection: Tearing down recorder and state (unconditional)');
      if (loggingConfig.isVerboseDebugEnabled) {
        debugPrint(StackTrace.current.toString());
      }
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
        if (kDebugMode) {
          debugPrint(
              '🎙️ VAD: Recorder stopped during speech end (keeping instance alive)');
        }
      }
      // NOTE: No longer disposing recorder here - reuse the instance!
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error stopping recorder: $e');
    }

    // Flip all state flags
    _isSpeechDetected = false;
    _isListening = false;
    _consecutiveLoudFrames = 0;
    _consecutiveQuietFrames = 0;

    // Debounce timers removed for simplicity

    if (kDebugMode) {
      debugPrint(
          '🎙️ VAD: Complete teardown finished, emitting onSpeechEnd with debounce');
    }

    // Add a tiny post-speech debounce to batch any quick amplitude bounces
    await Future.delayed(const Duration(milliseconds: 50));

    // Finally, emit the end event
    _speechEndController.add(null);
  }

  // Removed debounce timer methods (unused)

  // Stop listening for voice activity
  Future<void> stopListening() async {
    if (kDebugMode) debugPrint('[VADManager] stopListening() called.');

    // Release access to shared recorder
    SharedRecorderManager.instance.releaseAccess('VADManager');

    // FIX A: Always cancel the amplitude timer FIRST, before any early returns
    // This prevents the "smoking gun" bug where timer keeps running after we think we stopped
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;

    // Safe-guard: if we haven't even started, nothing to do
    if (!_isListening && !_isSpeechDetected) {
      if (kDebugMode) debugPrint('[VADManager] Not listening, nothing to stop.');
      return;
    }

    // Let _stopSpeechDetection handle all the teardown
    await _stopSpeechDetection();

    if (kDebugMode) {
      AppLogger.d('VAD: VAD: Stopped listening for voice activity');
    }
  }

  // Reset calibration (useful when environment changes)
  void resetCalibration() {
    _isCalibrated = false;
    _noiseCalibrationSamples.clear();
    _calibrationTimer?.cancel();
    _noiseFloor = -60.0;
    _speechStartThreshold = -20.0;
    _speechEndThreshold = -30.0;

    if (kDebugMode) {
      AppLogger.d(
          'VAD: VAD: Calibration reset - will recalibrate on next session');
    }
  }

  // Get current noise environment info (for debugging/UI feedback)
  Map<String, dynamic> getNoiseInfo() {
    return {
      'isCalibrated': _isCalibrated,
      'noiseFloor': _noiseFloor,
      'speechStartThreshold': _speechStartThreshold,
      'speechEndThreshold': _speechEndThreshold,
      'isVeryNoisy': _noiseFloor > _maxNoiseFloor,
      'isCalibrating': _calibrationTimer?.isActive ?? false,
    };
  }

  // Clean up resources (Option B: Single final disposal)
  Future<void> dispose() async {
    try {
      if (_isListening) {
        await stopListening();
      }

      _amplitudeTimer?.cancel();
      _calibrationTimer?.cancel();

      // OPTION B: Only dispose recorder here, at final cleanup
      if (!_recorderDisposed && _isInitialized) {
        try {
          if (await _recorder.isRecording()) {
            await _recorder.stop();
          }
          await _recorder.dispose();
          _recorderDisposed = true;
          if (kDebugMode) {
            AppLogger.d(
                'VAD: VAD: Recorder finally disposed during full cleanup');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Error disposing recorder: $e');
        }
      }

      await _speechStartController.close();
      await _speechEndController.close();
      await _errorController.close();
      await _amplitudeController.close();

      if (kDebugMode) {
        AppLogger.d('VAD: VAD manager disposed completely');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ VAD dispose error: $e');
      }
    }
  }
}
