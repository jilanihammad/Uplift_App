import 'package:flutter/foundation.dart';
import 'dart:async';

/// TTS Streaming Monitor
///
/// Provides comprehensive monitoring and telemetry for TTS streaming performance.
/// Critical for safe production rollout with instant rollback capability.
class TTSStreamingMonitor {
  static final TTSStreamingMonitor _instance = TTSStreamingMonitor._internal();
  factory TTSStreamingMonitor() => _instance;
  TTSStreamingMonitor._internal();

  // Monitoring counters
  int _totalStreamingAttempts = 0;
  int _successfulStreams = 0;
  int _failedStreams = 0;
  int _bufferUnderruns = 0;
  int _fallbacksToFullBuffer = 0;
  int _memoryWarnings = 0;

  // OPUS-specific metrics
  int _opusStreamingAttempts = 0;
  int _opusSuccessfulStreams = 0;
  int _opusFailedStreams = 0;
  int _opusEofBeforeOpusTags = 0;
  int _opusHeaderBufferTimeouts = 0;
  int _opusToWavFallbacks = 0;

  // Performance tracking
  final List<int> _latencyMeasurements = [];
  final List<int> _heapSizeMeasurements = [];
  int _maxHeapSize = 0;

  // Error tracking
  final Map<String, int> _errorCounts = {};
  final List<String> _recentErrors = [];

  // Timing
  DateTime? _lastStreamStart;
  DateTime? _lastSuccessfulStream;

  // Configuration
  static const int _maxRecentErrors = 50;
  static const int _maxLatencyMeasurements = 100;
  static const int _maxHeapMeasurements = 100;

  /// Record the start of a TTS streaming attempt
  void recordStreamingStart() {
    _totalStreamingAttempts++;
    _lastStreamStart = DateTime.now();

    if (kDebugMode) {
      debugPrint(
          '🎯 TTSStreamingMonitor: Stream attempt #$_totalStreamingAttempts started');
    }
  }

  /// Record a successful TTS streaming completion
  void recordStreamingSuccess({required int latencyMs}) {
    _successfulStreams++;
    _lastSuccessfulStream = DateTime.now();

    // Track latency
    _latencyMeasurements.add(latencyMs);
    if (_latencyMeasurements.length > _maxLatencyMeasurements) {
      _latencyMeasurements.removeAt(0);
    }

    if (kDebugMode) {
      debugPrint(
          '✅ TTSStreamingMonitor: Successful stream (latency: ${latencyMs}ms)');
      debugPrint('📊 Success rate: ${(successRate * 100).toStringAsFixed(1)}%');
    }
  }

  /// Record a failed TTS streaming attempt
  void recordStreamingFailure(String error) {
    _failedStreams++;

    // Track error types
    _errorCounts[error] = (_errorCounts[error] ?? 0) + 1;

    // Track recent errors
    _recentErrors.add('${DateTime.now().toIso8601String()}: $error');
    if (_recentErrors.length > _maxRecentErrors) {
      _recentErrors.removeAt(0);
    }

    if (kDebugMode) {
      debugPrint('❌ TTSStreamingMonitor: Stream failed - $error');
      debugPrint('📊 Failure rate: ${(failureRate * 100).toStringAsFixed(1)}%');
    }
  }

  /// Record a buffer underrun event
  void recordBufferUnderrun() {
    _bufferUnderruns++;

    if (kDebugMode) {
      debugPrint(
          '⚠️ TTSStreamingMonitor: Buffer underrun detected (#$_bufferUnderruns)');
    }
  }

  /// Record fallback to full buffer mode
  void recordFallbackToFullBuffer(String reason) {
    _fallbacksToFullBuffer++;

    if (kDebugMode) {
      debugPrint('🔄 TTSStreamingMonitor: Fallback to full buffer - $reason');
    }
  }

  /// Record memory usage measurement
  void recordHeapSize(int heapSizeBytes) {
    _heapSizeMeasurements.add(heapSizeBytes);
    if (_heapSizeMeasurements.length > _maxHeapMeasurements) {
      _heapSizeMeasurements.removeAt(0);
    }

    if (heapSizeBytes > _maxHeapSize) {
      _maxHeapSize = heapSizeBytes;
    }

    // Check for memory warning threshold (>50MB growth)
    if (heapSizeBytes > 50 * 1024 * 1024) {
      _memoryWarnings++;
      if (kDebugMode) {
        debugPrint(
            '⚠️ TTSStreamingMonitor: Memory warning - heap size: ${(heapSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');
      }
    }
  }

  // ====== OPUS-Specific Monitoring Methods ======

