import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';

// Optional Firebase imports - add if using Firebase Crashlytics
// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// import 'package:firebase_analytics/firebase_analytics.dart';

/// A centralized logging service that properly handles
/// logging based on build mode (debug vs release)
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();

  // Singleton factory constructor
  factory LoggingService() => _instance;

  // Private constructor
  LoggingService._internal();

  // Configurable log level
  LogLevel _logLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;

  // Flag to enable additional analytics logging
  bool _enableAnalyticsLogging = false;

  // Flag to enable or disable Firebase Crashlytics integration
  bool _crashlyticsEnabled = false;

  // Flag to determine if this is a debug build (cached for performance)
  final bool _isDebugBuild = kDebugMode;

  /// Configure the log level
  void setLogLevel(LogLevel level) {
    _logLevel = level;
  }

  /// Enable/disable analytics logging
  void setAnalyticsLogging(bool enabled) {
    _enableAnalyticsLogging = enabled;
  }

  /// Enable/disable Crashlytics integration
  void setCrashlyticsEnabled(bool enabled) {
    _crashlyticsEnabled = enabled;
  }

  /// Log a debug message - only shown in debug builds
  void debug(String message, {String? tag}) {
    if (_isDebugBuild && _logLevel.index >= LogLevel.debug.index) {
      _printLog('DEBUG', tag, message);
    }
  }

  /// Log info - minimal info that can be shown in release for important events
  void info(String message, {String? tag}) {
    if (_logLevel.index >= LogLevel.info.index) {
      if (_isDebugBuild) {
        _printLog('INFO', tag, message);
      } else {
        // Use dart:developer log for release - will show in device logs but not console
        // This avoids printing to the console in release mode
        developer.log(message, name: tag ?? 'APP');
      }
    }
  }

  /// Log a warning - shown in both debug and release for important warnings
  void warning(String message, {String? tag, dynamic error}) {
    if (_logLevel.index >= LogLevel.warning.index) {
      if (_isDebugBuild) {
        _printLog('WARNING', tag, message);
        if (error != null) {
          debugPrint('Warning details: $error');
        }
      } else {
        developer.log(message, name: tag ?? 'WARNING');

        // Optionally log to Crashlytics as non-fatal
        if (error != null) {
          _logToCrashlytics('WARNING: $message\nDetails: $error');
        } else {
          _logToCrashlytics('WARNING: $message');
        }
      }
    }
  }

  /// Log an error - always shown and potentially reported
  void error(String message,
      {String? tag, dynamic error, StackTrace? stackTrace}) {
    if (_logLevel.index >= LogLevel.error.index) {
      if (_isDebugBuild) {
        _printLog('ERROR', tag, message);
        if (error != null) {
          debugPrint('Error details: $error');
        }
        if (stackTrace != null) {
          debugPrint('Stack trace: $stackTrace');
        }
      } else {
        developer.log(message,
            name: tag ?? 'ERROR', error: error, stackTrace: stackTrace);

        // Log to crashlytics in release mode
        if (_crashlyticsEnabled) {
          _recordError(message, error, stackTrace);
        }
      }
    }
  }

  /// Log an analytics event - generally for user actions and events
  void analytics(String eventName,
      {Map<String, dynamic>? parameters, String? tag}) {
    if (_enableAnalyticsLogging && _isDebugBuild) {
      _printLog('ANALYTICS', tag, 'Event: $eventName, Params: $parameters');
    }

    // In release, we would send to an analytics service
    // This is left as a commented example - add the actual implementation
    // if needed and Firebase Analytics is available
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

  /// Standard format for log messages in debug mode
  void _printLog(String level, String? tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final tagStr = tag != null ? '[$tag] ' : '';
    debugPrint('$timestamp | $level | ${tagStr}$message');
  }

  /// Helper to log to Firebase Crashlytics
  void _logToCrashlytics(String message) {
    if (!_isDebugBuild && _crashlyticsEnabled) {
      // Example Firebase Crashlytics integration
      // This is left as a commented example - uncomment if Crashlytics is added
      /*
      try {
        FirebaseCrashlytics.instance.log(message);
      } catch (e) {
        // Fallback if Crashlytics fails
        developer.log('Failed to log to Crashlytics: $e', name: 'CRASHLYTICS_ERROR');
      }
      */
    }
  }

  /// Helper to record an error to Firebase Crashlytics
  void _recordError(String message, dynamic error, StackTrace? stackTrace) {
    if (!_isDebugBuild && _crashlyticsEnabled) {
      // Example Firebase Crashlytics integration for errors
      // This is left as a commented example - uncomment if Crashlytics is added
      /*
      try {
        final nonNullError = error ?? message;
        final nonNullStack = stackTrace ?? StackTrace.current;
        FirebaseCrashlytics.instance.recordError(
          nonNullError, 
          nonNullStack,
          reason: message,
          fatal: false
        );
      } catch (e) {
        // Fallback if Crashlytics fails
        developer.log('Failed to record error to Crashlytics: $e', name: 'CRASHLYTICS_ERROR');
      }
      */
    }
  }
}

/// Enum representing different log levels
enum LogLevel {
  debug, // Verbose debugging info
  info, // General information
  warning, // Warnings that don't prevent operation
  error, // Errors that may impact functionality
  none // No logging
}

/// Global instance for easy access throughout the app
final logger = LoggingService();
