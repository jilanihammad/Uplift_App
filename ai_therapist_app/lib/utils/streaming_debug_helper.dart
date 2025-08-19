// lib/utils/streaming_debug_helper.dart

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'logger_util.dart';

/// Debug helper specifically for TTS streaming development
/// 
/// This provides easy control over streaming log verbosity without affecting
/// other parts of the app. Useful for debugging the streaming buffer controller
/// and incremental TTS functionality.
class StreamingDebugHelper {
  static bool _streamingDebugEnabled = kDebugMode;
  static Level _streamingLogLevel = Level.debug;

  /// Enable verbose streaming logs (debug level)
  static void enableStreamingDebug() {
    _streamingDebugEnabled = true;
    _streamingLogLevel = Level.debug;
    log.setLogLevel(Level.debug);
    log.i('Streaming debug logs ENABLED - verbose mode');
  }

  /// Disable streaming debug logs (info level only)
  static void disableStreamingDebug() {
    _streamingDebugEnabled = false;
    _streamingLogLevel = Level.info;
    log.setLogLevel(Level.info);
    log.i('Streaming debug logs DISABLED - info level only');
  }

  /// Set streaming logs to warning level (quiet mode)
  static void setQuietMode() {
    _streamingDebugEnabled = false;
    _streamingLogLevel = Level.warning;
    log.setLogLevel(Level.warning);
    log.i('Streaming logs set to QUIET mode - warnings and errors only');
  }

  /// Reset to default logging based on build mode
  static void resetToDefault() {
    _streamingDebugEnabled = kDebugMode;
    _streamingLogLevel = kDebugMode ? Level.debug : Level.info;
    log.setLogLevel(_streamingLogLevel);
    log.i('Streaming logs reset to DEFAULT - debug=${kDebugMode}');
  }

  /// Check if streaming debug is currently enabled
  static bool get isStreamingDebugEnabled => _streamingDebugEnabled;

  /// Get current streaming log level
  static Level get currentLogLevel => _streamingLogLevel;

  /// Log a streaming debug message (only if streaming debug enabled)
  static void streamingDebug(String message) {
    if (_streamingDebugEnabled) {
      log.d('[STREAMING] $message');
    }
  }

  /// Log a streaming info message
  static void streamingInfo(String message) {
    log.i('[STREAMING] $message');
  }

  /// Log a streaming warning
  static void streamingWarning(String message) {
    log.w('[STREAMING] $message');
  }

  /// Log a streaming error
  static void streamingError(String message, [dynamic error]) {
    log.e('[STREAMING] $message', error);
  }

  /// Print current streaming debug status
  static void printStatus() {
    log.i('=== Streaming Debug Status ===');
    log.i('Enabled: $_streamingDebugEnabled');
    log.i('Level: $_streamingLogLevel');
    log.i('Build Mode: ${kDebugMode ? "Debug" : "Release"}');
    log.i('=============================');
  }
}

/// Extension on LoggerUtil for streaming-specific logging
extension StreamingLogExtension on LoggerUtil {
  /// Log streaming debug info (gated by StreamingDebugHelper)
  void streaming(String message) {
    if (StreamingDebugHelper.isStreamingDebugEnabled) {
      d('[STREAMING] $message');
    }
  }
}