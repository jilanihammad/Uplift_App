// lib/utils/disposal_monitor.dart

import 'package:flutter/foundation.dart';

/// Monitors disposal performance and MediaCodec-related issues
class DisposalMonitor {
  static final DisposalMonitor _instance = DisposalMonitor._internal();
  factory DisposalMonitor() => _instance;
  DisposalMonitor._internal();

  final Map<String, List<DisposalMetric>> _metrics = {};

  /// Record a disposal operation
  void recordDisposal({
    required String serviceName,
    required int durationMs,
    bool isAsync = false,
    String? error,
  }) {
    final metric = DisposalMetric(
      serviceName: serviceName,
      durationMs: durationMs,
      isAsync: isAsync,
      error: error,
      timestamp: DateTime.now(),
    );

    _metrics.putIfAbsent(serviceName, () => []).add(metric);

    // Keep only last 10 metrics per service
    if (_metrics[serviceName]!.length > 10) {
      _metrics[serviceName]!.removeAt(0);
    }

    if (kDebugMode) {
      final status = error != null ? 'FAILED' : 'SUCCESS';
      final asyncLabel = isAsync ? 'ASYNC' : 'SYNC';
      debugPrint('📊 DisposalMonitor: $serviceName $asyncLabel disposal $status in ${durationMs}ms');
      
      if (error != null) {
        debugPrint('📊 DisposalMonitor: Error details: $error');
      }
    }
  }

  /// Get disposal statistics for a service
  DisposalStats? getStats(String serviceName) {
    final metrics = _metrics[serviceName];
    if (metrics == null || metrics.isEmpty) return null;

    return DisposalStats.fromMetrics(serviceName, metrics);
  }

  /// Get all disposal statistics
  Map<String, DisposalStats> getAllStats() {
    final result = <String, DisposalStats>{};
    
    for (final entry in _metrics.entries) {
      if (entry.value.isNotEmpty) {
        result[entry.key] = DisposalStats.fromMetrics(entry.key, entry.value);
      }
    }
    
    return result;
  }

  /// Check for potential MediaCodec issues (long disposal times)
  List<String> getMediaCodecWarnings() {
    final warnings = <String>[];
    
    for (final entry in _metrics.entries) {
      final metrics = entry.value;
      if (metrics.isEmpty) continue;
      
      // Check for consistently slow disposals (>2 seconds)
      final recentMetrics = metrics.length > 3 
          ? metrics.sublist(metrics.length - 3)
          : metrics;
      
      final slowDisposals = recentMetrics
          .where((m) => m.durationMs > 2000)
          .length;
      
      if (slowDisposals >= 2) {
        warnings.add('${entry.key}: Consistently slow disposal ($slowDisposals/3 recent disposals >2s)');
      }
      
      // Check for disposal errors
      final recentErrors = recentMetrics
          .where((m) => m.error != null)
          .length;
      
      if (recentErrors > 0) {
        warnings.add('${entry.key}: $recentErrors disposal errors in recent attempts');
      }
    }
    
    return warnings;
  }

  /// Clear all metrics
  void clear() {
    _metrics.clear();
    if (kDebugMode) {
      debugPrint('📊 DisposalMonitor: Metrics cleared');
    }
  }
}

/// Individual disposal metric
class DisposalMetric {
  final String serviceName;
  final int durationMs;
  final bool isAsync;
  final String? error;
  final DateTime timestamp;

  DisposalMetric({
    required this.serviceName,
    required this.durationMs,
    required this.isAsync,
    this.error,
    required this.timestamp,
  });
}

/// Disposal statistics for a service
class DisposalStats {
  final String serviceName;
  final int totalDisposals;
  final int asyncDisposals;
  final int syncDisposals;
  final int errors;
  final int averageDurationMs;
  final int maxDurationMs;
  final int minDurationMs;
  final DateTime lastDisposal;

  DisposalStats({
    required this.serviceName,
    required this.totalDisposals,
    required this.asyncDisposals,
    required this.syncDisposals,
    required this.errors,
    required this.averageDurationMs,
    required this.maxDurationMs,
    required this.minDurationMs,
    required this.lastDisposal,
  });

  factory DisposalStats.fromMetrics(String serviceName, List<DisposalMetric> metrics) {
    final asyncCount = metrics.where((m) => m.isAsync).length;
    final errorCount = metrics.where((m) => m.error != null).length;
    final durations = metrics.map((m) => m.durationMs).toList();
    
    return DisposalStats(
      serviceName: serviceName,
      totalDisposals: metrics.length,
      asyncDisposals: asyncCount,
      syncDisposals: metrics.length - asyncCount,
      errors: errorCount,
      averageDurationMs: durations.isEmpty ? 0 : durations.reduce((a, b) => a + b) ~/ durations.length,
      maxDurationMs: durations.isEmpty ? 0 : durations.reduce((a, b) => a > b ? a : b),
      minDurationMs: durations.isEmpty ? 0 : durations.reduce((a, b) => a < b ? a : b),
      lastDisposal: metrics.isEmpty ? DateTime.now() : metrics.last.timestamp,
    );
  }

  @override
  String toString() {
    return 'DisposalStats($serviceName: $totalDisposals total, '
           '${asyncDisposals}A/${syncDisposals}S, '
           '$errors errors, avg ${averageDurationMs}ms, '
           'range $minDurationMs-${maxDurationMs}ms)';
  }
}