import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'tts_streaming_monitor.dart';
class TwoPhaseCompletion {
  final Completer<void> _websocketCompleter = Completer<void>();
  final Completer<void> _playerCompleter = Completer<void>();
  final Completer<void> _bothDoneCompleter = Completer<void>();
  bool _websocketDone = false;
  bool _playerDone = false;
  bool _disposed = false;
  StreamSubscription<ProcessingState>? _playerSubscription;
  Timer? _safetyWatchdog; // Only for true hangs, not normal playback
  AudioPlayer? _audioPlayer;
  Future<void> Function()? _stopPlayerCallback;
  VoidCallback? _onPlaybackFinished;
  VoidCallback? _restartVADCallback;
  void initializeWithPlayer(AudioPlayer player) {
    if (_disposed) return;
    _audioPlayer = player;
    _playerSubscription = player.processingStateStream
        .where((state) => state == ProcessingState.completed)
        .listen((_) {
      _onPlayerCompletedNaturally();
    });
  }
  Future<void> _onPlayerCompletedNaturally() async {
    _safetyWatchdog?.cancel();
    _safetyWatchdog = null;
    try {
      await _audioPlayer?.stop(); // Hard reset
      await _audioPlayer?.seek(Duration.zero); // Reset position
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!_disposed) {
          _onPlaybackFinished?.call();
          _restartVADCallback?.call();
        }
      });
    } catch (e) {}
    markPlayerDone();
  }
  void setSafetyWatchdog(int totalBytes) {
    if (_disposed) return;
    final estMs =
        _calculateExactDuration(totalBytes) ?? _estimateDurationMs(totalBytes);
    final safetyMs = estMs * 2; // 2x estimate for safety
    _safetyWatchdog = Timer(Duration(milliseconds: safetyMs), () {
      TTSStreamingMonitor().recordStreamingFailure(
          'Safety watchdog timeout after ${safetyMs}ms');
      _forceStop();
    });
  }
  int? _calculateExactDuration(int totalBytes) {
    // TODO: Parse Opus header for exact duration
    return null;
  }
  int _estimateDurationMs(int totalBytes) {
    return (totalBytes * 8 ~/ 64).clamp(1000, 60000); // 1s min, 60s max
  }
  Future<void> _forceStop() async {
    try {
      if (_stopPlayerCallback != null) {
        await _stopPlayerCallback!();
      }
      markWebSocketDone();
      markPlayerDone();
    } catch (e) {}
  }
  void setStopPlayerCallback(Future<void> Function() callback) {
    _stopPlayerCallback = callback;
  }
  void setPlaybackFinishedCallback(VoidCallback callback) {
    _onPlaybackFinished = callback;
  }
  void setRestartVADCallback(VoidCallback callback) {
    _restartVADCallback = callback;
  }
  void markWebSocketDone() {
    if (_disposed || _websocketCompleter.isCompleted) return;
    _websocketDone = true;
    _websocketCompleter.complete();
    _checkBothDone();
  }
  void markPlayerDone() {
    if (_disposed || _playerCompleter.isCompleted) return;
    _playerDone = true;
    _playerCompleter.complete();
    _checkBothDone();
  }
  Future<void> waitForBothDone() => _bothDoneCompleter.future;
  void _checkBothDone() {
    if (_websocketDone && _playerDone && !_bothDoneCompleter.isCompleted) {
      _bothDoneCompleter.complete();
    }
  }
  void _cancelAllWatchdogs() {
    _safetyWatchdog?.cancel();
    _safetyWatchdog = null;
    _playerSubscription?.cancel();
    _playerSubscription = null;
  }
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelAllWatchdogs();
    if (!_websocketCompleter.isCompleted) {
      _websocketCompleter.complete();
    }
    if (!_playerCompleter.isCompleted) {
      _playerCompleter.complete();
    }
    if (!_bothDoneCompleter.isCompleted) {
      _bothDoneCompleter.complete();
    }
  }
}
