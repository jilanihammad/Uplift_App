import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:audio_streamer/audio_streamer.dart';
import 'package:permission_handler/permission_handler.dart';

// Import the RNNoise service
import 'rnnoise_service.dart';

/// Enhanced VAD Manager that provides the same interface as VADManager
/// 
/// This is a drop-in replacement that uses RNNoise for better noise filtering
/// while maintaining the exact same interface as the original VADManager.
/// 
/// Purpose: Prevent background noise (cars, AC, TV) from triggering false 
/// speech detection during therapy sessions.
class EnhancedVADManager {
  static EnhancedVADManager? _instance;

  // RNNoise integration
  final RNNoiseService _rnnoiseService = RNNoiseService.instance;
  bool _useRNNoise = true;
  bool _rnnoiseInitialized = false;
  
  // Audio streaming for RNNoise processing
  StreamSubscription<List<double>>? _audioSubscription;
  
  // VAD state
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSpeechDetected = false;
  
  // RNNoise VAD parameters
  double _speechThreshold = 0.6; // RNNoise VAD confidence threshold
  int _speechFrames = 0;
  int _silenceFrames = 0;
  final int _minSpeechFrames = 3; // 30ms at 10fps
  final int _minSilenceFrames = 10; // 100ms at 10fps
  
  // Audio processing parameters
  static const int _sampleRate = 48000; // RNNoise requires 48kHz
  static const int _frameSize = 480; // 10ms at 48kHz
  final List<double> _audioBuffer = [];
  
  // Stream controllers for events (same interface as VADManager)
  final StreamController<void> _speechStartController = StreamController<void>.broadcast();
  final StreamController<void> _speechEndController = StreamController<void>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();

  // Public streams (same interface as VADManager)
  Stream<void> get onSpeechStart => _speechStartController.stream;
  Stream<void> get onSpeechEnd => _speechEndController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<double> get amplitudeStream => _amplitudeController.stream;
  
  // Factory constructor (same as VADManager)
  factory EnhancedVADManager() {
    _instance ??= EnhancedVADManager._internal();
    return _instance!;
  }

  // Private constructor
  EnhancedVADManager._internal();
  
