import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();
  LogLevel _logLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;
  bool _enableAnalyticsLogging = false;
  bool _crashlyticsEnabled = false;
  final bool _isDebugBuild = kDebugMode;
  void setLogLevel(LogLevel level) {
    _logLevel = level;
  }
  void setAnalyticsLogging(bool enabled) {
    _enableAnalyticsLogging = enabled;
  }
  void setCrashlyticsEnabled(bool enabled) {
    _crashlyticsEnabled = enabled;
  }
  void debug(String message, {String? tag}) {
    if (_isDebugBuild && _logLevel.index >= LogLevel.debug.index) {
      _printLog('DEBUG', tag, message);
    }
  }
  void info(String message, {String? tag}) {
    if (_logLevel.index >= LogLevel.info.index) {
      if (_isDebugBuild) {
        _printLog('INFO', tag, message);
      } else {
        developer.log(message, name: tag ?? 'APP');
      }
    }
  }
  void warning(String message, {String? tag, dynamic error}) {
    if (_logLevel.index >= LogLevel.warning.index) {
      if (_isDebugBuild) {
        _printLog('WARNING', tag, message);
        if (error != null) {
        }
      } else {
        developer.log(message, name: tag ?? 'WARNING');
        if (error != null) {
          _logToCrashlytics('WARNING: $message\nDetails: $error');
        } else {
          _logToCrashlytics('WARNING: $message');
        }
      }
    }
  }
  void error(String message,
      {String? tag, dynamic error, StackTrace? stackTrace}) {
    if (_logLevel.index >= LogLevel.error.index) {
      if (_isDebugBuild) {
        _printLog('ERROR', tag, message);
        if (error != null) {
        }
        if (stackTrace != null) {
        }
      } else {
        developer.log(message,
            name: tag ?? 'ERROR', error: error, stackTrace: stackTrace);
        if (_crashlyticsEnabled) {
          _recordError(message, error, stackTrace);
        }
      }
    }
  }
  void analytics(String eventName,
      {Map<String, dynamic>? parameters, String? tag}) {
    if (_enableAnalyticsLogging && _isDebugBuild) {
      _printLog('ANALYTICS', tag, 'Event: $eventName, Params: $parameters');
    }
    /*
    if (!_isDebugBuild) {
      try {
        FirebaseAnalytics.instance.logEvent(name: eventName, parameters: parameters);
      } catch (e) {
        developer.log('Failed to log analytics event: $e', name: 'ANALYTICS_ERROR');
      }
    }
    */
  }
  void _printLog(String level, String? tag, String message) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final tagStr = tag != null ? '[$tag] ' : '';
  }
  void _logToCrashlytics(String message) {
    if (_isDebugBuild || !_crashlyticsEnabled) {
      return;
    }
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (e) {
      developer.log('Failed to log to Crashlytics: $e',
          name: 'CRASHLYTICS_ERROR');
    }
  }
  void _recordError(String message, dynamic error, StackTrace? stackTrace) {
    if (_isDebugBuild || !_crashlyticsEnabled) {
      return;
    }
    try {
      final nonNullError = error ?? message;
      final nonNullStack = stackTrace ?? StackTrace.current;
      FirebaseCrashlytics.instance.recordError(
        nonNullError,
        nonNullStack,
        reason: message,
        fatal: false,
      );
    } catch (e) {
      developer.log('Failed to record error to Crashlytics: $e',
          name: 'CRASHLYTICS_ERROR');
    }
  }
}
enum LogLevel {
  debug, // Verbose debugging info
  info, // General information
  warning, // Warnings that don't prevent operation
  error, // Errors that may impact functionality
  none // No logging
}
final logger = LoggingService();
