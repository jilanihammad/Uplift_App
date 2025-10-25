import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'tts_streaming_monitor.dart';

/// Event-driven TTS completion tracking that listens to ExoPlayer events
///
/// Eliminates artificial timeout race conditions by hooking into
/// AudioPlayer.processingStateStream for natural completion detection.
class TwoPhaseCompletion {
  final Completer<void> _websocketCompleter = Completer<void>();
  final Completer<void> _playerCompleter = Completer<void>();
  final Completer<void> _bothDoneCompleter = Completer<void>();

  bool _websocketDone = false;
  bool _playerDone = false;
  bool _disposed = false;

  // Event-driven subscriptions instead of timers
  StreamSubscription<ProcessingState>? _playerSubscription;
  Timer? _safetyWatchdog; // Only for true hangs, not normal playback

  // Audio player reference for event listening
  AudioPlayer? _audioPlayer;

  // Callbacks
  Future<void> Function()? _stopPlayerCallback;
  VoidCallback? _onPlaybackFinished;
  VoidCallback? _restartVADCallback;

  /// Initialize with audio player for event-driven completion
  void initializeWithPlayer(AudioPlayer player) {
    if (_disposed) return;

    _audioPlayer = player;

    // Hook into ExoPlayer's natural completion event
    _playerSubscription = player.processingStateStream
        .where((state) => state == ProcessingState.completed)
        .listen((_) {
      if (kDebugMode) {
        debugPrint('🎵 [TTS] ExoPlayer natural completion detected');
      }
      _onPlayerCompletedNaturally();
    });

    if (kDebugMode) {
      debugPrint('🎧 [TTS] Event-driven completion tracking initialized');
    }
  }

  /// Handle natural ExoPlayer completion - the RIGHT way
  Future<void> _onPlayerCompletedNaturally() async {
    // Cancel any safety watchdog since we completed naturally
    _safetyWatchdog?.cancel();
    _safetyWatchdog = null;

    if (kDebugMode) {
      debugPrint('✅ [TTS] Natural playback completion - cleaning up properly');
    }

    // Proper cleanup sequence as specified
    try {
      await _audioPlayer?.stop(); // Hard reset
      await _audioPlayer?.seek(Duration.zero); // Reset position

      // 150ms buffer to prevent VAD self-hearing
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!_disposed) {
          if (kDebugMode) {
            debugPrint('🎤 [TTS] Safe to restart VAD after 150ms buffer');
          }

          // Signal TTS completion and restart VAD
          _onPlaybackFinished?.call();
          _restartVADCallback?.call();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [TTS] Error during natural completion cleanup: $e');
      }
    }

    // Mark player phase as complete
    markPlayerDone();
  }

  /// Set minimal safety watchdog (only for true hangs)
  void setSafetyWatchdog(int totalBytes) {
    if (_disposed) return;

    // Calculate 2x estimated duration as safety margin
    final estMs =
        _calculateExactDuration(totalBytes) ?? _estimateDurationMs(totalBytes);
    final safetyMs = estMs * 2; // 2x estimate for safety

    _safetyWatchdog = Timer(Duration(milliseconds: safetyMs), () {
      if (kDebugMode) {
        debugPrint(
            '⚠️ [TTS] Safety watchdog triggered after ${safetyMs}ms - forcing stop');
      }

      TTSStreamingMonitor().recordStreamingFailure(
          'Safety watchdog timeout after ${safetyMs}ms');
      _forceStop();
    });

    if (kDebugMode) {
      debugPrint(
          '⏲️ [TTS] Safety watchdog set: ${safetyMs}ms (2x estimated ${estMs}ms)');
    }
  }

  /// Calculate exact duration from Opus header (if available)
  int? _calculateExactDuration(int totalBytes) {
    // TODO: Parse Opus header for exact duration
    // For now, return null to fall back to estimation
    return null;
  }

  /// Estimate duration: totalBytes * 8 / 64000 (64 kbps)
  int _estimateDurationMs(int totalBytes) {
    return (totalBytes * 8 ~/ 64).clamp(1000, 60000); // 1s min, 60s max
  }

  /// Force stop for safety watchdog or emergency situations
  Future<void> _forceStop() async {
    if (kDebugMode) {
      debugPrint('🛑 [TTS] Force stopping due to safety watchdog');
    }

    try {
      if (_stopPlayerCallback != null) {
        await _stopPlayerCallback!();
      }

      // Force completion to unblock waiting code
      markWebSocketDone();
      markPlayerDone();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [TTS] Error during force stop: $e');
      }
    }
  }

  /// Set callback to stop audio player on timeout
  void setStopPlayerCallback(Future<void> Function() callback) {
    _stopPlayerCallback = callback;
  }

  /// Set callback for when playback finishes naturally
  void setPlaybackFinishedCallback(VoidCallback callback) {
    _onPlaybackFinished = callback;
  }

  /// Set callback to restart VAD after completion
  void setRestartVADCallback(VoidCallback callback) {
    _restartVADCallback = callback;
  }

  /// Mark WebSocket streaming as complete (tts-done received)
  void markWebSocketDone() {
    if (_disposed || _websocketCompleter.isCompleted) return;

    _websocketDone = true;
    _websocketCompleter.complete();
    _checkBothDone();

    if (kDebugMode) {
      debugPrint('🌐 [TTS] WebSocket phase complete');
    }
  }

  /// Mark audio player as complete (playback finished)
  void markPlayerDone() {
    if (_disposed || _playerCompleter.isCompleted) return;

    _playerDone = true;
    _playerCompleter.complete();
    _checkBothDone();

    if (kDebugMode) {
      debugPrint('🎵 [TTS] Audio player phase complete');
    }
  }

  /// Wait for both WebSocket and player completion (no artificial timeout)
  Future<void> waitForBothDone() => _bothDoneCompleter.future;

  /// Check if both phases are done and complete if so
  void _checkBothDone() {
    if (_websocketDone && _playerDone && !_bothDoneCompleter.isCompleted) {
      _bothDoneCompleter.complete();

      if (kDebugMode) {
        debugPrint('✅ [TTS] Both WebSocket and player phases completed');
      }
    }
  }

  /// Cancel all watchdogs and subscriptions
  void _cancelAllWatchdogs() {
    _safetyWatchdog?.cancel();
    _safetyWatchdog = null;
    _playerSubscription?.cancel();
    _playerSubscription = null;
  }

  /// Dispose and clean up all resources
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _cancelAllWatchdogs();

    // Complete any pending futures to prevent hangs
    if (!_websocketCompleter.isCompleted) {
      _websocketCompleter.complete();
    }
    if (!_playerCompleter.isCompleted) {
      _playerCompleter.complete();
    }
    if (!_bothDoneCompleter.isCompleted) {
      _bothDoneCompleter.complete();
    }

    if (kDebugMode) {
      debugPrint('🧹 [TTS] TwoPhaseCompletion disposed');
    }
  }
}
