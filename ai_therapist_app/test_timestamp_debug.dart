import 'package:intl/intl.dart';

void main() {
  print('=== Timestamp Parsing Debug Test ===\n');

  // Test timestamps
  const timestampWithoutZ = "2025-06-29T17:34:37";
  const timestampWithZ = "2025-06-29T17:34:37Z";
  const timestampWithMillis = "2025-06-29T17:34:37.123";
  const timestampWithMillisZ = "2025-06-29T17:34:37.123Z";

  print('Test 1: Parsing timestamp without Z');
  testTimestampParsing(timestampWithoutZ);

  print('\nTest 2: Parsing timestamp with Z');
  testTimestampParsing(timestampWithZ);

  print('\nTest 3: Parsing timestamp with milliseconds');
  testTimestampParsing(timestampWithMillis);

  print('\nTest 4: Parsing timestamp with milliseconds and Z');
  testTimestampParsing(timestampWithMillisZ);

  print('\n=== Testing DateFormatter functions ===\n');
  testDateFormatterFunctions();
}

void testTimestampParsing(String timestamp) {
  print('Input: "$timestamp"');

  try {
    // Method 1: Direct DateTime.parse
    final dt1 = DateTime.parse(timestamp);
    print('  DateTime.parse: Success');
    print('    - isUtc: ${dt1.isUtc}');
    print('    - Local: ${dt1.toLocal()}');
    print('    - UTC: ${dt1.toUtc()}');
    print('    - ISO8601: ${dt1.toIso8601String()}');
  } catch (e) {
    print('  DateTime.parse: FAILED - $e');
  }

  try {
    // Method 2: Try parsing as UTC if no Z
    final dt2 = timestamp.endsWith('Z')
        ? DateTime.parse(timestamp)
        : DateTime.parse('${timestamp}Z');
    print('  Parse with Z added: Success');
    print('    - isUtc: ${dt2.isUtc}');
    print('    - Local: ${dt2.toLocal()}');
  } catch (e) {
    print('  Parse with Z added: FAILED - $e');
  }

  try {
    // Method 3: Parse and ensure UTC
    DateTime dt3;
    if (timestamp.endsWith('Z')) {
      dt3 = DateTime.parse(timestamp);
    } else {
      // Parse as local then convert to UTC
      final local = DateTime.parse(timestamp);
      dt3 = DateTime.utc(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
        local.second,
        local.millisecond,
        local.microsecond,
      );
    }
    print('  Parse ensuring UTC: Success');
    print('    - isUtc: ${dt3.isUtc}');
    print('    - Local: ${dt3.toLocal()}');
  } catch (e) {
    print('  Parse ensuring UTC: FAILED - $e');
  }
}

void testDateFormatterFunctions() {
  final now = DateTime.now();
  final utcNow = now.toUtc();
  const testTimestamp = "2025-06-29T17:34:37";

  print('Testing DateFormatter-like functions:');
  print('Current time: ${now.toIso8601String()}');
  print('Current UTC: ${utcNow.toIso8601String()}');

  // Test formatting patterns
  final formats = [
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-ddTHH:mm:ssZ',
    'yyyy-MM-dd HH:mm:ss',
    'HH:mm',
    'MMM dd, yyyy',
  ];

  for (final format in formats) {
    try {
      final formatter = DateFormat(format);
      final formatted = formatter.format(now);
      print('\nFormat: "$format"');
      print('  Output: "$formatted"');

      // Try parsing back
      try {
        final parsed = formatter.parse(formatted);
        print('  Parse back: Success (${parsed.toIso8601String()})');
      } catch (e) {
        print('  Parse back: FAILED - $e');
      }
    } catch (e) {
      print('\nFormat: "$format" - FAILED: $e');
    }
  }

  // Test specific timestamp parsing
  print('\n\nTesting specific timestamp format from logs:');
  try {
    final logTimestamp = DateTime.parse(testTimestamp);
    print('Parsed log timestamp: ${logTimestamp.toIso8601String()}');

    // Test different display formats
    print('Display formats:');
    print('  - Time only: ${DateFormat('HH:mm').format(logTimestamp)}');
    print('  - Date only: ${DateFormat('MMM dd').format(logTimestamp)}');
    print('  - Full: ${DateFormat('MMM dd, yyyy HH:mm').format(logTimestamp)}');

    // Test relative time
    final diff = now.difference(logTimestamp);
    print('  - Relative: ${_formatRelativeTime(diff)}');
  } catch (e) {
    print('Failed to parse log timestamp: $e');
  }
}

String _formatRelativeTime(Duration difference) {
  if (difference.inSeconds < 60) {
    return '${difference.inSeconds} seconds ago';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes} minutes ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours} hours ago';
  } else {
    return '${difference.inDays} days ago';
  }
}
