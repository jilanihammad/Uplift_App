// lib/utils/throttled_debug_print.dart

import 'package:flutter/foundation.dart';

/// Throttled debug printing to prevent UI thread blocking from excessive logs
class ThrottledDebugPrint {
  static final Map<String, DateTime> _lastPrintTimes = {};
  static const Duration _throttleInterval =
      Duration(milliseconds: 500); // 500ms throttle

  /// Print a debug message, but throttle identical messages to prevent spam
  static void debugPrintThrottled(String message, {String? key}) {
    if (!kDebugMode) return;

    // Use message as key if no specific key provided
    final throttleKey = key ?? message;
    final now = DateTime.now();

    // Check if we should throttle this message
    final lastPrint = _lastPrintTimes[throttleKey];
    if (lastPrint != null && now.difference(lastPrint) < _throttleInterval) {
      return; // Skip this print to prevent spam
    }

    // Update last print time and print the message
    _lastPrintTimes[throttleKey] = now;
    debugPrint(message);

    // Clean up old entries periodically to prevent memory bloat
    if (_lastPrintTimes.length > 100) {
      _cleanupOldEntries(now);
    }
  }

  /// Print a debug message with counter for repeated messages
  static void debugPrintThrottledWithCounter(String baseMessage,
      {String? key}) {
    if (!kDebugMode) return;

    final throttleKey = key ?? baseMessage;
    final now = DateTime.now();

    // Check if we should throttle this message
    final lastPrint = _lastPrintTimes[throttleKey];
    if (lastPrint != null && now.difference(lastPrint) < _throttleInterval) {
      return; // Skip this print
    }

    // Count how many times this message was throttled
    final counter = _throttleCounts[throttleKey] ?? 0;
    final message =
        counter > 0 ? '$baseMessage (skipped $counter similar)' : baseMessage;

    _lastPrintTimes[throttleKey] = now;
    _throttleCounts[throttleKey] = 0; // Reset counter after printing
    debugPrint(message);

    // Cleanup
    if (_lastPrintTimes.length > 100) {
      _cleanupOldEntries(now);
    }
  }

  static final Map<String, int> _throttleCounts = {};

  /// Increment throttle counter for a message (used internally)
  static void _incrementThrottleCount(String key) {
    _throttleCounts[key] = (_throttleCounts[key] ?? 0) + 1;
  }

  /// Clean up old entries to prevent memory bloat
  static void _cleanupOldEntries(DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 5));

    _lastPrintTimes.removeWhere((key, time) => time.isBefore(cutoff));

    // Also clean up throttle counts for removed keys
    final remainingKeys = _lastPrintTimes.keys.toSet();
    _throttleCounts.removeWhere((key, count) => !remainingKeys.contains(key));
  }

  /// Clear all throttle state (useful for testing)
  static void clearThrottleState() {
    _lastPrintTimes.clear();
    _throttleCounts.clear();
  }
}

/// Convenience function for throttled debug printing
void debugPrintThrottledCustom(String message, {String? key}) {
  ThrottledDebugPrint.debugPrintThrottled(message, key: key);
}

/// Convenience function for throttled debug printing with counter
void debugPrintThrottledWithCounter(String message, {String? key}) {
  ThrottledDebugPrint.debugPrintThrottledWithCounter(message, key: key);
}
