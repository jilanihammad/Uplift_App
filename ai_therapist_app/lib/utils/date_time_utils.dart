String normalizeBackendIsoString(String raw) {
  var normalized = raw.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  final tzAndZulu = RegExp(r'([+-]\d{2}:\d{2})Z$');
  final match = tzAndZulu.firstMatch(normalized);
  if (match != null) {
    final offset = match.group(1);
    if (offset == '+00:00' || offset == '-00:00') {
      normalized = normalized.replaceRange(match.start, match.end, 'Z');
    } else {
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
