import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// Manages voice activity detection (VAD) functionality
///
/// This simplified implementation uses amplitude-based detection
/// to determine when a user starts and stops speaking
class VADManager {
  // Singleton instance
  static VADManager? _instance;

  // Audio recorder for capturing audio levels
  AudioRecorder _recorder = AudioRecorder();

  // Timer for polling amplitude
  Timer? _amplitudeTimer;

  // Amplitude thresholds
  final double _speechStartThreshold =
      -25.0; // dB (higher means more sensitive)
  final double _speechEndThreshold =
      -35.0; // dB (higher means less likely to end)

  // Processing options
  final int _consecutiveLoudFramesRequired =
      2; // More responsive speech detection
  final int _consecutiveQuietFramesRequired = 10; // Faster speech end detection

  // Silence timeouts (ms)
  final int _maxSilenceDuration =
      1500; // Stop recording after this much silence

  // State tracking
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeechDetected = false;
  Timer? _silenceTimer;
  DateTime? _speechStartTime;

  // Debounce timers (to avoid flickering)
  Timer? _speechStartDebounceTimer;
  Timer? _speechEndDebounceTimer;

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

  // Streams for external components to listen to
  Stream<void> get onSpeechStart => _speechStartController.stream;
  Stream<void> get onSpeechEnd => _speechEndController.stream;
  Stream<String> get onError => _errorController.stream;

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

      _isInitialized = true;
      if (kDebugMode) {
        print('🎙️ VAD manager initialized');
      }
    } catch (e) {
      _errorController.add('Error initializing VAD: $e');
      if (kDebugMode) {
        print('❌ VAD initialization error: $e');
      }
    }
  }

  // Start listening for voice activity
  Future<bool> startListening() async {
    if (kDebugMode)
      print(
          '[VADManager] startListening() called. _isInitialized=$_isInitialized, _isListening=$_isListening');
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

    try {
      _recorder = AudioRecorder();
      if (kDebugMode) print('[VADManager] New AudioRecorder instance created.');

      if (kDebugMode)
        print('[VADManager] Requesting temp dir for monitor file');
      // Create a temporary file path for monitoring
      final Directory tempDir = await getTemporaryDirectory();
      final String monitorFilePath =
          '${tempDir.path}/vad_monitor_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (kDebugMode) print('[VADManager] Starting recorder for VAD');
      // Start recording with monitoring mode
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

        // Process the amplitude
        _processAmplitude(level);
      } catch (e) {
        // Ignore errors during amplitude polling
        if (kDebugMode) {
          print('⚠️ VAD amplitude polling error: $e');
        }
      }
    });
  }

  // Process amplitude and detect speech
  void _processAmplitude(double level) {
    if (!_isListening) return;

    if (kDebugMode) {
      // Print every 5 amplitude readings (to avoid flooding the console)
      if (Random().nextInt(5) == 0) {
        print(
            '🎙️ VAD amplitude: $level dB (threshold: $_speechStartThreshold)');
      }
    }

    if (_isSpeechDetected) {
      // Already detecting speech, check if it ended
      if (level < _speechEndThreshold) {
        _consecutiveQuietFrames++;

        if (_consecutiveQuietFrames >= _consecutiveQuietFramesRequired) {
          // Reset counters and update state
          _consecutiveQuietFrames = 0;
          _consecutiveLoudFrames = 0;

          // Only stop if we've recorded for at least 1 second
          final now = DateTime.now();
          final speechDuration = _speechStartTime != null
              ? now.difference(_speechStartTime!).inMilliseconds
              : 0;

          if (speechDuration > 1000) {
            if (kDebugMode) {
              print('🎙️ VAD: Speech ended (duration: ${speechDuration}ms)');
            }
            _stopSpeechDetection();
          } else if (kDebugMode) {
            print(
                '🎙️ VAD: Ignoring brief speech fragment (${speechDuration}ms)');
          }
        }
      } else {
        // Reset quiet frame counter if volume is still loud enough
        _consecutiveQuietFrames = 0;

        // Cancel any active silence timer
        _silenceTimer?.cancel();

        // Start a new silence timer
        _silenceTimer = Timer(Duration(milliseconds: _maxSilenceDuration), () {
          if (_isSpeechDetected) {
            if (kDebugMode) {
              print('🎙️ VAD: Speech ended due to silence timeout');
            }
            _stopSpeechDetection();
          }
        });
      }
    } else {
      // Not yet detecting speech, check if it started
      if (level >= _speechStartThreshold) {
        _consecutiveLoudFrames++;

        if (_consecutiveLoudFrames >= _consecutiveLoudFramesRequired) {
          if (kDebugMode) {
            print('🎙️ VAD: Speech detected! Starting recording');
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

      // Start the max silence timer
      _silenceTimer = Timer(Duration(milliseconds: _maxSilenceDuration), () {
        if (_isSpeechDetected) {
          if (kDebugMode) {
            print('🎙️ VAD: Speech ended due to silence timeout');
          }
          _stopSpeechDetection();
        }
      });
    }
  }

  // Stop speech detection
  void _stopSpeechDetection() {
    if (_isSpeechDetected) {
      if (kDebugMode) {
        print(
            '[VADManager][DEBUG] _stopSpeechDetection: Emitting onSpeechEnd. _isSpeechDetected=$_isSpeechDetected');
        print(StackTrace.current);
      }
      _silenceTimer?.cancel();
      _silenceTimer = null;
      _isSpeechDetected = false;
      _speechEndController.add(null);
    }
  }

  // Cancel all debounce timers
  void _cancelDebounceTimers() {
    _speechStartDebounceTimer?.cancel();
    _speechStartDebounceTimer = null;
    _speechEndDebounceTimer?.cancel();
    _speechEndDebounceTimer = null;
  }

  // Cancel just the speech end timer
  void _cancelSpeechEndTimer() {
    _speechEndDebounceTimer?.cancel();
    _speechEndDebounceTimer = null;
  }

  // Stop listening for voice activity
  Future<void> stopListening() async {
    if (kDebugMode) print('[VADManager] stopListening() called.');
    if (!_isListening) {
      if (kDebugMode) print('[VADManager] Not listening, nothing to stop.');
      return;
    }

    _isListening = false;
    _isSpeechDetected = false;
    _consecutiveLoudFrames = 0;
    _consecutiveQuietFrames = 0;

    _amplitudeTimer?.cancel();
    _silenceTimer?.cancel();
    _speechStartDebounceTimer?.cancel();
    _speechEndDebounceTimer?.cancel();

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
        await _recorder.dispose();
        if (kDebugMode) {
          print('🎙️ VAD: Recorder stopped and disposed.');
        }
      } else {
        // If not recording, still dispose it to be safe for next start
        await _recorder.dispose();
        if (kDebugMode) {
          print(
              '🎙️ VAD: Recorder was not recording, but disposed for safety.');
        }
      }
    } catch (e) {
      _errorController.add('Error stopping/disposing VAD recorder: $e');
      if (kDebugMode) {
        print('❌ VAD recorder stop/dispose error: $e');
      }
    }

    if (kDebugMode) {
      print('🎙️ VAD: Stopped listening for voice activity');
    }
  }

  // Clean up resources
  Future<void> dispose() async {
    try {
      if (_isListening) {
        await stopListening();
      }

      _amplitudeTimer?.cancel();
      _cancelDebounceTimers();

      await _speechStartController.close();
      await _speechEndController.close();
      await _errorController.close();

      if (kDebugMode) {
        print('🎙️ VAD manager disposed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ VAD dispose error: $e');
      }
    }
  }
}
