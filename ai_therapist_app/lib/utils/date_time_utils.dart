import 'package:flutter/foundation.dart';

/// Normalize ISO-8601 strings emitted by the backend so DateTime.parse can read them.
String normalizeBackendIsoString(String raw) {
  var normalized = raw.trim();
  if (normalized.isEmpty) {
    return normalized;
  }

  // Replace sequences like "+00:00Z" or "-00:00Z" with a single "Z".
  final tzAndZulu = RegExp(r'([+-]\d{2}:\d{2})Z$');
  final match = tzAndZulu.firstMatch(normalized);
  if (match != null) {
    final offset = match.group(1);
    if (offset == '+00:00' || offset == '-00:00') {
      normalized = normalized.replaceRange(match.start, match.end, 'Z');
    } else {
      // Keep the explicit offset but drop the extra Z suffix.
      normalized = normalized.substring(0, normalized.length - 1);
    }
  }

  return normalized;
}

DateTime parseBackendDateTime(String raw) {
  final normalized = normalizeBackendIsoString(raw);
  return DateTime.parse(normalized);
}

DateTime parseBackendDateTimeToUtc(String raw) {
  return parseBackendDateTime(raw).toUtc();
}
