import 'package:flutter/foundation.dart';
import 'logging_service.dart';
class LoggingConfig {
  static final LoggingConfig _instance = LoggingConfig._internal();
  factory LoggingConfig() => _instance;
  LoggingConfig._internal();
  LogLevel _currentLogLevel = kDebugMode ? LogLevel.debug : LogLevel.error;
  bool _enableAnalytics = false;
  bool _enableVerboseDebug = false;
  void init(
      {bool enableVerboseLogsInRelease = false,
      bool enableVerboseDebug = false}) {
    _enableVerboseDebug = kDebugMode && enableVerboseDebug;
    logger.info(
        'Logging configured: level=${_currentLogLevel.toString().split('.').last}, isDebug=$kDebugMode, verboseDebug=$_enableVerboseDebug');
  }
  void setLogLevel(LogLevel level) {
    _currentLogLevel = level;
    logger.setLogLevel(level);
  }
  void enableAnalytics(bool enable) {
    _enableAnalytics = enable;
    logger.setAnalyticsLogging(enable);
  }
  void enableVerboseDebug(bool enable) {
    _enableVerboseDebug = kDebugMode && enable;
  }
  LogLevel get currentLogLevel => _currentLogLevel;
  bool isLogLevelEnabled(LogLevel level) {
    return _currentLogLevel.index >= level.index;
  }
  bool get isDebugEnabled => isLogLevelEnabled(LogLevel.debug);
  bool get isInfoEnabled => isLogLevelEnabled(LogLevel.info);
  bool get isWarningEnabled => isLogLevelEnabled(LogLevel.warning);
  bool get isErrorEnabled => isLogLevelEnabled(LogLevel.error);
  bool get isVerboseDebugEnabled => _enableVerboseDebug;
}
final loggingConfig = LoggingConfig();
