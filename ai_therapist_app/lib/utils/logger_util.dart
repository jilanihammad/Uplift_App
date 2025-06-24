import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'logging_service.dart';

/// A centralized logging utility that wraps the logger package.
/// This adapts the logger package to work with our existing LoggingService.
/// It provides a more structured logging approach with console formatting.
class LoggerUtil {
  static final LoggerUtil _instance = LoggerUtil._internal();
  late Logger _logger;
  late PrettyPrinter _printer;

  /// Singleton instance
  factory LoggerUtil() => _instance;

  LoggerUtil._internal() {
    // Configure printer
    _printer = PrettyPrinter(
      methodCount: 0, // Number of method calls to display
      errorMethodCount: 8, // Number of method calls if error occurs
      lineLength: 120, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart, // Print time for each log message
    );

    // Configure logger with custom options
    _logger = Logger(
      printer: _printer,
      // Only log in debug mode by default
      level: kDebugMode ? Level.trace : Level.off,
    );
  }

  /// Set the logging level
  void setLogLevel(Level level) {
    _logger = Logger(
      printer: _printer,
      level: level,
    );
  }

  /// Enable logs in production (use with caution)
  void enableProductionLogs() {
    setLogLevel(Level.info);
  }

  /// Disable all logs
  void disableLogs() {
    setLogLevel(Level.off);
  }

  /// Log a debug message
  void d(String message, [dynamic error, StackTrace? stackTrace]) {
    // Use both the pretty logger for console and the existing LoggingService
    if (kDebugMode) {
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
    logger.debug(message, tag: 'Logger');
  }

  /// Log an info message
  void i(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.i(message, error: error, stackTrace: stackTrace);
    }
    logger.info(message, tag: 'Logger');
  }

  /// Log a warning message
  void w(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.w(message, error: error, stackTrace: stackTrace);
    }
    logger.warning(message, tag: 'Logger', error: error);
  }

  /// Log an error message
  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.e(message, error: error, stackTrace: stackTrace);
    }
    logger.error(message, tag: 'Logger', error: error, stackTrace: stackTrace);
  }

  /// Log a verbose message (debug only)
  void v(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.t(message, error: error, stackTrace: stackTrace);
    }
    logger.debug(message, tag: 'Logger-Verbose');
  }
}

/// Global logger instance for easy access
final log = LoggerUtil();
