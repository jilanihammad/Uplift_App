import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'path_manager.dart';
import 'recording_manager.dart'; // For SharedRecorderManager
class VADManager {
  static VADManager? _instance;
  late final AudioRecorder _recorder;
  Timer? _amplitudeTimer;
  bool _operationInProgress = false;
  bool _recorderDisposed = false;
  double _speechStartThreshold = -20.0; // dB - will be adjusted
  double _speechEndThreshold = -30.0; // dB - will be adjusted
  double _noiseFloor = -60.0; // Current ambient noise level
  final List<double> _noiseCalibrationSamples = [];
  bool _isCalibrated = false;
  final int _calibrationSamples = 30; // Collect 3 seconds of ambient noise
  Timer? _calibrationTimer;
  final int _consecutiveLoudFramesRequired = 3; // More conservative
  final int _consecutiveQuietFramesRequired = 15; // Require more silence
  final int _maxSilenceDuration = 2500; // Longer timeout for noisy environments
  final double _minSpeechDuration = 500; // Minimum speech length (ms)
  final double _maxNoiseFloor =
      -20.0; // If noise is louder than this, warn user
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeechDetected = false;
  Timer? _silenceTimer;
  DateTime? _speechStartTime;
  int _consecutiveQuietFrames = 0;
  int _consecutiveLoudFrames = 0;
  final StreamController<void> _speechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _speechEndController =
      StreamController<void>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<void> get onSpeechStart => _speechStartController.stream;
  Stream<void> get onSpeechEnd => _speechEndController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<double> get amplitudeStream => _amplitudeController.stream
      .throttleTime(const Duration(milliseconds: 120));
  factory VADManager() {
    _instance ??= VADManager._internal();
    return _instance!;
  }
  VADManager._internal();
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _errorController.add('Microphone permission not granted for VAD');
        return;
      }
      _recorder = AudioRecorder();
      _recorderDisposed = false;
      _isInitialized = true;
    } catch (e) {
      _errorController.add('Error initializing VAD: $e');
    }
  }
  Future<void> _calibrateNoiseFloor() async {
    if (_isCalibrated) return;
    _noiseCalibrationSamples.clear();
    _calibrationTimer?.cancel();
    _calibrationTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_noiseCalibrationSamples.length >= _calibrationSamples) {
        timer.cancel();
        _finalizeCalibraton();
        return;
      }
    });
    Timer(const Duration(seconds: 5), () {
      if (!_isCalibrated) {
        _calibrationTimer?.cancel();
        _finalizeCalibraton();
      }
    });
  }
  void _finalizeCalibraton() {
    if (_noiseCalibrationSamples.isEmpty) {
      _isCalibrated = true;
      return;
    }
    _noiseCalibrationSamples.sort();
    final int quietSamples = (_noiseCalibrationSamples.length * 0.7).round();
    final quietSamplesList =
        _noiseCalibrationSamples.take(quietSamples).toList();
    _noiseFloor =
        quietSamplesList.reduce((a, b) => a + b) / quietSamplesList.length;
    _speechStartThreshold =
        _noiseFloor + 10.0; // Speech must be 10dB above noise
    _speechEndThreshold = _noiseFloor + 5.0; // End when within 5dB of noise
    _speechStartThreshold = _speechStartThreshold.clamp(-35.0, -10.0);
    _speechEndThreshold = _speechEndThreshold.clamp(-45.0, -15.0);
    _isCalibrated = true;
  }
  Future<bool> startListening() async {
    final sharedRecorder = SharedRecorderManager.instance;
    if (sharedRecorder.isInUse && sharedRecorder.currentUser != 'VADManager') {
      return false;
    }
    if (_operationInProgress) {
      await Future.delayed(const Duration(milliseconds: 10));
      return startListening(); // Retry
    }
    _operationInProgress = true;
    try {
      if (!_isInitialized) {
        await initialize();
      }
      if (_isListening) {
        return true;
      }
      if (await _recorder.isRecording()) {
        _isListening = true;
        _isSpeechDetected = false;
        _consecutiveLoudFrames = 0;
        _consecutiveQuietFrames = 0;
        _startAmplitudePolling();
        return true;
      }
      await PathManager.instance.init();
      final String monitorFilePath = PathManager.instance.vadMonitorFile();
      await sharedRecorder.requestAccess('VADManager');
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 16000,
          bitRate: 64000,
        ),
        path: monitorFilePath, // This file will be overwritten each time
      );
      _startAmplitudePolling();
      if (!_isCalibrated) {
        _calibrateNoiseFloor();
      }
      _isListening = true;
      _isSpeechDetected = false;
      _consecutiveLoudFrames = 0;
      _consecutiveQuietFrames = 0;
      return true;
    } catch (e) {
      _errorController.add('Error starting VAD: $e');
      return false;
    } finally {
      _operationInProgress = false;
    }
  }
  void _startAmplitudePolling() {
    _amplitudeTimer?.cancel();
    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final amplitude = await _recorder.getAmplitude();
        final double level = amplitude.current ?? -60.0;
        if (!_isCalibrated &&
            _calibrationTimer != null &&
            _calibrationTimer!.isActive) {
          _noiseCalibrationSamples.add(level);
        }
        _amplitudeController.add(level);
        if (_isCalibrated) {
          _processAmplitude(level);
        }
      } catch (e) {
        if (e.toString().contains('permission') ||
            e.toString().contains('recording') ||
            e.toString().contains('disposed')) {
          _stopSpeechDetection().catchError((e2) {
          });
        }
      }
    });
  }
  void _processAmplitude(double level) {
    if (!_isListening) return;
    if (_isSpeechDetected) {
      if (level < _speechEndThreshold) {
        _consecutiveQuietFrames++;
        _consecutiveLoudFrames = 0; // Reset loud frames when quiet
        if (_consecutiveQuietFrames >= _consecutiveQuietFramesRequired) {
          final now = DateTime.now();
          final speechDuration = _speechStartTime != null
              ? now.difference(_speechStartTime!).inMilliseconds
              : 0;
          if (speechDuration > _minSpeechDuration) {
            _stopSpeechDetection().catchError((e) {
            });
          } else if (kDebugMode) {
            debugPrint(
                '🎙️ VAD: Ignoring brief speech fragment (${speechDuration}ms < ${_minSpeechDuration}ms)');
            _consecutiveQuietFrames = 0;
          }
        }
      } else {
        if (_consecutiveQuietFrames > 0) {
        }
        _consecutiveQuietFrames = 0;
        _consecutiveLoudFrames++;
        _silenceTimer?.cancel();
        _silenceTimer = Timer(Duration(milliseconds: _maxSilenceDuration), () {
          if (_isSpeechDetected) {
            final speechDuration = _speechStartTime != null
                ? DateTime.now().difference(_speechStartTime!).inMilliseconds
                : 0;
            _stopSpeechDetection().catchError((e) {
            });
          }
        });
      }
    } else {
      if (level >= _speechStartThreshold) {
        _consecutiveLoudFrames++;
        _consecutiveQuietFrames = 0; // Reset quiet frames when loud
        if (_consecutiveLoudFrames >= _consecutiveLoudFramesRequired) {
          _startSpeechDetection();
        }
      } else {
        _consecutiveLoudFrames = 0;
      }
    }
  }
  void _startSpeechDetection() {
    if (!_isSpeechDetected) {
      _isSpeechDetected = true;
      _speechStartTime = DateTime.now();
      _speechStartController.add(null);
      // Note: Silence timer is handled in _processAmplitude, not here
    }
  }
  Future<void> _stopSpeechDetection() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      // NOTE: No longer disposing recorder here - reuse the instance!
    } catch (e) {}
    _isSpeechDetected = false;
    _isListening = false;
    _consecutiveLoudFrames = 0;
    _consecutiveQuietFrames = 0;
    await Future.delayed(const Duration(milliseconds: 50));
    _speechEndController.add(null);
  }
  Future<void> stopListening() async {
    SharedRecorderManager.instance.releaseAccess('VADManager');
    // FIX A: Always cancel the amplitude timer FIRST, before any early returns
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    if (!_isListening && !_isSpeechDetected) {
      return;
    }
    await _stopSpeechDetection();
  }
  void resetCalibration() {
    _isCalibrated = false;
    _noiseCalibrationSamples.clear();
    _calibrationTimer?.cancel();
    _noiseFloor = -60.0;
    _speechStartThreshold = -20.0;
    _speechEndThreshold = -30.0;
  }
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
  Future<void> dispose() async {
    try {
      if (_isListening) {
        await stopListening();
      }
      _amplitudeTimer?.cancel();
      _calibrationTimer?.cancel();
      if (!_recorderDisposed && _isInitialized) {
        try {
          if (await _recorder.isRecording()) {
            await _recorder.stop();
          }
          await _recorder.dispose();
          _recorderDisposed = true;
        } catch (e) {}
      }
      await _speechStartController.close();
      await _speechEndController.close();
      await _errorController.close();
      await _amplitudeController.close();
    } catch (e) {}
  }
}
