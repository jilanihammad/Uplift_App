import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audio_streamer/audio_streamer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ai_therapist_app/utils/app_logger.dart';

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

  // Instance tracking for crash protection
  static int _instanceCounter = 0;
  late final String _vadInstanceId;
  
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
  
  // Enhanced lifecycle tracking to prevent crashes
  bool _isStreamActive = false;
  bool _isShuttingDown = false;
  bool _isDisposing = false;
  
  // Shutdown completion tracking for race condition prevention
  Completer<void>? _shutdownCompleter;
  
  // RACE CONDITION FIX: Worker thread completion tracking
  // Single-shot completer to ensure AudioRecord.read() has exited before release()
  Completer<void>? _workerDone;
  bool _workerCompletionTracked = false; // Prevent multiple completions (hot-reload safe)
  
  // Operation timeout protection
  Timer? _operationTimeoutTimer;
  static const Duration _operationTimeout = Duration(seconds: 5);
  
  // RNNoise VAD parameters
  double _speechThreshold = 0.8; // RNNoise VAD confidence threshold (raised from 0.6 to reduce false positives)
  int _speechFrames = 0;
  int _silenceFrames = 0;
  final int _minSpeechFrames = 5; // VAD FLAPPING FIX: 50ms at 10fps (was 3/30ms) - more stable speech detection
  final int _minSilenceFrames = 30; // VAD FLAPPING FIX: 300ms at 10fps (was 10/100ms) - prevents brief pauses from ending speech
  
  // Audio processing parameters
  static const int _sampleRate = 48000; // RNNoise requires 48kHz
  static const int _frameSize = 480; // 10ms at 48kHz
  final List<double> _audioBuffer = [];
  
  // Log throttling to reduce spam (max 1 log per second)
  DateTime? _lastLogTime;
  static const Duration _logThrottleInterval = Duration(seconds: 1);
  
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
  EnhancedVADManager._internal() {
    _vadInstanceId = 'VAD_${++_instanceCounter}_${DateTime.now().millisecondsSinceEpoch}';
    if (kDebugMode) {
      AppLogger.d(' Enhanced VAD: Created instance $_vadInstanceId');
    }
  }
  
  /// Initialize the enhanced VAD system
  Future<void> initialize() async {
    if (_isInitialized || _isDisposing) return;
    
    if (kDebugMode) {
      AppLogger.d(' Enhanced VAD ($_vadInstanceId): Starting initialization');
    }
    
    try {
      // Set timeout protection for initialization
      _startOperationTimeout('initialize');
      
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _errorController.add('Microphone permission not granted for Enhanced VAD');
        if (kDebugMode) {
          print('❌ Enhanced VAD ($_vadInstanceId): Microphone permission denied');
        }
        return;
      }
      
      // Try to initialize RNNoise with crash protection
      try {
        _rnnoiseInitialized = await _rnnoiseService.initialize();
        if (_rnnoiseInitialized) {
          if (kDebugMode) {
            AppLogger.d(' Enhanced VAD ($_vadInstanceId): RNNoise initialized successfully');
          }
        } else {
          if (kDebugMode) {
            print('⚠️ Enhanced VAD ($_vadInstanceId): RNNoise initialization failed, using amplitude fallback');
          }
          _useRNNoise = false;
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Enhanced VAD ($_vadInstanceId): RNNoise initialization error: $e, using amplitude fallback');
        }
        _useRNNoise = false;
        _rnnoiseInitialized = false;
      }
      
      _isInitialized = true;
      _clearOperationTimeout();
      
      if (kDebugMode) {
        AppLogger.d(' Enhanced VAD ($_vadInstanceId) initialized (RNNoise: ${_useRNNoise ? 'ENABLED' : 'DISABLED'})');
      }
    } catch (e) {
      _clearOperationTimeout();
      _errorController.add('Error initializing Enhanced VAD: $e');
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId) initialization error: $e');
      }
    }
  }
  
  /// Start enhanced voice activity detection
  Future<bool> startListening() async {
    // Enhanced double-stop protection
    if (_isDisposing) {
      if (kDebugMode) {
        print('🛑 Enhanced VAD ($_vadInstanceId): Cannot start - instance is disposing');
      }
      return false;
    }
    
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized || _isDisposing) {
        return false;
      }
    }
    
    if (_isListening) {
      if (kDebugMode) {
        AppLogger.d(' Enhanced VAD ($_vadInstanceId): Already listening, ignoring duplicate start');
      }
      return true;
    }
    
    if (kDebugMode) {
      AppLogger.d(' Enhanced VAD ($_vadInstanceId): Starting voice activity detection');
    }
    
    try {
      // Set timeout protection for start operation
      _startOperationTimeout('startListening');
      
      // RACE CONDITION FIX: Initialize worker completion tracker
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
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): Failed to start listening: $e');
      }
      _errorController.add('Failed to start VAD: $e');
      return false;
    }
  }
  
  /// Start RNNoise-based VAD
  Future<bool> _startRNNoiseVAD() async {
    try {
      // Enhanced state validation
      if (_isDisposing) {
        if (kDebugMode) {
          print('🛑 Enhanced VAD ($_vadInstanceId): Cannot start RNNoise - disposing');
        }
        return false;
      }
      
      // RACE CONDITION FIX: Wait for any ongoing shutdown to complete
      if (_isShuttingDown) {
        if (kDebugMode) {
          print('🔄 Enhanced VAD ($_vadInstanceId): Shutdown in progress, waiting for completion before restart');
        }
        
        final shutdownCompleted = await _waitForShutdownCompletion();
        if (!shutdownCompleted) {
          if (kDebugMode) {
            print('❌ Enhanced VAD ($_vadInstanceId): Failed to wait for shutdown completion');
          }
          return false;
        }
      }
      
      // Ensure shutdown flags are reset after successful wait
      _isShuttingDown = false;
      
      // Reset RNNoise state for new session with crash protection
      try {
        await _rnnoiseService.reset();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Enhanced VAD ($_vadInstanceId): RNNoise reset failed: $e');
        }
        // Continue without reset - not critical
      }
      
      // CRITICAL: Set sampling rate to 48kHz for RNNoise with native crash protection
      try {
        AudioStreamer().sampleRate = _sampleRate; // 48000 Hz as defined in _sampleRate
        
        if (kDebugMode) {
          AppLogger.d(' Enhanced VAD ($_vadInstanceId): Audio streamer configured for ${_sampleRate}Hz (RNNoise requirement)');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Enhanced VAD ($_vadInstanceId): Failed to configure audio streamer: $e');
        }
        return await _fallbackToAmplitudeVAD();
      }
      
      // Subscribe to audio stream with enhanced error handling
      try {
        _audioSubscription = AudioStreamer().audioStream.listen(
          _processRNNoiseAudioChunk,
          onError: (error) {
            if (kDebugMode) {
              print('❌ Enhanced VAD ($_vadInstanceId): RNNoise VAD stream error: $error');
            }
            _isStreamActive = false; // Mark stream as inactive on error
            _completeWorkerIfNeeded('RNNoise stream onError');
            _handleStreamError(error);
          },
          onDone: () {
            if (kDebugMode) {
              print('🔚 Enhanced VAD ($_vadInstanceId): RNNoise stream completed');
            }
            _isStreamActive = false;
            _completeWorkerIfNeeded('RNNoise stream onDone');
          },
        );
      } catch (e) {
        if (kDebugMode) {
          print('❌ Enhanced VAD ($_vadInstanceId): Failed to subscribe to audio stream: $e');
        }
        return await _fallbackToAmplitudeVAD();
      }
      
      _isListening = true;
      _isStreamActive = true; // Mark stream as active
      _resetVADState();
      
      if (kDebugMode) {
        AppLogger.d(' Enhanced VAD ($_vadInstanceId): Started RNNoise-based voice detection');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): Failed to start RNNoise VAD: $e');
      }
      return await _fallbackToAmplitudeVAD();
    }
  }
  
  /// Start simple amplitude-based VAD (fallback)
  Future<bool> _startAmplitudeVAD() async {
    try {
      // Enhanced state validation
      if (_isDisposing || _isShuttingDown) {
        if (kDebugMode) {
          print('🛑 Enhanced VAD ($_vadInstanceId): Cannot start amplitude VAD - disposing or shutting down');
        }
        return false;
      }
      
      // Set sampling rate for amplitude processing with crash protection
      try {
        AudioStreamer().sampleRate = 16000;
      } catch (e) {
        if (kDebugMode) {
          print('❌ Enhanced VAD ($_vadInstanceId): Failed to set amplitude VAD sample rate: $e');
        }
        _errorController.add('Failed to configure audio for amplitude VAD: $e');
        return false;
      }
      
      // Subscribe to audio stream with enhanced error handling
      try {
        _audioSubscription = AudioStreamer().audioStream.listen(
          _processAmplitudeChunk,
          onError: (error) {
            if (kDebugMode) {
              print('❌ Enhanced VAD ($_vadInstanceId): Amplitude VAD stream error: $error');
            }
            _completeWorkerIfNeeded('Amplitude stream onError');
            _handleStreamError(error);
          },
          onDone: () {
            if (kDebugMode) {
              print('🔚 Enhanced VAD ($_vadInstanceId): Amplitude stream completed');
            }
            _isStreamActive = false;
            _completeWorkerIfNeeded('Amplitude stream onDone');
          },
        );
      } catch (e) {
        if (kDebugMode) {
          print('❌ Enhanced VAD ($_vadInstanceId): Failed to subscribe to amplitude stream: $e');
        }
        _errorController.add('Failed to start amplitude VAD stream: $e');
        return false;
      }
      
      _isListening = true;
      _isStreamActive = true;
      _resetVADState();
      
      if (kDebugMode) {
        AppLogger.d(' Enhanced VAD ($_vadInstanceId): Started amplitude-based voice detection');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): Failed to start amplitude VAD: $e');
      }
      _errorController.add('Failed to start VAD: $e');
      return false;
    }
  }
  
  /// Process audio chunk for amplitude-based VAD
  void _processAmplitudeChunk(List<double> chunk) {
    // RACE CONDITION FIX: Defensive state checks to prevent AudioRecord crashes  
    if (!_isInitialized || !_isStreamActive || _isShuttingDown || !_isListening || _isDisposing) {
      if (kDebugMode && (_isShuttingDown || _isDisposing)) {
        print('🛑 Enhanced VAD ($_vadInstanceId): Ignoring amplitude chunk during shutdown to prevent buffer race');
      }
      return; // Exit early to prevent buffer race conditions
    }
    
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
    // RACE CONDITION FIX: Enhanced state checks to prevent AudioRecord native crashes
    if (!_isInitialized || !_isStreamActive || _isShuttingDown || !_isListening || _isDisposing) {
      if (kDebugMode && (_isShuttingDown || _isDisposing)) {
        print('🛑 Enhanced VAD ($_vadInstanceId): Ignoring audio chunk during shutdown to prevent buffer race');
      }
      return; // Exit early to prevent buffer race conditions
    }
    
    try {
      // Add samples to buffer with additional safety checks
      if (chunk.isNotEmpty && _audioBuffer.length < 10000) { // Prevent excessive buffer growth
        _audioBuffer.addAll(chunk);
      }
      
      // Process complete frames with enhanced state validation
      while (_audioBuffer.length >= _frameSize && 
             _isStreamActive && 
             !_isShuttingDown && 
             !_isDisposing &&
             _isListening) {
        
        final frame = _audioBuffer.take(_frameSize).toList();
        _audioBuffer.removeRange(0, _frameSize);
        
        // Additional safety check before processing frame
        if (_isStreamActive && !_isShuttingDown && !_isDisposing) {
          _processRNNoiseAudioFrame(frame);
        } else {
          // Stop processing if state changed during loop
          break;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): RNNoise audio processing error: $e');
      }
      // Don't let processing errors crash the stream
      _handleProcessingError(e);
    }
  }
  
  /// Process a single audio frame with RNNoise
  void _processRNNoiseAudioFrame(List<double> frame) async {
    try {
      // Convert normalized samples (-1.0 to 1.0) to Int16 for RNNoise
      // Use full Int16 range (-32768 to 32767) for optimal RNNoise performance
      final Int16List int16Frame = Int16List(frame.length);
      for (int i = 0; i < frame.length; i++) {
        int16Frame[i] = (frame[i] * 32767.0).round().clamp(-32768, 32767);
      }
      
      // Process with RNNoise
      final processedFrame = await _rnnoiseService.processAudioFrame(int16Frame);
      
      if (processedFrame != null) {
        // Get VAD probability from RNNoise
        final vadProbability = await _rnnoiseService.getVadProbability();
        
        // Calculate amplitude for UI visualization
        final amplitude = _calculateAmplitudeFromInt16(processedFrame);
        _amplitudeController.add(amplitude);
        
        // Apply dynamic threshold: base 0.8 + amplitude gate for better noise rejection
        // Quiet audio (< -50dB) needs higher confidence to be considered speech
        final dynamicThreshold = amplitude < -50.0 ? _speechThreshold + 0.1 : _speechThreshold;
        
        // Apply hysteresis-based VAD logic using RNNoise probability
        if (vadProbability > dynamicThreshold) {
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
        
        // Throttled logging to reduce spam (max 1 log per second)
        if (kDebugMode && (vadProbability > 0.1) && _shouldLog()) {
          AppLogger.d(' Enhanced VAD (RNNoise): confidence=${vadProbability.toStringAsFixed(3)} | '
                'threshold=${dynamicThreshold.toStringAsFixed(2)} | frames=S$_speechFrames/Sil$_silenceFrames | amp=${amplitude.toStringAsFixed(1)}dB');
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
  
  /// Check if enough time has passed to allow logging (throttling mechanism)
  bool _shouldLog() {
    final now = DateTime.now();
    if (_lastLogTime == null || now.difference(_lastLogTime!) >= _logThrottleInterval) {
      _lastLogTime = now;
      return true;
    }
    return false;
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
    // Create shutdown completion tracker if not already created
    _shutdownCompleter ??= Completer<void>();
    
    _isShuttingDown = true;
    _isStreamActive = false;
    
    if (_audioSubscription != null) {
      await _audioSubscription!.cancel();
      _audioSubscription = null;
      
      // Give time for buffer cleanup
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    _resetVADState();
    
    // Signal shutdown completion
    _isShuttingDown = false;
    if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
      _shutdownCompleter!.complete();
    }
  }
  
  /// Stop voice activity detection
  Future<void> stopListening() async {
    // Enhanced double-stop protection
    if (!_isListening || _isShuttingDown) {
      if (kDebugMode) {
        print('🛑 Enhanced VAD ($_vadInstanceId): Already stopped or shutting down, ignoring duplicate stop');
      }
      return;
    }
    
    if (_isDisposing) {
      if (kDebugMode) {
        print('🛑 Enhanced VAD ($_vadInstanceId): Cannot stop - instance is disposing');
      }
      return;
    }
    
    // RACE CONDITION FIX: Create shutdown completion tracker
    _shutdownCompleter = Completer<void>();
    
    // CRITICAL FIX: Signal shutdown to prevent buffer race conditions
    _isShuttingDown = true;
    _isStreamActive = false;
    
    if (kDebugMode) {
      print('🛑 Enhanced VAD ($_vadInstanceId): Beginning shutdown sequence to prevent buffer race');
    }
    
    try {
      // Set timeout protection for stop operation
      _startOperationTimeout('stopListening');
      
      // Cancel subscription with enhanced crash protection
      if (_audioSubscription != null) {
        try {
          await _audioSubscription!.cancel();
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Enhanced VAD ($_vadInstanceId): Error canceling subscription: $e');
          }
          // Continue with cleanup even if cancellation fails
        } finally {
          _audioSubscription = null;
        }
        
        // RACE CONDITION FIX: Wait for worker thread to complete before proceeding
        if (_workerDone != null && !_workerDone!.isCompleted) {
          if (kDebugMode) {
            print('⏳ Enhanced VAD ($_vadInstanceId): Waiting for worker thread to exit AudioRecord.read()...');
          }
          try {
            await _workerDone!.future.timeout(const Duration(milliseconds: 500));
            if (kDebugMode) {
              print('✅ Enhanced VAD ($_vadInstanceId): Worker thread confirmed exited');
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ Enhanced VAD ($_vadInstanceId): Worker completion timeout, proceeding anyway: $e');
            }
            // Complete manually to prevent future deadlocks
            _completeWorkerIfNeeded('stopListening timeout');
          }
        }
        
        // CRITICAL: Give native AudioRecord time to release buffers
        // This prevents the ClientProxy::releaseBuffer assert failure
        await Future.delayed(const Duration(milliseconds: 200)); // Increased from 150ms for better stability
      }
      
      // Reset state safely
      _isListening = false;
      _isSpeechDetected = false;
      _resetVADState();
      
      _clearOperationTimeout();
      
      // RACE CONDITION FIX: Signal shutdown completion
      _isShuttingDown = false;
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
      
      // RACE CONDITION FIX: Reset worker future after clean stop to prevent stale references
      _workerDone = null;
      _workerCompletionTracked = false;
      
      if (kDebugMode) {
        AppLogger.d(' Enhanced VAD ($_vadInstanceId): Stopped listening (buffers safely released, shutdown complete)');
      }
      
    } catch (e) {
      _clearOperationTimeout();
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): Error during stop: $e');
      }
      // Ensure state is reset even on error
      _isListening = false;
      _isSpeechDetected = false;
      _isShuttingDown = false;
      _resetVADState();
      
      // RACE CONDITION FIX: Signal shutdown completion even on error
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
    }
  }
  
  /// Reset VAD state
  void _resetVADState() {
    _speechFrames = 0;
    _silenceFrames = 0;
    _audioBuffer.clear();
  }
  
  /// Wait for shutdown completion to prevent race conditions
  /// 
  /// This method ensures that any ongoing shutdown process completes
  /// before allowing a restart attempt, preventing the race condition
  /// where restart is attempted while shutdown is still in progress.
  Future<bool> _waitForShutdownCompletion() async {
    if (!_isShuttingDown) {
      return true; // No shutdown in progress
    }
    
    if (kDebugMode) {
      print('⏳ Enhanced VAD ($_vadInstanceId): Waiting for shutdown completion to prevent race condition');
    }
    
    try {
      // Wait for existing shutdown to complete with timeout
      if (_shutdownCompleter != null) {
        await _shutdownCompleter!.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            if (kDebugMode) {
              print('⚠️ Enhanced VAD ($_vadInstanceId): Shutdown completion timeout - forcing reset');
            }
            // Force reset shutdown state on timeout
            _isShuttingDown = false;
            _shutdownCompleter = null;
          },
        );
      }
      
      // Double-check shutdown state after wait
      if (_isShuttingDown) {
        if (kDebugMode) {
          print('⚠️ Enhanced VAD ($_vadInstanceId): Shutdown still in progress after wait - forcing reset');
        }
        _isShuttingDown = false;
        _shutdownCompleter = null;
      }
      
      if (kDebugMode) {
        print('✅ Enhanced VAD ($_vadInstanceId): Shutdown completion confirmed - safe to restart');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): Error waiting for shutdown completion: $e');
      }
      // Force reset on any error
      _isShuttingDown = false;
      _shutdownCompleter = null;
      return false;
    }
  }
  
  /// Update VAD sensitivity (public API)
  void setSpeechThreshold(double threshold) {
    _speechThreshold = threshold.clamp(0.0, 1.0);
    if (kDebugMode) {
      AppLogger.d(' Enhanced VAD: Threshold updated to $_speechThreshold');
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
    // Prevent new operations during disposal
    if (_isDisposing) {
      if (kDebugMode) {
        print('🛑 Enhanced VAD ($_vadInstanceId): Already disposing, ignoring duplicate dispose');
      }
      return;
    }
    
    _isDisposing = true;
    
    if (kDebugMode) {
      print('🗑️ Enhanced VAD ($_vadInstanceId): Starting disposal process');
    }
    
    try {
      // Clear any pending timeouts
      _clearOperationTimeout();
      
      // Stop listening with enhanced protection
      await stopListening();
      
      // Give extra time for cleanup during disposal
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Dispose RNNoise service with crash protection
      if (_rnnoiseInitialized) {
        try {
          await _rnnoiseService.dispose();
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Enhanced VAD ($_vadInstanceId): Error disposing RNNoise service: $e');
          }
          // Continue with disposal even if RNNoise disposal fails
        }
        _rnnoiseInitialized = false;
      }
      
      // Close stream controllers with crash protection
      try {
        await _speechStartController.close();
      } catch (e) {
        if (kDebugMode) print('⚠️ Enhanced VAD ($_vadInstanceId): Error closing speech start controller: $e');
      }
      
      try {
        await _speechEndController.close();
      } catch (e) {
        if (kDebugMode) print('⚠️ Enhanced VAD ($_vadInstanceId): Error closing speech end controller: $e');
      }
      
      try {
        await _errorController.close();
      } catch (e) {
        if (kDebugMode) print('⚠️ Enhanced VAD ($_vadInstanceId): Error closing error controller: $e');
      }
      
      try {
        await _amplitudeController.close();
      } catch (e) {
        if (kDebugMode) print('⚠️ Enhanced VAD ($_vadInstanceId): Error closing amplitude controller: $e');
      }
      
      // Reset all state
      _isInitialized = false;
      _useRNNoise = false;
      _isListening = false;
      _isSpeechDetected = false;
      _isStreamActive = false;
      _isShuttingDown = false;
      _resetVADState();
      
      // RACE CONDITION FIX: Complete any pending shutdown tracker
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
      _shutdownCompleter = null;
      
      if (kDebugMode) {
        print('🗑️ Enhanced VAD ($_vadInstanceId): Disposed successfully');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Enhanced VAD ($_vadInstanceId): Error during disposal: $e');
      }
      // Ensure disposal flag remains set even on error
    }
  }
  
  /// ENGINEER FEEDBACK: Public API to wait for worker thread to completely exit
  /// Call this before any AudioRecord release operations to prevent race conditions
  Future<void> waitForWorkerExit() async {
    if (_workerDone != null && !_workerDone!.isCompleted) {
      try {
        await _workerDone!.future.timeout(const Duration(milliseconds: 500));
        if (kDebugMode) {
          print('✅ Enhanced VAD ($_vadInstanceId): Worker thread confirmed exited');
        }
      } catch (e) {
        // ENGINEER FEEDBACK: Enhanced timeout logging with call-site and state info
        if (kDebugMode) {
          final callSite = StackTrace.current.toString().split('\n').length > 1 
              ? StackTrace.current.toString().split('\n')[1] 
              : 'unknown';
          print('⚠️ Enhanced VAD ($_vadInstanceId): Worker exit timeout from: $callSite');
          print('⚠️ Enhanced VAD ($_vadInstanceId): Current state - listening: $_isListening, streamActive: $_isStreamActive, shuttingDown: $_isShuttingDown');
          print('⚠️ Enhanced VAD ($_vadInstanceId): Timeout error: $e');
        }
        // Complete manually to prevent future deadlocks
        _completeWorkerIfNeeded('waitForWorkerExit timeout');
      }
    } else if (kDebugMode) {
      print('✅ Enhanced VAD ($_vadInstanceId): Worker already exited or not started');
    }
  }

  /// RACE CONDITION FIX: Single-shot worker completion tracking (hot-reload safe)
  void _completeWorkerIfNeeded(String context) {
    if (!_workerCompletionTracked && _workerDone != null && !_workerDone!.isCompleted) {
      _workerCompletionTracked = true;
      _workerDone!.complete();
      if (kDebugMode) {
        print('✅ Enhanced VAD ($_vadInstanceId): Worker completion tracked from $context');
      }
    } else if (kDebugMode && _workerCompletionTracked) {
      print('🔄 Enhanced VAD ($_vadInstanceId): Worker already completed, ignoring completion from $context (hot-reload safe)');
    }
  }
  
  /// ENGINEER FEEDBACK: Debug-only safety assert for worker state validation
  /// This helps catch programming errors where operations are attempted with invalid worker state
  void _assertWorkerState(String operation) {
    if (kDebugMode) {
      // Assert: Worker future should exist when we're actively listening
      if (_isListening && _isStreamActive && _workerDone == null) {
        print('🚨 ASSERT FAILED: $_vadInstanceId $operation called with active stream but no worker tracker!');
        print('🚨 State: listening=$_isListening, streamActive=$_isStreamActive, workerDone=$_workerDone');
        assert(false, 'Worker tracker missing during active operation');
      }
      
      // Assert: Completion tracking should be consistent
      if (_workerDone != null && _workerDone!.isCompleted && !_workerCompletionTracked) {
        print('🚨 ASSERT FAILED: $_vadInstanceId $operation found completed worker but tracking flag not set!');
        print('🚨 State: workerCompleted=${_workerDone!.isCompleted}, tracked=$_workerCompletionTracked');
        assert(false, 'Worker completion tracking inconsistent');
      }
    }
  }
  
  /// Start operation timeout protection
  void _startOperationTimeout(String operation) {
    _clearOperationTimeout();
    _operationTimeoutTimer = Timer(_operationTimeout, () {
      if (kDebugMode) {
        print('⏰ Enhanced VAD ($_vadInstanceId): Operation timeout for $operation');
      }
      _handleOperationTimeout(operation);
    });
  }
  
  /// Clear operation timeout
  void _clearOperationTimeout() {
    _operationTimeoutTimer?.cancel();
    _operationTimeoutTimer = null;
  }
  
  /// Handle operation timeout
  void _handleOperationTimeout(String operation) {
    if (kDebugMode) {
      print('🚨 Enhanced VAD ($_vadInstanceId): Timeout during $operation - forcing cleanup');
    }
    
    // Force cleanup on timeout
    _isStreamActive = false;
    
    // Cancel subscription immediately
    _audioSubscription?.cancel();
    _audioSubscription = null;
    
    // Reset state
    _isListening = false;
    _isSpeechDetected = false;
    _resetVADState();
    
    // RACE CONDITION FIX: Signal shutdown completion on timeout
    _isShuttingDown = false;
    if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
      _shutdownCompleter!.complete();
    }
    
    _errorController.add('VAD operation timeout: $operation');
  }
  
  /// Handle stream errors with fallback protection
  void _handleStreamError(dynamic error) {
    if (kDebugMode) {
      print('🚨 Enhanced VAD ($_vadInstanceId): Stream error: $error');
    }
    
    // Mark stream as inactive
    _isStreamActive = false;
    
    // Check if this is a platform exception (native crash)
    if (error is PlatformException) {
      if (kDebugMode) {
        print('🚨 Enhanced VAD ($_vadInstanceId): Native platform error detected: ${error.code} - ${error.message}');
      }
      
      // For native errors, force immediate cleanup
      _audioSubscription?.cancel();
      _audioSubscription = null;
      _isListening = false;
      _resetVADState();
      
      // RACE CONDITION FIX: Signal shutdown completion on native error
      _isShuttingDown = false;
      if (_shutdownCompleter != null && !_shutdownCompleter!.isCompleted) {
        _shutdownCompleter!.complete();
      }
    }
    
    // Emit error event
    _errorController.add('VAD stream error: $error');
    
    // Try to fallback to amplitude VAD if using RNNoise
    if (_useRNNoise) {
      if (kDebugMode) {
        print('🔄 Enhanced VAD ($_vadInstanceId): Attempting fallback to amplitude VAD due to stream error');
      }
      _fallbackToAmplitudeVAD();
    }
  }
  
  /// Handle processing errors without crashing the stream
  void _handleProcessingError(dynamic error) {
    if (kDebugMode) {
      print('⚠️ Enhanced VAD ($_vadInstanceId): Processing error (continuing): $error');
    }
    
    // Clear buffer to prevent further issues
    _audioBuffer.clear();
    
    // Don't emit error events for processing errors to avoid spam
    // Just log and continue
  }
} 