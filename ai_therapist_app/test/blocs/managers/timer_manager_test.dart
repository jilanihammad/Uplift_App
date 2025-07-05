/// Unit tests for TimerManager
/// 
/// These tests verify the timer functionality of TimerManager including
/// start/stop/pause/resume, callbacks, and time calculations.

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/blocs/managers/timer_manager.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  group('TimerManager', () {
    late TimerManager manager;

    setUp(() {
      manager = TimerManager();
    });

    tearDown(() {
      manager.dispose();
    });

    group('Initialization', () {
      test('initializes with zero values', () {
        expect(manager.elapsedSeconds, 0);
        expect(manager.remainingSeconds, 0);
        expect(manager.isRunning, false);
        expect(manager.isPaused, false);
        expect(manager.isExpired, false);
        expect(manager.sessionDuration, isNull);
        expect(manager.sessionProgress, 0.0);
      });

      test('setSessionDuration updates duration', () {
        manager.setSessionDuration(const Duration(minutes: 30));
        
        expect(manager.sessionDuration, const Duration(minutes: 30));
        expect(manager.remainingSeconds, 1800); // 30 * 60
      });
    });

    group('Timer Control', () {
      test('cannot start timer without duration', () {
        manager.startTimer();
        expect(manager.isRunning, false);
      });

      test('starts timer when duration is set', () {
        manager.setSessionDuration(const Duration(minutes: 10));
        manager.startTimer();
        
        expect(manager.isRunning, true);
        expect(manager.isPaused, false);
      });

      test('ignores start when already running', () {
        manager.setSessionDuration(const Duration(minutes: 10));
        manager.startTimer();
        
        // Try to start again
        manager.startTimer();
        
        expect(manager.isRunning, true);
      });

      test('stops timer and resets values', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          // Let some time pass
          async.elapse(const Duration(seconds: 5));
          
          manager.stopTimer();
          
          expect(manager.isRunning, false);
          expect(manager.elapsedSeconds, 0);
          expect(manager.remainingSeconds, 600); // Back to full duration
        });
      });
    });

    group('Time Tracking', () {
      test('tracks elapsed time correctly', () {
        fakeAsync((async) {
          var updateCount = 0;
          var lastElapsed = 0;
          var lastRemaining = 0;
          
          manager.onTimeUpdate = (elapsed, remaining) {
            updateCount++;
            lastElapsed = elapsed;
            lastRemaining = remaining;
          };
          
          manager.setSessionDuration(const Duration(minutes: 5));
          manager.startTimer();
          
          // Let 10 seconds pass
          async.elapse(const Duration(seconds: 10));
          
          expect(updateCount, 10); // Should update every second
          expect(lastElapsed, 10);
          expect(lastRemaining, 290); // 300 - 10
          expect(manager.elapsedSeconds, 10);
          expect(manager.remainingSeconds, 290);
        });
      });

      test('session progress calculates correctly', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          expect(manager.sessionProgress, 0.0);
          
          // 25% progress (2.5 minutes)
          async.elapse(const Duration(seconds: 150));
          expect(manager.sessionProgress, closeTo(0.25, 0.01));
          
          // 50% progress (5 minutes)
          async.elapse(const Duration(seconds: 150));
          expect(manager.sessionProgress, closeTo(0.5, 0.01));
          
          // 100% progress (10 minutes)
          async.elapse(const Duration(minutes: 5));
          expect(manager.sessionProgress, 1.0);
        });
      });
    });

    group('Pause and Resume', () {
      test('pauses timer correctly', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          // Run for 5 seconds
          async.elapse(const Duration(seconds: 5));
          expect(manager.elapsedSeconds, 5);
          
          // Pause
          manager.pauseTimer();
          expect(manager.isPaused, true);
          expect(manager.isRunning, false);
          
          // Time passes while paused
          async.elapse(const Duration(seconds: 5));
          
          // Time should not have advanced
          expect(manager.elapsedSeconds, 5);
        });
      });

      test('resumes timer correctly', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          // Run for 5 seconds
          async.elapse(const Duration(seconds: 5));
          
          // Pause
          manager.pauseTimer();
          
          // Wait while paused
          async.elapse(const Duration(seconds: 3));
          
          // Resume
          manager.resumeTimer();
          expect(manager.isPaused, false);
          expect(manager.isRunning, true);
          
          // Run for 5 more seconds
          async.elapse(const Duration(seconds: 5));
          
          // Total should be 10 seconds (5 + 5, excluding pause time)
          expect(manager.elapsedSeconds, 10);
        });
      });

      test('handles multiple pause/resume cycles', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          // First cycle: 3 seconds
          async.elapse(const Duration(seconds: 3));
          manager.pauseTimer();
          async.elapse(const Duration(seconds: 2)); // Paused time
          manager.resumeTimer();
          
          // Second cycle: 4 seconds
          async.elapse(const Duration(seconds: 4));
          manager.pauseTimer();
          async.elapse(const Duration(seconds: 1)); // Paused time
          manager.resumeTimer();
          
          // Third cycle: 3 seconds
          async.elapse(const Duration(seconds: 3));
          
          // Total should be 10 seconds (3 + 4 + 3)
          expect(manager.elapsedSeconds, 10);
        });
      });
    });

    group('Callbacks', () {
      test('triggers time warning at 5 minutes remaining', () {
        fakeAsync((async) {
          var warningTriggered = false;
          
          manager.onTimeWarning = () {
            warningTriggered = true;
          };
          
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          // Advance to 4:59 - no warning yet
          async.elapse(const Duration(seconds: 299));
          expect(warningTriggered, false);
          
          // Advance to 5:00 - warning should trigger
          async.elapse(const Duration(seconds: 1));
          expect(warningTriggered, true);
        });
      });

      test('triggers session expired callback', () {
        fakeAsync((async) {
          var expiredTriggered = false;
          
          manager.onSessionExpired = () {
            expiredTriggered = true;
          };
          
          manager.setSessionDuration(const Duration(minutes: 2));
          manager.startTimer();
          
          // Advance to just before expiration
          async.elapse(const Duration(seconds: 119));
          expect(expiredTriggered, false);
          expect(manager.isExpired, false);
          
          // Advance to expiration
          async.elapse(const Duration(seconds: 1));
          expect(expiredTriggered, true);
          expect(manager.isExpired, true);
          expect(manager.isRunning, false); // Auto-stops
        });
      });

      test('warning triggers only once', () {
        fakeAsync((async) {
          var warningCount = 0;
          
          manager.onTimeWarning = () {
            warningCount++;
          };
          
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          // Advance past warning threshold
          async.elapse(const Duration(minutes: 6));
          
          expect(warningCount, 1); // Should only trigger once
        });
      });
    });

    group('Time Formatting', () {
      test('formats time correctly', () {
        expect(manager.formatTime(0), '00:00');
        expect(manager.formatTime(59), '00:59');
        expect(manager.formatTime(60), '01:00');
        expect(manager.formatTime(90), '01:30');
        expect(manager.formatTime(3599), '59:59');
        expect(manager.formatTime(3600), '60:00');
      });

      test('formatted properties work correctly', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 10));
          manager.startTimer();
          
          expect(manager.formattedElapsedTime, '00:00');
          expect(manager.formattedRemainingTime, '10:00');
          
          async.elapse(const Duration(seconds: 75));
          
          expect(manager.formattedElapsedTime, '01:15');
          expect(manager.formattedRemainingTime, '08:45');
        });
      });
    });

    group('Timer State', () {
      test('getTimerState returns complete state', () {
        fakeAsync((async) {
          manager.setSessionDuration(const Duration(minutes: 30));
          manager.startTimer();
          
          async.elapse(const Duration(minutes: 5));
          
          final state = manager.getTimerState();
          
          expect(state['isRunning'], true);
          expect(state['isPaused'], false);
          expect(state['isExpired'], false);
          expect(state['elapsedSeconds'], 300);
          expect(state['remainingSeconds'], 1500);
          expect(state['sessionDurationMinutes'], 30);
          expect(state['sessionProgress'], closeTo(0.167, 0.01));
          expect(state['formattedElapsed'], '05:00');
          expect(state['formattedRemaining'], '25:00');
        });
      });
    });

    group('Edge Cases', () {
      test('handles zero duration gracefully', () {
        manager.setSessionDuration(Duration.zero);
        
        expect(manager.remainingSeconds, 0);
        expect(manager.sessionProgress, 0.0);
        expect(manager.isExpired, true);
      });

      test('handles dispose correctly', () {
        manager.setSessionDuration(const Duration(minutes: 10));
        manager.startTimer();
        
        manager.dispose();
        
        expect(manager.isRunning, false);
        expect(manager.onTimeUpdate, isNull);
        expect(manager.onSessionExpired, isNull);
        expect(manager.onTimeWarning, isNull);
      });

      test('pause/resume when not running does nothing', () {
        manager.pauseTimer();
        expect(manager.isPaused, false);
        
        manager.resumeTimer();
        expect(manager.isRunning, false);
      });
    });
  });
}