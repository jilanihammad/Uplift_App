import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
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
      filter:
          ProductionFilter(), // Only show logs in debug mode for debug level
    );
  }
  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
  }
  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }
  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }
  static void v(String message, [dynamic error, StackTrace? stackTrace]) {
  }
}
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (event.level == Level.debug && !kDebugMode) {
      return false;
    }
    return true;
  }
}
