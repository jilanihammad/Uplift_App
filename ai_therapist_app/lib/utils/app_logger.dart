import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logging utility for the AI Therapist App
/// 
/// Usage:
/// - AppLogger.d() for debug info (only in debug mode)
/// - AppLogger.i() for info messages
/// - AppLogger.w() for warnings
/// - AppLogger.e() for errors
///
/// In production builds, debug messages are automatically filtered out.
class AppLogger {
  static late final Logger _logger;
  
  static void initialize() {
    _logger = Logger(
      level: kDebugMode ? Level.debug : Level.info,
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 3,
        lineLength: 120,
        colors: true,
        printEmojis: false, // Remove emojis from logs
        dateTimeFormat: DateTimeFormat.none,
      ),
      filter: ProductionFilter(), // Only show logs in debug mode for debug level
    );
  }
  
  /// Debug logs - only shown in debug builds
  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
  }
  
  /// Info logs - shown in all builds but quieter
  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }
  
  /// Warning logs
  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }
  
  /// Error logs
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
  
  /// Verbose logs for very detailed debugging (only in debug mode)
  static void v(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.t(message, error: error, stackTrace: stackTrace);
    }
  }
}

/// Custom filter that respects debug mode for debug messages
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (event.level == Level.debug && !kDebugMode) {
      return false;
    }
    return true;
  }
}