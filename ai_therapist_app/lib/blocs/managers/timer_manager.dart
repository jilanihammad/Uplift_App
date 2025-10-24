/// TimerManager - Phase 1.1.2
///
/// Manages session timing and duration tracking for VoiceSessionBloc.
/// This manager handles all time-related functionality including session
/// timers, elapsed time tracking, and time-based events.
///
/// Responsibilities:
/// - Session timer management (start, stop, pause)
/// - Elapsed time tracking
/// - Remaining time calculations
/// - Timer-based event notifications
/// - Session duration enforcement
///
/// Thread Safety: Uses Dart Timer (main thread callbacks)
/// Dependencies: None (pure Dart)

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Callback type for timer events
typedef TimerCallback = void Function();

/// Callback type for time updates with remaining seconds
typedef TimeUpdateCallback = void Function(
    int elapsedSeconds, int remainingSeconds);

/// Manages session timing and duration tracking
class TimerManager {
  /// Selected session duration
  Duration? _sessionDuration;

  /// Timer instance for tracking elapsed time
  Timer? _sessionTimer;

  /// Session start time
  DateTime? _sessionStartTime;

  /// Accumulated elapsed time (for pause/resume support)
  Duration _accumulatedTime = Duration.zero;

  /// Whether the timer is currently paused
  bool _isPaused = false;

  /// Callback for time updates (called every second)
  TimeUpdateCallback? onTimeUpdate;

  /// Callback for when session time expires
  TimerCallback? onSessionExpired;

  /// Callback for warning when time is running low (5 minutes left)
  TimerCallback? onTimeWarning;

  /// Flag to track if warning has been triggered
  bool _warningTriggered = false;

  /// Get the selected session duration
  Duration? get sessionDuration => _sessionDuration;

  /// Get elapsed time in seconds
  int get elapsedSeconds => _accumulatedTime.inSeconds;

  /// Get remaining time in seconds
  int get remainingSeconds {
    if (_sessionDuration == null) return 0;
    final remaining = _sessionDuration!.inSeconds - elapsedSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Get elapsed time as Duration
  Duration get elapsedTime => _accumulatedTime;

  /// Get remaining time as Duration
  Duration get remainingTime => Duration(seconds: remainingSeconds);

  /// Check if timer is currently running
  bool get isRunning => _sessionTimer != null && !_isPaused;

  /// Check if timer is paused
  bool get isPaused => _isPaused;

  /// Check if session has expired
  bool get isExpired =>
      _sessionDuration != null && elapsedSeconds >= _sessionDuration!.inSeconds;

  /// Set the session duration
  void setSessionDuration(Duration duration) {
    if (kDebugMode) {
      debugPrint(
          '[TimerManager] Session duration set to ${duration.inMinutes} minutes');
    }
    _sessionDuration = duration;
    _warningTriggered = false; // Reset warning flag
  }

  /// Start the session timer
  void startTimer() {
    if (_sessionTimer != null) {
      if (kDebugMode) {
        debugPrint('[TimerManager] Timer already running');
      }
      return;
    }

    if (_sessionDuration == null) {
      if (kDebugMode) {
        debugPrint(
            '[TimerManager] Cannot start timer without session duration');
      }
      return;
    }

    _sessionStartTime = DateTime.now();
    _isPaused = false;

    if (kDebugMode) {
      debugPrint('[TimerManager] Starting session timer');
    }

    // Emit initial update so UI shows correct starting remaining value immediately
    _updateElapsedTime(forceEmit: true);
    // Create a periodic timer that fires every second
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        _updateElapsedTime();
      }
    });
  }

  /// Pause the timer
  void pauseTimer() {
    if (_sessionTimer == null || _isPaused) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[TimerManager] Pausing timer at ${elapsedSeconds} seconds');
    }

    _isPaused = true;
    // Save accumulated time when pausing
    if (_sessionStartTime != null) {
      _accumulatedTime += DateTime.now().difference(_sessionStartTime!);
      _sessionStartTime = null;
    }
  }

  /// Resume the timer
  void resumeTimer() {
    if (_sessionTimer == null || !_isPaused) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '[TimerManager] Resuming timer from ${elapsedSeconds} seconds');
    }

    _isPaused = false;
    _sessionStartTime = DateTime.now();
  }

  /// Stop and reset the timer
  void stopTimer() {
    if (kDebugMode) {
      debugPrint('[TimerManager] Stopping timer at ${elapsedSeconds} seconds');
    }

    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionStartTime = null;
    _accumulatedTime = Duration.zero;
    _isPaused = false;
    _warningTriggered = false;
  }

  /// Update elapsed time and trigger callbacks
  void _updateElapsedTime({bool forceEmit = false}) {
    if (_sessionStartTime != null) {
      // Calculate total elapsed time
      final currentSessionTime = DateTime.now().difference(_sessionStartTime!);
      final totalElapsed = _accumulatedTime + currentSessionTime;

      // Only update if time actually changed (to handle sub-second timing)
      if (forceEmit || totalElapsed.inSeconds > _accumulatedTime.inSeconds) {
        if (!forceEmit) {
          _accumulatedTime = _accumulatedTime + const Duration(seconds: 1);
        }

        // Trigger time update callback
        onTimeUpdate?.call(elapsedSeconds, remainingSeconds);

        // Check for time warning (5 minutes remaining)
        if (!_warningTriggered &&
            remainingSeconds <= 300 &&
            remainingSeconds > 0) {
          _warningTriggered = true;
          onTimeWarning?.call();
          if (kDebugMode) {
            debugPrint(
                '[TimerManager] Time warning triggered - 5 minutes remaining');
          }
        }

        // Check for session expiration
        if (isExpired) {
          if (kDebugMode) {
            debugPrint('[TimerManager] Session time expired');
          }
          onSessionExpired?.call();
          stopTimer(); // Auto-stop on expiration
        }
      }
    }
  }

  /// Format time for display (MM:SS)
  String formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Get formatted elapsed time
  String get formattedElapsedTime => formatTime(elapsedSeconds);

  /// Get formatted remaining time
  String get formattedRemainingTime => formatTime(remainingSeconds);

  /// Get session progress as percentage (0.0 to 1.0)
  double get sessionProgress {
    if (_sessionDuration == null || _sessionDuration!.inSeconds == 0) {
      return 0.0;
    }
    final progress = elapsedSeconds / _sessionDuration!.inSeconds;
    return progress.clamp(0.0, 1.0);
  }

  /// Dispose of resources
  void dispose() {
    if (kDebugMode) {
      debugPrint('[TimerManager] Disposing timer resources');
    }
    stopTimer();
    onTimeUpdate = null;
    onSessionExpired = null;
    onTimeWarning = null;
  }

  /// Get a summary of current timer state
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
