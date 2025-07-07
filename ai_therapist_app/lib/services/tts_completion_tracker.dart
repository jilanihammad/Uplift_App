import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tts_streaming_monitor.dart';

/// Tracks completion of both WebSocket and AudioPlayer for TTS streaming
/// 
/// Prevents race conditions where one completes before the other,
/// ensuring proper coordination between data streaming and audio playback.
class TwoPhaseCompletion {
  static const Duration maxTTSDuration = Duration(seconds: 60);
  
  final Completer<void> _websocketCompleter = Completer<void>();
  final Completer<void> _playerCompleter = Completer<void>();
  final Completer<void> _bothDoneCompleter = Completer<void>();
  
  bool _websocketDone = false;
  bool _playerDone = false;
  bool _disposed = false;
  
  /// Mark WebSocket streaming as complete (tts-done received)
  void markWebSocketDone() {
    if (_disposed || _websocketCompleter.isCompleted) return;
    
    _websocketDone = true;
    _websocketCompleter.complete();
    _checkBothDone();
    
    if (kDebugMode) {
      print('🌐 [TTS] WebSocket phase complete');
    }
  }
  
  /// Mark audio player as complete (playback finished)
  void markPlayerDone() {
    if (_disposed || _playerCompleter.isCompleted) return;
    
    _playerDone = true;
    _playerCompleter.complete();
    _checkBothDone();
    
    if (kDebugMode) {
      print('🎵 [TTS] Audio player phase complete');
    }
  }
  
  /// Wait for both WebSocket and player completion
  Future<void> waitForBothDone() => _bothDoneCompleter.future;
  
  /// Wait for both phases with timeout protection
  Future<void> waitForBothDoneWithTimeout() async {
    try {
      await Future.any([
        waitForBothDone(),
        Future.delayed(maxTTSDuration * 1.2).then((_) => throw TimeoutException('TTS completion timeout', maxTTSDuration * 1.2)),
      ]);
      
      if (kDebugMode) {
        print('✅ [TTS] Both phases completed successfully');
      }
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        print('⚠️ [TTS] Timeout waiting for completion (${e.duration?.inSeconds}s) - forcing cleanup');
      }
      
      // Record timeout for monitoring
      TTSStreamingMonitor().recordStreamingFailure('Completion timeout after ${e.duration?.inSeconds}s');
      
      // Force completion to prevent hanging
      markWebSocketDone();
      markPlayerDone();
      
      // Re-throw for caller to handle
      rethrow;
    }
  }
  
  /// Check if both phases are done and complete if so
  void _checkBothDone() {
    if (_websocketDone && _playerDone && !_bothDoneCompleter.isCompleted) {
      _bothDoneCompleter.complete();
      
      if (kDebugMode) {
        print('🎯 [TTS] Both phases complete - TTS can transition to listening');
      }
    }
  }
  
  /// Get current completion status
  Map<String, bool> get status => {
    'websocketDone': _websocketDone,
    'playerDone': _playerDone,
    'bothDone': _websocketDone && _playerDone,
    'disposed': _disposed,
  };
  
  /// Dispose and mark both phases complete (for error cleanup)
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    // Complete any pending phases
    markWebSocketDone();
    markPlayerDone();
    
    if (kDebugMode) {
      print('🗑️ [TTS] TwoPhaseCompletion disposed');
    }
  }
}