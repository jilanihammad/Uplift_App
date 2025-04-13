// lib/utils/logger.dart
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );

  // Log a debug message
  static void d(String message) {
    if (kDebugMode) {
      _logger.d(message);
    }
  }

  // Log an info message
  static void i(String message) {
    if (kDebugMode) {
      _logger.i(message);
    }
  }

  // Log a warning message
  static void w(String message) {
    if (kDebugMode) {
      _logger.w(message);
    }
  }

  // Log an error message with optional stack trace
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.e(message, error, stackTrace);
    }
  }

  // Log a fatal error
  static void wtf(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.wtf(message, error, stackTrace);
    }
  }
}