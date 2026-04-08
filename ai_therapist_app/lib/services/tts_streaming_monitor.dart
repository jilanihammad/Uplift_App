import 'package:ai_therapist_app/utils/date_time_utils.dart';
class TTSStreamingMonitor {
  static final TTSStreamingMonitor _instance = TTSStreamingMonitor._internal();
  factory TTSStreamingMonitor() => _instance;
  TTSStreamingMonitor._internal();
  int _totalStreamingAttempts = 0;
  int _successfulStreams = 0;
  int _failedStreams = 0;
  int _bufferUnderruns = 0;
  int _fallbacksToFullBuffer = 0;
  int _memoryWarnings = 0;
  int _opusStreamingAttempts = 0;
  int _opusSuccessfulStreams = 0;
  int _opusFailedStreams = 0;
  int _opusEofBeforeOpusTags = 0;
  int _opusHeaderBufferTimeouts = 0;
  int _opusToWavFallbacks = 0;
  final List<int> _latencyMeasurements = [];
  final List<int> _heapSizeMeasurements = [];
  int _maxHeapSize = 0;
  final Map<String, int> _errorCounts = {};
  final List<String> _recentErrors = [];
  DateTime? _lastStreamStart;
  DateTime? _lastSuccessfulStream;
  static const int _maxRecentErrors = 50;
  static const int _maxLatencyMeasurements = 100;
  static const int _maxHeapMeasurements = 100;
  void recordStreamingStart() {
    _totalStreamingAttempts++;
    _lastStreamStart = DateTime.now();
  }
  void recordStreamingSuccess({required int latencyMs}) {
    _successfulStreams++;
    _lastSuccessfulStream = DateTime.now();
    _latencyMeasurements.add(latencyMs);
    if (_latencyMeasurements.length > _maxLatencyMeasurements) {
      _latencyMeasurements.removeAt(0);
    }
  }
  void recordStreamingFailure(String error) {
    _failedStreams++;
    _errorCounts[error] = (_errorCounts[error] ?? 0) + 1;
    _recentErrors.add('${DateTime.now().toIso8601String()}: $error');
    if (_recentErrors.length > _maxRecentErrors) {
      _recentErrors.removeAt(0);
    }
  }
  void recordBufferUnderrun() {
    _bufferUnderruns++;
  }
  void recordFallbackToFullBuffer(String reason) {
    _fallbacksToFullBuffer++;
  }
  void recordHeapSize(int heapSizeBytes) {
    _heapSizeMeasurements.add(heapSizeBytes);
    if (_heapSizeMeasurements.length > _maxHeapMeasurements) {
      _heapSizeMeasurements.removeAt(0);
    }
    if (heapSizeBytes > _maxHeapSize) {
      _maxHeapSize = heapSizeBytes;
    }
    if (heapSizeBytes > 50 * 1024 * 1024) {
      _memoryWarnings++;
    }
  }
  // ====== OPUS-Specific Monitoring Methods ======
  void recordOpusStreamingStart() {
    _opusStreamingAttempts++;
    recordStreamingStart(); // Also record general streaming start
  }
  void recordOpusStreamingSuccess({required int latencyMs}) {
    _opusSuccessfulStreams++;
    recordStreamingSuccess(latencyMs: latencyMs); // Also record general success
  }
  void recordOpusStreamingFailure(String error) {
    _opusFailedStreams++;
    recordStreamingFailure('OPUS: $error'); // Also record general failure
  }
  void recordOpusEofBeforeOpusTags() {
    _opusEofBeforeOpusTags++;
  }
  void recordOpusHeaderTimeout() {
    _opusHeaderBufferTimeouts++;
  }
  void recordOpusToWavFallback(String reason) {
    _opusToWavFallbacks++;
  }
  double get successRate {
    if (_totalStreamingAttempts == 0) return 1.0;
    return _successfulStreams / _totalStreamingAttempts;
  }
  double get failureRate {
    if (_totalStreamingAttempts == 0) return 0.0;
    return _failedStreams / _totalStreamingAttempts;
  }
  double get bufferUnderrunRate {
    if (_totalStreamingAttempts == 0) return 0.0;
    return _bufferUnderruns / _totalStreamingAttempts;
  }
  double get averageLatencyMs {
    if (_latencyMeasurements.isEmpty) return 0.0;
    return _latencyMeasurements.reduce((a, b) => a + b) /
        _latencyMeasurements.length;
  }
  int get currentHeapSize {
    return _heapSizeMeasurements.isNotEmpty ? _heapSizeMeasurements.last : 0;
  }
  int get maxHeapSize => _maxHeapSize;
  // ====== OPUS-Specific Getters ======
  double get opusSuccessRate {
    if (_opusStreamingAttempts == 0) return 1.0;
    return _opusSuccessfulStreams / _opusStreamingAttempts;
  }
  double get opusFailureRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusFailedStreams / _opusStreamingAttempts;
  }
  double get opusEofBeforeOpusTagsRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusEofBeforeOpusTags / _opusStreamingAttempts;
  }
  double get opusHeaderTimeoutRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusHeaderBufferTimeouts / _opusStreamingAttempts;
  }
  double get opusToWavFallbackRate {
    if (_opusStreamingAttempts == 0) return 0.0;
    return _opusToWavFallbacks / _opusStreamingAttempts;
  }
  bool get isHealthy {
    final bool successRateOk = successRate >= 0.999; // >99.9%
    final bool underrunRateOk = bufferUnderrunRate <= 0.001; // <0.1%
    final bool memoryUsageOk = _memoryWarnings == 0 ||
        (_memoryWarnings / _totalStreamingAttempts) <= 0.01; // <1%
    return successRateOk && underrunRateOk && memoryUsageOk;
  }
  bool get needsRollback {
    final bool highFailureRate = failureRate > 0.01; // >1% failure rate
    final bool highUnderrunRate =
        bufferUnderrunRate > 0.05; // >5% underrun rate
    final bool recentErrors = _recentErrors.length > 10 &&
        _recentErrors.skip(_recentErrors.length - 10).any((error) =>
            DateTime.now()
                .difference(parseBackendDateTime(error.split(':')[0]))
                .inMinutes <
            5);
    return highFailureRate || highUnderrunRate || recentErrors;
  }
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
  void logStatus() {
  }
  void reset() {
    _totalStreamingAttempts = 0;
    _successfulStreams = 0;
    _failedStreams = 0;
    _bufferUnderruns = 0;
    _fallbacksToFullBuffer = 0;
    _memoryWarnings = 0;
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
  }
}
