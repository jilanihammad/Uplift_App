import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for RNNoise-based audio noise suppression
/// 
/// Provides real-time noise suppression capabilities using the RNNoise library.
/// Processes audio in 48kHz 16-bit mono PCM format as required by RNNoise.
class RNNoiseService {
  static const MethodChannel _channel = MethodChannel('rnnoise_flutter');
  
  /// Singleton instance
  static RNNoiseService? _instance;
  static RNNoiseService get instance {
    _instance ??= RNNoiseService._internal();
    return _instance!;
  }
  RNNoiseService._internal();

  bool _isInitialized = false;

  /// Initialize the RNNoise library
  /// 
  /// Must be called before any other methods.
  /// Returns true if initialization was successful.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      final bool result = await _channel.invokeMethod('initialize');
      _isInitialized = result;
      if (kDebugMode && result) {
        debugPrint('🔇 RNNoise service initialized successfully');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ RNNoise initialization failed: $e');
      }
      return false;
    }
  }

  /// Process audio data through RNNoise noise suppression
  /// 
  /// [audioData] must be 16-bit PCM audio at 48kHz sample rate.
  /// Frame size should be 480 samples (10ms at 48kHz).
  /// 
  /// Returns the processed audio data with noise suppression applied.
  /// Returns null if processing fails.
  Future<Int16List?> processAudioFrame(Int16List audioData) async {
    if (!_isInitialized) {
      if (kDebugMode) {
        debugPrint('⚠️ RNNoise not initialized, attempting auto-initialization');
      }
      final initialized = await initialize();
      if (!initialized) return null;
    }
    
    if (audioData.length != 480) {
      if (kDebugMode) {
        debugPrint('⚠️ Invalid RNNoise frame size: ${audioData.length} (expected 480)');
      }
      return null;
    }
    
    try {
      final Uint8List result = await _channel.invokeMethod(
        'processAudio',
        {'audioData': audioData},
      );
      
      // Convert Uint8List back to Int16List
      final ByteData byteData = ByteData.sublistView(result);
      final Int16List processedAudio = Int16List(result.length ~/ 2);
      
      for (int i = 0; i < processedAudio.length; i++) {
        processedAudio[i] = byteData.getInt16(i * 2, Endian.little);
      }
      
      return processedAudio;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ RNNoise audio processing failed: $e');
      }
      return null;
    }
  }

  /// Process audio with automatic format conversion from 16kHz to 48kHz and back
  /// 
  /// [input16k] should be 16-bit PCM audio at 16kHz
  /// Returns processed audio at 16kHz with noise suppression applied
  Future<Int16List?> processAudio16k(Int16List input16k) async {
    try {
      // Convert 16kHz to 48kHz
      final Int16List input48k = _upsample16to48(input16k);
      
      // Split into 480-sample frames for RNNoise
      final List<Int16List> frames = _splitIntoFrames(input48k, frameSize: 480);
      final List<Int16List> processedFrames = [];
      
      // Process each frame
      for (final frame in frames) {
        final processed = await processAudioFrame(frame);
        if (processed != null) {
          processedFrames.add(processed);
        } else {
          // If processing fails, use original frame
          processedFrames.add(frame);
        }
      }
      
      // Combine frames back to continuous audio
      final Int16List combined48k = _combineFrames(processedFrames);
      
      // Convert back to 16kHz
      final Int16List output16k = _downsample48to16(combined48k);
      
      return output16k;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ RNNoise 16k processing failed: $e');
      }
      return null;
    }
  }

  /// Get VAD (Voice Activity Detection) probability from last processed frame
  /// 
  /// Returns a value between 0.0 and 1.0 indicating the probability
  /// that the last processed audio frame contained speech.
  /// Higher values indicate higher probability of speech.
  Future<double> getVadProbability() async {
    if (!_isInitialized) return 0.0;
    
    try {
      final double probability = await _channel.invokeMethod('getVadProbability');
      return probability.clamp(0.0, 1.0);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to get VAD probability: $e');
      }
      return 0.0;
    }
  }

  /// Reset the RNNoise internal state
  /// 
  /// Useful when starting a new audio session or when there's been
  /// a long gap in audio processing.
  Future<void> reset() async {
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('reset');
      if (kDebugMode) {
        debugPrint('🔄 RNNoise state reset');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ RNNoise reset failed: $e');
      }
    }
  }

  /// Clean up and dispose of RNNoise resources
  /// 
  /// Should be called when the noise suppression is no longer needed.
  Future<void> dispose() async {
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('dispose');
      _isInitialized = false;
      if (kDebugMode) {
        debugPrint('🗑️ RNNoise service disposed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ RNNoise disposal failed: $e');
      }
    }
  }

  /// Check if RNNoise is properly initialized and ready to process audio
  bool get isInitialized => _isInitialized;

  // Audio format conversion utilities

  /// Convert audio from 16kHz to 48kHz using simple interpolation
  Int16List _upsample16to48(Int16List input16k) {
    final int outputLength = input16k.length * 3;
    final Int16List output48k = Int16List(outputLength);
    
    for (int i = 0; i < input16k.length; i++) {
      final int baseIndex = i * 3;
      final int currentSample = input16k[i];
      final int nextSample = (i + 1 < input16k.length) ? input16k[i + 1] : currentSample;
      
      // Linear interpolation for 3x upsampling
      output48k[baseIndex] = currentSample;
      output48k[baseIndex + 1] = ((currentSample * 2 + nextSample) / 3).round();
      output48k[baseIndex + 2] = ((currentSample + nextSample * 2) / 3).round();
    }
    
    return output48k;
  }

  /// Convert audio from 48kHz to 16kHz using decimation
  Int16List _downsample48to16(Int16List input48k) {
    final int outputLength = input48k.length ~/ 3;
    final Int16List output16k = Int16List(outputLength);
    
    for (int i = 0; i < outputLength; i++) {
      final int baseIndex = i * 3;
      if (baseIndex + 2 < input48k.length) {
        // Simple averaging of 3 samples for downsampling
        final int sum = input48k[baseIndex] + 
                       input48k[baseIndex + 1] + 
                       input48k[baseIndex + 2];
        output16k[i] = (sum / 3).round();
      } else {
        // Handle edge case
        output16k[i] = input48k[baseIndex];
      }
    }
    
    return output16k;
  }

  /// Split audio data into frames suitable for RNNoise processing
  List<Int16List> _splitIntoFrames(Int16List audioData, {int frameSize = 480}) {
    final List<Int16List> frames = [];
    
    for (int i = 0; i < audioData.length; i += frameSize) {
      final int endIndex = (i + frameSize < audioData.length) 
          ? i + frameSize 
          : audioData.length;
      
      final Int16List frame = Int16List(frameSize);
      final int actualFrameSize = endIndex - i;
      
      // Copy actual data
      for (int j = 0; j < actualFrameSize; j++) {
        frame[j] = audioData[i + j];
      }
      
      // Pad with zeros if needed
      for (int j = actualFrameSize; j < frameSize; j++) {
        frame[j] = 0;
      }
      
      frames.add(frame);
    }
    
    return frames;
  }

  /// Combine processed audio frames back into a continuous stream
  Int16List _combineFrames(List<Int16List> frames) {
    if (frames.isEmpty) return Int16List(0);
    
    final int totalLength = frames.length * frames.first.length;
    final Int16List combined = Int16List(totalLength);
    
    for (int i = 0; i < frames.length; i++) {
      final int baseIndex = i * frames[i].length;
      for (int j = 0; j < frames[i].length; j++) {
        combined[baseIndex + j] = frames[i][j];
      }
    }
    
    return combined;
  }
}