import 'package:flutter/foundation.dart';
class ThrottledDebugPrint {
  static final Map<String, DateTime> _lastPrintTimes = {};
  static const Duration _throttleInterval =
      Duration(milliseconds: 500); // 500ms throttle
  static void debugPrintThrottled(String message, {String? key}) {
    if (!kDebugMode) return;
    final throttleKey = key ?? message;
    final now = DateTime.now();
    final lastPrint = _lastPrintTimes[throttleKey];
    if (lastPrint != null && now.difference(lastPrint) < _throttleInterval) {
      return; // Skip this print to prevent spam
    }
    _lastPrintTimes[throttleKey] = now;
    if (_lastPrintTimes.length > 100) {
      _cleanupOldEntries(now);
    }
  }
  static void debugPrintThrottledWithCounter(String baseMessage,
      {String? key}) {
    if (!kDebugMode) return;
    final throttleKey = key ?? baseMessage;
    final now = DateTime.now();
    final lastPrint = _lastPrintTimes[throttleKey];
    if (lastPrint != null && now.difference(lastPrint) < _throttleInterval) {
      return; // Skip this print
    }
    final counter = _throttleCounts[throttleKey] ?? 0;
    final message =
        counter > 0 ? '$baseMessage (skipped $counter similar)' : baseMessage;
    _lastPrintTimes[throttleKey] = now;
    _throttleCounts[throttleKey] = 0; // Reset counter after printing
    if (_lastPrintTimes.length > 100) {
      _cleanupOldEntries(now);
    }
  }
  static final Map<String, int> _throttleCounts = {};
  static void _cleanupOldEntries(DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 5));
    _lastPrintTimes.removeWhere((key, time) => time.isBefore(cutoff));
    final remainingKeys = _lastPrintTimes.keys.toSet();
    _throttleCounts.removeWhere((key, count) => !remainingKeys.contains(key));
  }
  static void clearThrottleState() {
    _lastPrintTimes.clear();
    _throttleCounts.clear();
  }
}
void debugPrintThrottledCustom(String message, {String? key}) {
  ThrottledDebugPrint.debugPrintThrottled(message, key: key);
}
void debugPrintThrottledWithCounter(String message, {String? key}) {
  ThrottledDebugPrint.debugPrintThrottledWithCounter(message, key: key);
}
