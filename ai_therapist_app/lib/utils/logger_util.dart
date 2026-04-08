import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'logging_service.dart';
class LoggerUtil {
  static final LoggerUtil _instance = LoggerUtil._internal();
  late Logger _logger;
  late PrettyPrinter _printer;
  factory LoggerUtil() => _instance;
  LoggerUtil._internal() {
    _printer = PrettyPrinter(
      methodCount: 0, // Number of method calls to display
      errorMethodCount: 8, // Number of method calls if error occurs
      lineLength: 120, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      dateTimeFormat: DateTimeFormat
          .onlyTimeAndSinceStart, // Print time for each log message
    );
    _logger = Logger(
      printer: _printer,
      level: kDebugMode ? Level.trace : Level.off,
    );
  }
  void setLogLevel(Level level) {
    _logger = Logger(
      printer: _printer,
      level: level,
    );
  }
  void enableProductionLogs() {
    setLogLevel(Level.info);
  }
  void disableLogs() {
    setLogLevel(Level.off);
  }
  void d(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.debug(message, tag: 'Logger');
  }
  void i(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.info(message, tag: 'Logger');
  }
  void w(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.warning(message, tag: 'Logger', error: error);
  }
  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.error(message, tag: 'Logger', error: error, stackTrace: stackTrace);
  }
  void v(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.debug(message, tag: 'Logger-Verbose');
  }
}
final log = LoggerUtil();
