import 'package:flutter/foundation.dart';
import 'logging_service.dart';

/// Controls logging configuration for the app
/// Provides a centralized way to configure logging levels based on the environment
class LoggingConfig {
  // Singleton instance
  static final LoggingConfig _instance = LoggingConfig._internal();

  factory LoggingConfig() => _instance;

  LoggingConfig._internal();

  // Current log level
  LogLevel _currentLogLevel = kDebugMode ? LogLevel.debug : LogLevel.error;

  // Flag to enable analytics
  bool _enableAnalytics = false;

  // Initializes logging configuration
  void init({bool enableVerboseLogsInRelease = false}) {
    // Configure default log levels based on build type
    if (kDebugMode) {
      // In debug mode, show all logs by default
      setLogLevel(LogLevel.debug);
    } else if (kProfileMode) {
      // In profile mode, show info and errors
      setLogLevel(LogLevel.info);
    } else {
      // In release mode, only show errors by default
      // Unless verbose logging is explicitly requested
      setLogLevel(enableVerboseLogsInRelease ? LogLevel.info : LogLevel.error);
    }

    // Log the configuration
    logger.info(
        'Logging configured: level=${_currentLogLevel.toString().split('.').last}, isDebug=$kDebugMode');
  }

  // Set specific log level
  void setLogLevel(LogLevel level) {
    _currentLogLevel = level;
    logger.setLogLevel(level);
  }

  // Enable analytics logging for user events
  void enableAnalytics(bool enable) {
    _enableAnalytics = enable;
    logger.setAnalyticsLogging(enable);
  }

  // Get current log level
  LogLevel get currentLogLevel => _currentLogLevel;

  // Check if a specific log level is enabled
  bool isLogLevelEnabled(LogLevel level) {
    return _currentLogLevel.index >= level.index;
  }

  // Helper methods for checking specific log levels
  bool get isDebugEnabled => isLogLevelEnabled(LogLevel.debug);
  bool get isInfoEnabled => isLogLevelEnabled(LogLevel.info);
  bool get isWarningEnabled => isLogLevelEnabled(LogLevel.warning);
  bool get isErrorEnabled => isLogLevelEnabled(LogLevel.error);
}

// Global instance for easy access
final loggingConfig = LoggingConfig();
