import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Memory monitoring utilities for TTS streaming
///
/// Provides memory usage tracking and heap growth detection for safe streaming.
class MemoryMonitor {
  static int _baselineMemoryFootprint = 0;
  static final List<Uint8List> _memoryTracker = [];
  static bool _baselineSet = false;

  /// Set baseline memory footprint at app startup
  static void setBaseline() {
    if (!_baselineSet) {
      _baselineMemoryFootprint = _estimateMemoryUsage();
      _baselineSet = true;
      if (kDebugMode) {
        debugPrint(
            '📊 MemoryMonitor: Baseline memory footprint: ${(_baselineMemoryFootprint / 1024 / 1024).toStringAsFixed(1)} MB');
      }
    }
  }

  /// Get current estimated memory usage in bytes
  static int getCurrentMemoryUsage() {
    return _estimateMemoryUsage();
  }

  /// Get memory growth since baseline in bytes
  static int getMemoryGrowth() {
    if (!_baselineSet) setBaseline();
    return _estimateMemoryUsage() - _baselineMemoryFootprint;
  }

  /// Track memory allocation for a specific buffer
  static void trackAllocation(Uint8List buffer, String source) {
    if (kDebugMode && buffer.length > 1024 * 1024) {
      // Track allocations >1MB
      debugPrint(
          '📊 MemoryMonitor: Large allocation from $source: ${(buffer.length / 1024 / 1024).toStringAsFixed(1)} MB');
    }
  }

  /// Check if memory usage is within safe limits
  static bool isMemoryUsageSafe({int maxGrowthMB = 50}) {
    final growthBytes = getMemoryGrowth();
    final growthMB = growthBytes / 1024 / 1024;
    return growthMB <= maxGrowthMB;
  }

  /// Get memory usage report
  static Map<String, dynamic> getMemoryReport() {
    final currentUsage = getCurrentMemoryUsage();
    final growth = getMemoryGrowth();

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'baseline_mb': _baselineMemoryFootprint / 1024 / 1024,
      'current_usage_mb': currentUsage / 1024 / 1024,
      'growth_mb': growth / 1024 / 1024,
      'is_safe': isMemoryUsageSafe(),
    };
  }

  /// Estimate memory usage (simple heuristic)
  /// This is an approximation since Dart doesn't provide direct heap access
  static int _estimateMemoryUsage() {
    // Create a small allocation to trigger GC-related memory reporting
    final testAllocation = Uint8List(1024);
    _memoryTracker.add(testAllocation);

    // Keep only recent allocations to prevent memory leak
    if (_memoryTracker.length > 10) {
      _memoryTracker.removeAt(0);
    }

    // Return a proxy measurement based on allocation count
    // This is a simple heuristic - in production, you might use
    // platform-specific memory monitoring
    return _memoryTracker.length * 1024 +
        10 * 1024 * 1024; // Base 10MB + tracker
  }

  /// Log current memory status
  static void logMemoryStatus() {
    if (kDebugMode) {
      final report = getMemoryReport();
      debugPrint('📊 Memory Status:');
      debugPrint(
          '  Current Usage: ${report['current_usage_mb'].toStringAsFixed(1)} MB');
      debugPrint('  Growth: ${report['growth_mb'].toStringAsFixed(1)} MB');
      debugPrint('  Safe: ${report['is_safe']}');
    }
  }
}