  /// Initialize the enhanced VAD system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _errorController.add('Microphone permission not granted for Enhanced VAD');
        return;
      }
      
      // Try to initialize RNNoise
      try {
        _rnnoiseInitialized = await _rnnoiseService.initialize();
        if (_rnnoiseInitialized) {
          if (kDebugMode) {
            print('🎙️ Enhanced VAD: RNNoise initialized successfully');
          }
        } else {
          if (kDebugMode) {
            print('⚠️ Enhanced VAD: RNNoise initialization failed, using amplitude fallback');
          }
          _useRNNoise = false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Enhanced VAD: RNNoise initialization error: $e, using amplitude fallback');
        }
        _useRNNoise = false;
        _rnnoiseInitialized = false;
      }
      
      _isInitialized = true;
      
      if (kDebugMode) {
        print('🎙️ Enhanced VAD Manager initialized (RNNoise: ${_useRNNoise ? 'ENABLED' : 'DISABLED'})');
      }
    } catch (e) {
      _errorController.add('Error initializing Enhanced VAD: $e');
      if (kDebugMode) {
        print('❌ Enhanced VAD initialization error: $e');
      }
    }
  }
  
  /// Start enhanced voice activity detection
  Future<bool> startListening() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_isListening) {
      if (kDebugMode) print('🎙️ Enhanced VAD already listening');
      return true;
    }
    
    if (_useRNNoise && _rnnoiseInitialized) {
      return await _startRNNoiseVAD();
    } else {
      return await _startAmplitudeVAD();
    }
  }
  
  /// Start RNNoise-based VAD
  Future<bool> _startRNNoiseVAD() async {
    try {
      // Reset RNNoise state for new session
      await _rnnoiseService.reset();
      
      // Set sampling rate for RNNoise (48kHz)
      AudioStreamer().sampleRate = _sampleRate;
      
      // Subscribe to audio stream
      _audioSubscription = AudioStreamer().audioStream.listen(
        _processRNNoiseAudioChunk,
        onError: (error) {
          if (kDebugMode) print('❌ RNNoise VAD stream error: $error');
          _fallbackToAmplitudeVAD();
        },
      );
      
      _isListening = true;
      _resetVADState();
      
      if (kDebugMode) {
        print('🎙️ Enhanced VAD: Started RNNoise-based voice detection');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD: Failed to start RNNoise VAD: $e');
      }
      return await _fallbackToAmplitudeVAD();
    }
  }
  
  /// Start simple amplitude-based VAD (fallback)
  Future<bool> _startAmplitudeVAD() async {
    try {
      // Set sampling rate for amplitude processing (16kHz is fine)
      AudioStreamer().sampleRate = 16000;
      
      _audioSubscription = AudioStreamer().audioStream.listen(
        _processAmplitudeChunk,
        onError: (error) {
          if (kDebugMode) print('❌ Amplitude VAD stream error: $error');
          _errorController.add('VAD stream error: $error');
        },
      );
      
      _isListening = true;
      _resetVADState();
      
      if (kDebugMode) {
        print('🎙️ Enhanced VAD: Started amplitude-based voice detection');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD: Failed to start amplitude VAD: $e');
      }
      _errorController.add('Failed to start VAD: $e');
      return false;
    }
  }
  
  /// Process audio chunk for amplitude-based VAD
  void _processAmplitudeChunk(List<double> chunk) {
    try {
      // Calculate RMS amplitude from normalized samples (-1.0 to 1.0)
      double sum = 0;
      for (final sample in chunk) {
        sum += sample * sample;
      }
      final rms = sqrt(sum / chunk.length);
      final amplitudeDb = 20 * log(rms + 1e-10) / ln10;
      
      // Emit amplitude for UI
      _amplitudeController.add(amplitudeDb);
      
      // Simple threshold-based VAD
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
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD: Amplitude processing error: $e');
      }
    }
  }
  
  /// Process incoming audio chunk with RNNoise
  void _processRNNoiseAudioChunk(List<double> chunk) {
    try {
      // Add samples to buffer
      _audioBuffer.addAll(chunk);
      
      // Process complete frames
      while (_audioBuffer.length >= _frameSize) {
        final frame = _audioBuffer.take(_frameSize).toList();
        _audioBuffer.removeRange(0, _frameSize);
        
        _processRNNoiseAudioFrame(frame);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD: RNNoise audio processing error: $e');
      }
    }
  }
  
  /// Process a single audio frame with RNNoise
  void _processRNNoiseAudioFrame(List<double> frame) async {
    try {
      // Convert normalized samples (-1.0 to 1.0) to Int16 for RNNoise
      final Int16List int16Frame = Int16List(frame.length);
      for (int i = 0; i < frame.length; i++) {
        int16Frame[i] = (frame[i] * 32767).round().clamp(-32768, 32767);
      }
      
      // Process with RNNoise
      final processedFrame = await _rnnoiseService.processAudioFrame(int16Frame);
      
      if (processedFrame != null) {
        // Get VAD probability from RNNoise
        final vadProbability = await _rnnoiseService.getVadProbability();
        
        // Calculate amplitude for UI visualization
        final amplitude = _calculateAmplitudeFromInt16(processedFrame);
        _amplitudeController.add(amplitude);
        
        // Apply hysteresis-based VAD logic using RNNoise probability
        if (vadProbability > _speechThreshold) {
          _speechFrames++;
          _silenceFrames = 0;
          
          // Start speech detection if we have enough consecutive speech frames
          if (_speechFrames >= _minSpeechFrames && !_isSpeechDetected) {
            _triggerSpeechStart();
          }
        } else {
          _silenceFrames++;
          _speechFrames = 0;
          
          // End speech detection if we have enough consecutive silence frames
          if (_silenceFrames >= _minSilenceFrames && _isSpeechDetected) {
            _triggerSpeechEnd();
          }
        }
        
        if (kDebugMode && (vadProbability > 0.1)) {
          print('🎙️ Enhanced VAD (RNNoise): confidence=${vadProbability.toStringAsFixed(3)} | '
                'frames=S$_speechFrames/Sil$_silenceFrames | amp=${amplitude.toStringAsFixed(1)}dB');
        }
      } else {
        // RNNoise processing failed, fall back to amplitude
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
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD: RNNoise frame processing error: $e');
      }
    }
  }
  
  /// Calculate amplitude from Int16 audio frame
  double _calculateAmplitudeFromInt16(Int16List frame) {
    double sum = 0;
    for (final sample in frame) {
      sum += sample * sample;
    }
    final rms = sqrt(sum / frame.length);
    return 20 * log(rms / 32767 + 1e-10) / ln10; // Convert to dB
  }
  
  /// Calculate amplitude from normalized double samples (fallback)
  double _calculateAmplitudeFromDoubles(List<double> frame) {
    double sum = 0;
    for (final sample in frame) {
      sum += sample * sample;
    }
    final rms = sqrt(sum / frame.length);
    return 20 * log(rms + 1e-10) / ln10; // Convert to dB
  }
  
  /// Convert amplitude to VAD probability (fallback for amplitude-based detection)
  double _amplitudeToVADProbability(double amplitudeDb) {
    // Simple conversion for fallback mode
    const double minDb = -60.0;
    const double maxDb = -10.0;
    final normalized = (amplitudeDb - minDb) / (maxDb - minDb);
    return normalized.clamp(0.0, 1.0);
  }
  
  /// Trigger speech start event
  void _triggerSpeechStart() {
    if (_isSpeechDetected) return;
    
    _isSpeechDetected = true;
    _speechStartController.add(null);
    
    if (kDebugMode) {
      print('🗣️ Enhanced VAD: Speech started (${_useRNNoise ? 'RNNoise' : 'Amplitude'})');
    }
  }
  
  /// Trigger speech end event
  void _triggerSpeechEnd() {
    if (!_isSpeechDetected) return;
    
    _isSpeechDetected = false;
    _speechEndController.add(null);
    
    if (kDebugMode) {
      print('🤐 Enhanced VAD: Speech ended (${_useRNNoise ? 'RNNoise' : 'Amplitude'})');
    }
  }
  
  /// Fallback to amplitude-based VAD
  Future<bool> _fallbackToAmplitudeVAD() async {
    if (kDebugMode) {
      print('🔄 Enhanced VAD: Falling back to amplitude-based detection');
    }
    
    await _stopRNNoiseVAD();
    _useRNNoise = false;
    
    return await _startAmplitudeVAD();
  }
  
  /// Stop RNNoise VAD processing
  Future<void> _stopRNNoiseVAD() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _resetVADState();
  }
  
  /// Stop voice activity detection
  Future<void> stopListening() async {
    if (!_isListening) return;
    
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _isListening = false;
    _isSpeechDetected = false;
    _resetVADState();
    
    if (kDebugMode) {
      print('🎙️ Enhanced VAD: Stopped listening');
    }
  }
  
  /// Reset VAD state
  void _resetVADState() {
    _speechFrames = 0;
    _silenceFrames = 0;
    _audioBuffer.clear();
  }
  
  /// Update VAD sensitivity (public API)
  void setSpeechThreshold(double threshold) {
    _speechThreshold = threshold.clamp(0.0, 1.0);
    if (kDebugMode) {
      print('🎙️ Enhanced VAD: Threshold updated to $_speechThreshold');
    }
  }
  
  /// Get current VAD configuration
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
  
  /// Dispose resources
  Future<void> dispose() async {
    await stopListening();
    
    // Dispose RNNoise service
    if (_rnnoiseInitialized) {
      await _rnnoiseService.dispose();
    }
    
    await _speechStartController.close();
    await _speechEndController.close();
    await _errorController.close();
    await _amplitudeController.close();
    
    _isInitialized = false;
    
    if (kDebugMode) {
      print('🎙️ Enhanced VAD: Disposed');
    }
  }
} 