  /// Record the start of an OPUS TTS streaming attempt
  void recordOpusStreamingStart() {
    _opusStreamingAttempts++;
    recordStreamingStart(); // Also record general streaming start

    if (kDebugMode) {
      debugPrint(
          '🎵 TTSStreamingMonitor: OPUS stream attempt #$_opusStreamingAttempts started');
    }
  }

  /// Record a successful OPUS streaming completion
  void recordOpusStreamingSuccess({required int latencyMs}) {
    _opusSuccessfulStreams++;
    recordStreamingSuccess(latencyMs: latencyMs); // Also record general success

    if (kDebugMode) {
      debugPrint(
          '✅ TTSStreamingMonitor: OPUS stream successful (latency: ${latencyMs}ms)');
      debugPrint(
          '📊 OPUS success rate: ${(opusSuccessRate * 100).toStringAsFixed(1)}%');
    }
  }

  /// Record a failed OPUS streaming attempt
  void recordOpusStreamingFailure(String error) {
    _opusFailedStreams++;
    recordStreamingFailure('OPUS: $error'); // Also record general failure

    if (kDebugMode) {
      debugPrint('❌ TTSStreamingMonitor: OPUS stream failed - $error');
      debugPrint(
          '📊 OPUS failure rate: ${(opusFailureRate * 100).toStringAsFixed(1)}%');
    }
  }

  /// Record OPUS stream ending before OpusTags header received
  void recordOpusEofBeforeOpusTags() {
    _opusEofBeforeOpusTags++;

    if (kDebugMode) {
      debugPrint(
          '⚠️ TTSStreamingMonitor: OPUS EOF before OpusTags header (#$_opusEofBeforeOpusTags)');
    }
  }

  /// Record OPUS header buffer timeout
  void recordOpusHeaderTimeout() {
    _opusHeaderBufferTimeouts++;

    if (kDebugMode) {
      debugPrint(
          '⏰ TTSStreamingMonitor: OPUS header buffer timeout (#$_opusHeaderBufferTimeouts)');
    }
  }

  /// Record fallback from OPUS to WAV format
  void recordOpusToWavFallback(String reason) {
    _opusToWavFallbacks++;

    if (kDebugMode) {
      debugPrint(
          '🔄 TTSStreamingMonitor: OPUS→WAV fallback - $reason (#$_opusToWavFallbacks)');
    }
  }

  /// Get success rate (0.0 to 1.0)
  double get successRate {
    if (_totalStreamingAttempts == 0) return 1.0;
    return _successfulStreams / _totalStreamingAttempts;
  }

  /// Get failure rate (0.0 to 1.0)
  double get failureRate {
    if (_totalStreamingAttempts == 0) return 0.0;
    return _failedStreams / _totalStreamingAttempts;
  }

  /// Get buffer underrun rate (0.0 to 1.0)
  double get bufferUnderrunRate {
    if (_totalStreamingAttempts == 0) return 0.0;
    return _bufferUnderruns / _totalStreamingAttempts;
  }

  /// Get average latency in milliseconds
  double get averageLatencyMs {
    if (_latencyMeasurements.isEmpty) return 0.0;
    return _latencyMeasurements.reduce((a, b) => a + b) /
        _latencyMeasurements.length;
  }

  /// Get current heap size in bytes
  int get currentHeapSize {
    return _heapSizeMeasurements.isNotEmpty ? _heapSizeMeasurements.last : 0;
  }

  /// Get maximum recorded heap size in bytes
  int get maxHeapSize => _maxHeapSize;

  // ====== OPUS-Specific Getters ======

  /// Get OPUS success rate (0.0 to 1.0)
  double get opusSuccessRate {
    if (_opusStreamingAttempts == 0) return 1.0;
    return _opusSuccessfulStreams / _opusStreamingAttempts;
  }

