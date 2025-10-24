// lib/utils/timezone_helper.dart

import 'package:flutter/foundation.dart';

class TimezoneHelper {
  /// Initialize the timezone helper (simplified for mobile)
  static void init() {
    if (kDebugMode) {
      final now = DateTime.now();
      print(
          '[TimezoneHelper] Device timezone: ${now.timeZoneName}, offset: ${now.timeZoneOffset}');
      print('[TimezoneHelper] Current local time: $now');
    }
  }

  /// Get current time in the device's local timezone
  static DateTime now() {
    return DateTime.now();
  }

  /// Convert a DateTime to the local timezone
  static DateTime toLocal(DateTime dateTime) {
    // If it's already a local DateTime, return as-is
    if (!dateTime.isUtc) {
      return dateTime;
    }

    // Convert UTC to local
    return dateTime.toLocal();
  }

  /// Format a DateTime with timezone awareness
  static String formatWithTimezone(DateTime dateTime) {
    final localDateTime = toLocal(dateTime);
    return '${localDateTime.toString()} (${localDateTime.timeZoneName})';
  }
}
