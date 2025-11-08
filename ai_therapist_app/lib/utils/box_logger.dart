import 'package:flutter/foundation.dart';

/// Lightweight utility for consistent, high-signal log framing.
/// Wraps log messages in a single bordered box to prevent duplicated output
/// and makes important state changes easy to scan.
class BoxLogger {
  static const String _topBorder =
      '┌───────────────────────────────────────────────────────────';
  static const String _bottomBorder =
      '└───────────────────────────────────────────────────────────';

  const BoxLogger._();

  static void debug(
    String emoji,
    String component,
    String message, {
    Map<String, String>? details,
  }) {
    if (!kDebugMode) return;
    _emit(emoji, component, message, details: details);
  }

  static void info(
    String emoji,
    String component,
    String message, {
    Map<String, String>? details,
  }) {
    _emit(emoji, component, message, details: details);
  }

  static void stateChange(
    String component,
    String from,
    String to, {
    String emoji = '🔁',
    int? generation,
    Map<String, String>? details,
  }) {
    final formattedDetails = <String, String>{
      if (generation != null) 'gen': '$generation',
      ...?details,
    };
    _emit(emoji, component, '$from → $to', details: formattedDetails);
  }

  static void _emit(
    String emoji,
    String component,
    String message, {
    Map<String, String>? details,
  }) {
    final buffer = StringBuffer()
      ..writeln(_topBorder)
      ..writeln('│ $emoji [$component] $message');

    if (details != null && details.isNotEmpty) {
      for (final entry in details.entries) {
        buffer.writeln('│    ${entry.key}: ${entry.value}');
      }
    }

    buffer.writeln(_bottomBorder);
    debugPrint(buffer.toString());
  }
}