  /// Get OPUS failure rate (0.0 to 1.0)
  double get opusFailureRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusFailedStreams / _opusStreamingAttempts;
  }

  /// Get OPUS EOF before OpusTags rate (0.0 to 1.0)
  double get opusEofBeforeOpusTagsRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusEofBeforeOpusTags / _opusStreamingAttempts;
  }

  /// Get OPUS header timeout rate (0.0 to 1.0)
  double get opusHeaderTimeoutRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusHeaderBufferTimeouts / _opusStreamingAttempts;
  }

  /// Get OPUS to WAV fallback rate (0.0 to 1.0)
  double get opusToWavFallbackRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusToWavFallbacks / _opusStreamingAttempts;
  }

  /// Check if streaming health is good for production
  bool get isHealthy {
    // Health criteria based on engineer's requirements
    final bool successRateOk = successRate >= 0.999; // >99.9%
    final bool underrunRateOk = bufferUnderrunRate <= 0.001; // <0.1%
    final bool memoryUsageOk = _memoryWarnings == 0 ||
        (_memoryWarnings / _totalStreamingAttempts) <= 0.01; // <1%

    return successRateOk && underrunRateOk && memoryUsageOk;
  }

  /// Check if immediate rollback is needed
  bool get needsRollback {
    // Immediate rollback triggers
    final bool highFailureRate = failureRate > 0.01; // >1% failure rate
    final bool highUnderrunRate =
        bufferUnderrunRate > 0.05; // >5% underrun rate
    final bool recentErrors = _recentErrors.length > 10 &&
        _recentErrors.skip(_recentErrors.length - 10).any((error) =>
            DateTime.now()
                .difference(DateTime.parse(error.split(':')[0]))
                .inMinutes <
            5);

    return highFailureRate || highUnderrunRate || recentErrors;
  }

  /// Get comprehensive monitoring report
  Map<String, dynamic> getMonitoringReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'streaming_attempts': _totalStreamingAttempts,
      'successful_streams': _successfulStreams,
      'failed_streams': _failedStreams,
      'success_rate': successRate,
      'failure_rate': failureRate,
      'buffer_underruns': _bufferUnderruns,
      'underrun_rate': bufferUnderrunRate,
      'fallbacks_to_full_buffer': _fallbacksToFullBuffer,
      'memory_warnings': _memoryWarnings,
      'average_latency_ms': averageLatencyMs,
      'current_heap_size_mb': currentHeapSize / 1024 / 1024,
      'max_heap_size_mb': maxHeapSize / 1024 / 1024,
      'is_healthy': isHealthy,
      'needs_rollback': needsRollback,
      'error_counts': Map.from(_errorCounts),
      'recent_errors': List.from(_recentErrors.take(10)), // Last 10 errors

      // OPUS-specific metrics
      'opus_streaming_attempts': _opusStreamingAttempts,
      'opus_successful_streams': _opusSuccessfulStreams,
      'opus_failed_streams': _opusFailedStreams,
      'opus_success_rate': opusSuccessRate,
      'opus_failure_rate': opusFailureRate,
      'opus_eof_before_opus_tags': _opusEofBeforeOpusTags,
      'opus_eof_before_opus_tags_rate': opusEofBeforeOpusTagsRate,
      'opus_header_timeouts': _opusHeaderBufferTimeouts,
      'opus_header_timeout_rate': opusHeaderTimeoutRate,
      'opus_to_wav_fallbacks': _opusToWavFallbacks,
      'opus_to_wav_fallback_rate': opusToWavFallbackRate,
    };
  }

  /// Log current monitoring status
  void logStatus() {
    if (kDebugMode) {
      debugPrint('📊 TTS Streaming Monitor Status:');
      debugPrint('  Attempts: $_totalStreamingAttempts');
      debugPrint('  Success Rate: ${(successRate * 100).toStringAsFixed(1)}%');
      debugPrint(
          '  Buffer Underruns: $_bufferUnderruns (${(bufferUnderrunRate * 100).toStringAsFixed(1)}%)');
      debugPrint('  Avg Latency: ${averageLatencyMs.toStringAsFixed(0)}ms');
      debugPrint(
          '  Heap Usage: ${(currentHeapSize / 1024 / 1024).toStringAsFixed(1)} MB');
      debugPrint('  Health Status: ${isHealthy ? "HEALTHY" : "NEEDS ATTENTION"}');
      if (needsRollback) {
        debugPrint('  🚨 ROLLBACK RECOMMENDED 🚨');
      }
    }
  }

  /// Reset all monitoring data (for testing)
  void reset() {
    _totalStreamingAttempts = 0;
    _successfulStreams = 0;
    _failedStreams = 0;
    _bufferUnderruns = 0;
    _fallbacksToFullBuffer = 0;
    _memoryWarnings = 0;

    // Reset OPUS-specific metrics
    _opusStreamingAttempts = 0;
    _opusSuccessfulStreams = 0;
    _opusFailedStreams = 0;
    _opusEofBeforeOpusTags = 0;
    _opusHeaderBufferTimeouts = 0;
    _opusToWavFallbacks = 0;

    _latencyMeasurements.clear();
    _heapSizeMeasurements.clear();
    _maxHeapSize = 0;
    _errorCounts.clear();
    _recentErrors.clear();
    _lastStreamStart = null;
    _lastSuccessfulStream = null;

    if (kDebugMode) {
      debugPrint(
          '🔄 TTSStreamingMonitor: Monitor data reset (including OPUS metrics)');
    }
  }
}
