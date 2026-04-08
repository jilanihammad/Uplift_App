library;
import 'dart:async';
typedef TimerCallback = void Function();
typedef TimeUpdateCallback = void Function(
    int elapsedSeconds, int remainingSeconds);
class TimerManager {
  Duration? _sessionDuration;
  Timer? _sessionTimer;
  DateTime? _sessionStartTime;
  Duration _accumulatedTime = Duration.zero;
  bool _isPaused = false;
  TimeUpdateCallback? onTimeUpdate;
  TimerCallback? onSessionExpired;
  TimerCallback? onTimeWarning;
  bool _warningTriggered = false;
  Duration? get sessionDuration => _sessionDuration;
  int get elapsedSeconds => _accumulatedTime.inSeconds;
  int get remainingSeconds {
    if (_sessionDuration == null) return 0;
    final remaining = _sessionDuration!.inSeconds - elapsedSeconds;
    return remaining > 0 ? remaining : 0;
  }
  Duration get elapsedTime => _accumulatedTime;
  Duration get remainingTime => Duration(seconds: remainingSeconds);
  bool get isRunning => _sessionTimer != null && !_isPaused;
  bool get isPaused => _isPaused;
  bool get isExpired =>
      _sessionDuration != null && elapsedSeconds >= _sessionDuration!.inSeconds;
  void setSessionDuration(Duration duration) {
    _sessionDuration = duration;
    _warningTriggered = false; // Reset warning flag
  }
  void startTimer() {
    if (_sessionTimer != null) {
      return;
    }
    if (_sessionDuration == null) {
      return;
    }
    _sessionStartTime = DateTime.now();
    _isPaused = false;
    _updateElapsedTime(forceEmit: true);
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        _updateElapsedTime();
      }
    });
  }
  void pauseTimer() {
    if (_sessionTimer == null || _isPaused) {
      return;
    }
    _isPaused = true;
    if (_sessionStartTime != null) {
      _accumulatedTime += DateTime.now().difference(_sessionStartTime!);
      _sessionStartTime = null;
    }
  }
  void resumeTimer() {
    if (_sessionTimer == null || !_isPaused) {
      return;
    }
    _isPaused = false;
    _sessionStartTime = DateTime.now();
  }
  void stopTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionStartTime = null;
    _accumulatedTime = Duration.zero;
    _isPaused = false;
    _warningTriggered = false;
  }
  void _updateElapsedTime({bool forceEmit = false}) {
    if (_sessionStartTime != null) {
      final currentSessionTime = DateTime.now().difference(_sessionStartTime!);
      final totalElapsed = _accumulatedTime + currentSessionTime;
      if (forceEmit || totalElapsed.inSeconds > _accumulatedTime.inSeconds) {
        if (!forceEmit) {
          _accumulatedTime = _accumulatedTime + const Duration(seconds: 1);
        }
        onTimeUpdate?.call(elapsedSeconds, remainingSeconds);
        if (!_warningTriggered &&
            remainingSeconds <= 300 &&
            remainingSeconds > 0) {
          _warningTriggered = true;
          onTimeWarning?.call();
        }
        if (isExpired) {
          onSessionExpired?.call();
          stopTimer(); // Auto-stop on expiration
        }
      }
    }
  }
  String formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
  String get formattedElapsedTime => formatTime(elapsedSeconds);
  String get formattedRemainingTime => formatTime(remainingSeconds);
  double get sessionProgress {
    if (_sessionDuration == null || _sessionDuration!.inSeconds == 0) {
      return 0.0;
    }
    final progress = elapsedSeconds / _sessionDuration!.inSeconds;
    return progress.clamp(0.0, 1.0);
  }
  void dispose() {
    stopTimer();
    onTimeUpdate = null;
    onSessionExpired = null;
    onTimeWarning = null;
  }
  Map<String, dynamic> getTimerState() {
    return {
      'isRunning': isRunning,
      'isPaused': isPaused,
      'isExpired': isExpired,
      'elapsedSeconds': elapsedSeconds,
      'remainingSeconds': remainingSeconds,
      'sessionDurationMinutes': _sessionDuration?.inMinutes ?? 0,
      'sessionProgress': sessionProgress,
      'formattedElapsed': formattedElapsedTime,
      'formattedRemaining': formattedRemainingTime,
    };
  }
}
