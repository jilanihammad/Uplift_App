import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_player_manager.dart';
import 'tts_streaming_monitor.dart';

/// Manages streaming TTS playback with proper lifecycle and Android compatibility
/// 
/// Key features:
/// - Proper StreamController lifecycle management
/// - Back-pressure protection for long utterances
/// - Integration with existing AudioPlayerManager
/// - Memory monitoring integration
class StreamingTTSPlayback {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  
  bool _sourceReady = false;
  bool _disposed = false;
  int _chunksAdded = 0;
  int _totalBytesAdded = 0;
  
  // Back-pressure configuration
  static const int maxBufferedChunks = 50; // ~200KB buffer for long utterances
  static const Duration backPressureDelay = Duration(milliseconds: 100);
  
  StreamingTTSPlayback() {
    _sourceReady = true;
    
    if (kDebugMode) {
      print('🎯 [TTS] StreamingTTSPlayback created and ready');
    }
  }
  
  /// Start audio playback using the existing AudioPlayerManager.playAudioStream
  Future<void> startPlayback(AudioPlayerManager playerManager, String debugName) async {
    if (!_sourceReady) {
      throw StateError('StreamingTTSPlayback not ready - cannot start playback');
    }
    
    if (_disposed) {
      throw StateError('StreamingTTSPlayback already disposed');
    }
    
    if (kDebugMode) {
      print('🚀 [TTS] Starting streaming playback: $debugName');
    }
    
    try {
      // Use existing AudioPlayerManager.playAudioStream method
      await playerManager.playAudioStream(_controller.stream, debugName: debugName);
    } catch (e) {
      if (kDebugMode) {
        print('❌ [TTS] Failed to start streaming playback: $e');
      }
      TTSStreamingMonitor().recordStreamingFailure('Playback start failed: $e');
      rethrow;
    }
  }
  
  /// Add audio chunk to the stream with back-pressure protection
  Future<void> addChunk(Uint8List chunk) async {
    if (_disposed || _controller.isClosed || !_sourceReady) {
      if (kDebugMode) {
        print('⚠️ [TTS] Ignoring chunk - playback disposed or closed');
      }
      return;
    }
    
    // Back-pressure protection for very long utterances (>15 seconds)
    if (_chunksAdded > maxBufferedChunks) {
      if (kDebugMode) {
        print('⚠️ [TTS] Back-pressure triggered at chunk $_chunksAdded - pausing');
      }
      
      // Brief pause to let playback catch up
      await Future.delayed(backPressureDelay);
    }
    
    try {
      _controller.add(chunk);
      _chunksAdded++;
      _totalBytesAdded += chunk.length;
      
      // Log progress at meaningful intervals
      if (kDebugMode && _chunksAdded % 10 == 0) {
        print('🎵 [TTS] Streaming chunk #$_chunksAdded (${(_totalBytesAdded / 1024).toStringAsFixed(1)} KB total)');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ [TTS] Failed to add chunk: $e');
      }
      TTSStreamingMonitor().recordStreamingFailure('Chunk addition failed: $e');
    }
  }
  
  /// Signal that no more chunks will be added (WebSocket done)
  void signalStreamComplete() {
    if (_disposed || _controller.isClosed) return;
    
    if (kDebugMode) {
      print('🏁 [TTS] Stream complete signal - closing controller ($_chunksAdded chunks, ${(_totalBytesAdded / 1024).toStringAsFixed(1)} KB total)');
    }
    
    try {
      _controller.close();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [TTS] Error closing stream controller: $e');
      }
    }
  }
  
  /// Get streaming statistics
  Map<String, dynamic> get stats => {
    'chunks_added': _chunksAdded,
    'total_bytes': _totalBytesAdded,
    'source_ready': _sourceReady,
    'disposed': _disposed,
    'controller_closed': _controller.isClosed,
  };
  
  /// Dispose resources and cleanup
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    if (kDebugMode) {
      print('🗑️ [TTS] Disposing StreamingTTSPlayback ($_chunksAdded chunks processed)');
    }
    
    try {
      if (!_controller.isClosed) {
        _controller.close();
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [TTS] Error during disposal: $e');
      }
    }
  }
}