import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:audio_streamer/audio_streamer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'rnnoise_service.dart';
class EnhancedVADManager {
  static EnhancedVADManager? _instance;
  static int _instanceCounter = 0;
  late final String _vadInstanceId;
  final RNNoiseService _rnnoiseService = RNNoiseService.instance;
  bool _useRNNoise = true;
  bool _rnnoiseInitialized = false;
  StreamSubscription<List<double>>? _audioSubscription;
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeechDetected = false;
  bool _isStreamActive = false;
  bool _isShuttingDown = false;
  bool _isDisposing = false;
  Completer<void>? _shutdownCompleter;
  Completer<void>? _workerDone;
  bool _workerCompletionTracked =
      false; // Prevent multiple completions (hot-reload safe)
  Timer? _operationTimeoutTimer;
  static const Duration _operationTimeout = Duration(seconds: 5);
  double _speechThreshold =
      0.8; // RNNoise VAD confidence threshold (raised from 0.6 to reduce false positives)
  int _speechFrames = 0;
  int _silenceFrames = 0;
  final int _minSpeechFrames =
      5; // VAD FLAPPING FIX: 50ms at 10fps (was 3/30ms) - more stable speech detection
  final int _minSilenceFrames =
      30; // VAD FLAPPING FIX: 300ms at 10fps (was 10/100ms) - prevents brief pauses from ending speech
  static const int _sampleRate = 48000; // RNNoise requires 48kHz
  static const int _frameSize = 480; // 10ms at 48kHz
  final List<double> _audioBuffer = [];
  DateTime? _lastLogTime;
  static const Duration _logThrottleInterval = Duration(seconds: 1);
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
  Stream<double> get amplitudeStream => _amplitudeController.stream;
  factory EnhancedVADManager() {
    _instance ??= EnhancedVADManager._internal();
    return _instance!;
  }
  EnhancedVADManager._internal() {
    _vadInstanceId =
        'VAD_${++_instanceCounter}_${DateTime.now().millisecondsSinceEpoch}';
  }
  Future<void> initialize() async {
    if (_isInitialized || _isDisposing) return;
    try {
      _startOperationTimeout('initialize');
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _errorController
            .add('Microphone permission not granted for Enhanced VAD');
        return;
      }
      try {
        _rnnoiseInitialized = await _rnnoiseService.initialize();
        if (_rnnoiseInitialized) {
        } else {
          _useRNNoise = false;
        }
      } catch (e) {
        _useRNNoise = false;
        _rnnoiseInitialized = false;
      }
      _isInitialized = true;
      _clearOperationTimeout();
    } catch (e) {
      _clearOperationTimeout();
      _errorController.add('Error initializing Enhanced VAD: $e');
    }
  }
  Future<bool> startListening() async {
    if (_isDisposing) {
      return false;
    }
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized || _isDisposing) {
        return false;
      }
    }
    if (_isListening) {
      return true;
    }
    try {
      _startOperationTimeout('startListening');
      _workerDone = Completer<void>();
      _workerCompletionTracked = false;
      bool result;
      if (_useRNNoise && _rnnoiseInitialized) {
        result = await _startRNNoiseVAD();
      } else {
        result = await _startAmplitudeVAD();
      }
      _clearOperationTimeout();
      return result;
    } catch (e) {
      _clearOperationTimeout();
      _errorController.add('Failed to start VAD: $e');
      return false;
    }
  }
  Future<bool> _startRNNoiseVAD() async {
    try {
      if (_isDisposing) {
        return false;
      }
      if (_isShuttingDown) {
        final shutdownCompleted = await _waitForShutdownCompletion();
        if (!shutdownCompleted) {
          return false;
        }
      }
      _isShuttingDown = false;
      try {
        await _rnnoiseService.reset();
      } catch (e) {}
      // CRITICAL: Set sampling rate to 48kHz for RNNoise with native crash protection
      try {
        AudioStreamer().sampleRate =
            _sampleRate; // 48000 Hz as defined in _sampleRate
      } catch (e) {
        return await _fallbackToAmplitudeVAD();
      }
      try {
        _audioSubscription = AudioStreamer().audioStream.listen(
          _processRNNoiseAudioChunk,
          onError: (error) {
            _isStreamActive = false; // Mark stream as inactive on error
            _completeWorkerIfNeeded('RNNoise stream onError');
            _handleStreamError(error);
          },
          onDone: () {
            _isStreamActive = false;
            _completeWorkerIfNeeded('RNNoise stream onDone');
          },
        );
      } catch (e) {
        return await _fallbackToAmplitudeVAD();
      }
      _isListening = true;
      _isStreamActive = true; // Mark stream as active
      _resetVADState();
      return true;
    } catch (e) {
      return await _fallbackToAmplitudeVAD();
    }
  }
  Future<bool> _startAmplitudeVAD() async {
    try {
      if (_isDisposing || _isShuttingDown) {
        return false;
      }
      try {
        AudioStreamer().sampleRate = 16000;
      } catch (e) {
        _errorController.add('Failed to configure audio for amplitude VAD: $e');
        return false;
      }
      try {
        _audioSubscription = AudioStreamer().audioStream.listen(
          _processAmplitudeChunk,
          onError: (error) {
            _completeWorkerIfNeeded('Amplitude stream onError');
            _handleStreamError(error);
          },
          onDone: () {
            _isStreamActive = false;
            _completeWorkerIfNeeded('Amplitude stream onDone');
          },
        );
      } catch (e) {
        _errorController.add('Failed to start amplitude VAD stream: $e');
        return false;
      }
      _isListening = true;
      _isStreamActive = true;
      _resetVADState();
      return true;
    } catch (e) {
      _errorController.add('Failed to start VAD: $e');
      return false;
    }
  }
  void _processAmplitudeChunk(List<double> chunk) {
    if (!_isInitialized ||
        !_isStreamActive ||
        _isShuttingDown ||
        !_isListening ||
        _isDisposing) {
      return; // Exit early to prevent buffer race conditions
    }
    try {
      double sum = 0;
      for (final sample in chunk) {
        sum += sample * sample;
      }
      final rms = sqrt(sum / chunk.length);
      final amplitudeDb = 20 * log(rms + 1e-10) / ln10;
      _amplitudeController.add(amplitudeDb);
      const double speechThresholdDb = -25.0;
      const double silenceThresholdDb = -35.0;
      if (amplitudeDb > speechThresholdDb) {
        _speechFrames++;
        _silenceFrames = 0;
        if (_speechFrames >= _minSpeechFrames && !_isSpeechDetected) {
          _triggerSpeechStart();
        }
      } else if (amplitudeDb < silenceThresholdDb) {
        _silenceFrames++;
        _speechFrames = 0;
        if (_silenceFrames >= _minSilenceFrames && _isSpeechDetected) {
          _triggerSpeechEnd();
        }
      }
    } catch (e) {}
  }
  void _processRNNoiseAudioChunk(List<double> chunk) {
    if (!_isInitialized ||
        !_isStreamActive ||
        _isShuttingDown ||
        !_isListening ||
        _isDisposing) {
      return; // Exit early to prevent buffer race conditions
    }
    try {
      if (chunk.isNotEmpty && _audioBuffer.length < 10000) {
        _audioBuffer.addAll(chunk);
      }
      while (_audioBuffer.length >= _frameSize &&
          _isStreamActive &&
          !_isShuttingDown &&
          !_isDisposing &&
          _isListening) {
        final frame = _audioBuffer.take(_frameSize).toList();
        _audioBuffer.removeRange(0, _frameSize);
        if (_isStreamActive && !_isShuttingDown && !_isDisposing) {
          _processRNNoiseAudioFrame(frame);
        } else {
          break;
        }
      }
    } catch (e) {
      _handleProcessingError(e);
    }
  }
  void _processRNNoiseAudioFrame(List<double> frame) async {
    try {
      final Int16List int16Frame = Int16List(frame.length);
      for (int i = 0; i < frame.length; i++) {
        int16Frame[i] = (frame[i] * 32767.0).round().clamp(-32768, 32767);
      }
      final processedFrame =
          await _rnnoiseService.processAudioFrame(int16Frame);
      if (processedFrame != null) {
        final vadProbability = await _rnnoiseService.getVadProbability();
        final amplitude = _calculateAmplitudeFromInt16(processedFrame);
        _amplitudeController.add(amplitude);
        final dynamicThreshold =
            amplitude < -50.0 ? _speechThreshold + 0.1 : _speechThreshold;
        if (vadProbability > dynamicThreshold) {
          _speechFrames++;
          _silenceFrames = 0;
          if (_speechFrames >= _minSpeechFrames && !_isSpeechDetected) {
            _triggerSpeechStart();
          }
        } else {
          _silenceFrames++;
          _speechFrames = 0;
          if (_silenceFrames >= _minSilenceFrames && _isSpeechDetected) {
            _triggerSpeechEnd();
          }
        }
      } else {
        final amplitude = _calculateAmplitudeFromDoubles(frame);
        final vadProbability = _amplitudeToVADProbability(amplitude);
        _amplitudeController.add(amplitude);
        if (vadProbability > _speechThreshold) {
          _speechFrames++;
          _silenceFrames = 0;
          if (_speechFrames >= _minSpeechFrames && !_isSpeechDetected) {
            _triggerSpeechStart();
          }
        } else {
          _silenceFrames++;
          _speechFrames = 0;
          if (_silenceFrames >= _minSilenceFrames && _isSpeechDetected) {
            _triggerSpeechEnd();
          }
        }
      }
    } catch (e) {}
  }
  double _calculateAmplitudeFromInt16(Int16List frame) {
    double sum = 0;
    for (final sample in frame) {
      sum += sample * sample;
    }
    final rms = sqrt(sum / frame.length);
    return 20 * log(rms / 32767 + 1e-10) / ln10; // Convert to dB
  }
  double _calculateAmplitudeFromDoubles(List<double> frame) {
    double sum = 0;
    for (final sample in frame) {
      sum += sample * sample;
    }
    final rms = sqrt(sum / frame.length);
    return 20 * log(rms + 1e-10) / ln10; // Convert to dB
  }
  double _amplitudeToVADProbability(double amplitudeDb) {
    const double minDb = -60.0;
    const double maxDb = -10.0;
    final normalized = (amplitudeDb - minDb) / (maxDb - minDb);
    return normalized.clamp(0.0, 1.0);
  }
  void _triggerSpeechStart() {
    if (_isSpeechDetected) return;
    _isSpeechDetected = true;
    _speechStartController.add(null);
  }
  void _triggerSpeechEnd() {
    if (!_isSpeechDetected) return;
    _isSpeechDetected = false;
    _speechEndController.add(null);
  }
  Future<bool> _fallbackToAmplitudeVAD() async {
    await _stopRNNoiseVAD();
    _useRNNoise = false;
    return await _startAmplitudeVAD();
  }
  Future<void> _stopRNNoiseVAD() async {
    _shutdownCompleter ??= Completer<void>();
    _isShuttingDown = true;
    _isStreamActive = false;
    if (_audioSubscription != null) {
      await _audioSubscription!.cancel();
      _audioSubscription = null;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _resetVADState();
    _isShuttingDown = false;
    if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
      _shutdownCompleter!.complete();
    }
  }
  Future<void> stopListening() async {
    if (!_isListening || _isShuttingDown) {
      return;
    }
    if (_isDisposing) {
      return;
    }
    _shutdownCompleter = Completer<void>();
    // CRITICAL FIX: Signal shutdown FIRST to stop audio processing immediately
    _isShuttingDown = true;
    _isStreamActive = false;
    _isListening = false; // Set immediately to stop processing
    // CRITICAL FIX: Complete worker future immediately after setting shutdown flags
    _completeWorkerIfNeeded('shutdown signal');
    try {
      _startOperationTimeout('stopListening');
      if (_audioSubscription != null) {
        try {
          unawaited(_audioSubscription!.cancel().catchError((e) {
          }));
        } catch (e) {}
        _audioSubscription = null;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      _isSpeechDetected = false;
      _resetVADState();
      _clearOperationTimeout();
      _isShuttingDown = false;
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
      _workerDone = null;
      _workerCompletionTracked = false;
    } catch (e) {
      _clearOperationTimeout();
      _isSpeechDetected = false;
      _isShuttingDown = false;
      _resetVADState();
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
    }
  }
  void _resetVADState() {
    _speechFrames = 0;
    _silenceFrames = 0;
    _audioBuffer.clear();
  }
  Future<bool> _waitForShutdownCompletion() async {
    if (!_isShuttingDown) {
      return true; // No shutdown in progress
    }
    try {
      if (_shutdownCompleter != null) {
        await _shutdownCompleter!.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _isShuttingDown = false;
            _shutdownCompleter = null;
          },
        );
      }
      if (_isShuttingDown) {
        _isShuttingDown = false;
        _shutdownCompleter = null;
      }
      return true;
    } catch (e) {
      _isShuttingDown = false;
      _shutdownCompleter = null;
      return false;
    }
  }
  void setSpeechThreshold(double threshold) {
    _speechThreshold = threshold.clamp(0.0, 1.0);
  }
  Map<String, dynamic> getConfiguration() {
    return {
      'isInitialized': _isInitialized,
      'isListening': _isListening,
      'isSpeechDetected': _isSpeechDetected,
      'useRNNoise': _useRNNoise,
      'rnnoiseInitialized': _rnnoiseInitialized,
      'speechThreshold': _speechThreshold,
      'sampleRate': _sampleRate,
      'frameSize': _frameSize,
    };
  }
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }
    _isDisposing = true;
    try {
      _clearOperationTimeout();
      await stopListening();
      await Future.delayed(const Duration(milliseconds: 100));
      if (_rnnoiseInitialized) {
        try {
          await _rnnoiseService.dispose();
        } catch (e) {}
        _rnnoiseInitialized = false;
      }
      try {
        await _speechStartController.close();
      } catch (e) {}
      try {
        await _speechEndController.close();
      } catch (e) {}
      try {
        await _errorController.close();
      } catch (e) {}
      try {
        await _amplitudeController.close();
      } catch (e) {}
      _isInitialized = false;
      _useRNNoise = false;
      _isListening = false;
      _isSpeechDetected = false;
      _isStreamActive = false;
      _isShuttingDown = false;
      _resetVADState();
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
      _shutdownCompleter = null;
    } catch (e) {}
  }
  Future<void> waitForWorkerExit() async {
    if (_isListening || _isStreamActive) {
      _isShuttingDown = true;
      _isStreamActive = false;
      _completeWorkerIfNeeded('waitForWorkerExit');
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
  void _completeWorkerIfNeeded(String context) {
    if (!_workerCompletionTracked &&
        _workerDone != null &&
        !_workerDone!.isCompleted) {
      _workerCompletionTracked = true;
      _workerDone!.complete();
    }
  }
  void _startOperationTimeout(String operation) {
    _clearOperationTimeout();
    _operationTimeoutTimer = Timer(_operationTimeout, () {
      _handleOperationTimeout(operation);
    });
  }
  void _clearOperationTimeout() {
    _operationTimeoutTimer?.cancel();
    _operationTimeoutTimer = null;
  }
  void _handleOperationTimeout(String operation) {
    _isStreamActive = false;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _isListening = false;
    _isSpeechDetected = false;
    _resetVADState();
    _isShuttingDown = false;
    if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
      _shutdownCompleter!.complete();
    }
    _errorController.add('VAD operation timeout: $operation');
  }
  void _handleStreamError(dynamic error) {
    _isStreamActive = false;
    if (error is PlatformException) {
      _audioSubscription?.cancel();
      _audioSubscription = null;
      _isListening = false;
      _resetVADState();
      _isShuttingDown = false;
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
    }
    _errorController.add('VAD stream error: $error');
    if (_useRNNoise) {
      _fallbackToAmplitudeVAD();
    }
  }
  void _handleProcessingError(dynamic error) {
    _audioBuffer.clear();
  }
}
