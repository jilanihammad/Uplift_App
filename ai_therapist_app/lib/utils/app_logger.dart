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
  
  // ENHANCED: Metrics tracking for production monitoring
  
  /// Track session initialization latency
  static void trackSessionInitLatency(Duration latency) {
    final latencyMs = latency.inMilliseconds;
    
    if (kDebugMode) {
      _logger.i('📊 METRICS: session_init_latency=${latencyMs}ms');
    }
    
    // In production, this would integrate with your analytics service
    // For now, log as structured data that can be parsed by log aggregators
    _logger.i('METRIC|session_init_latency|${latencyMs}ms');
  }
  
  /// Track disposal errors that could indicate service lifecycle issues
  static void trackDisposalError(String serviceName, String error) {
    if (kDebugMode) {
      _logger.w('📊 METRICS: disposed_service_error service=$serviceName error=$error');
    }
    
    // Structured logging for production monitoring
    _logger.w('METRIC|disposed_service_error|service=$serviceName|error=$error');
  }
  
  /// Track service registration cleanup
  static void trackServiceCleanup(String serviceName, bool success) {
    if (kDebugMode) {
      _logger.d('📊 METRICS: service_cleanup service=$serviceName success=$success');
    }
    
    // Track cleanup success/failure for monitoring
    _logger.i('METRIC|service_cleanup|service=$serviceName|success=$success');
  }
  
  /// Track async disposal performance
  static void trackAsyncDisposalTime(Duration duration, int serviceCount) {
    final durationMs = duration.inMilliseconds;
    
    if (kDebugMode) {
      _logger.d('📊 METRICS: async_disposal_time=${durationMs}ms services=$serviceCount');
    }
    
    _logger.i('METRIC|async_disposal_time|${durationMs}ms|services=$serviceCount');
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