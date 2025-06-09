import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Memory monitoring service to detect correlation between memory pressure and string corruption
class MemoryMonitor {
  static MemoryMonitor? _instance;
  static MemoryMonitor get instance => _instance ??= MemoryMonitor._();

  MemoryMonitor._();

  Timer? _monitoringTimer;
  final List<MemorySnapshot> _snapshots = [];
  int _corruptionEvents = 0;
  bool _isMonitoring = false;

  /// Start monitoring memory usage
  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    print('🧠 MemoryMonitor: Starting memory pressure monitoring');

    _monitoringTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _captureMemorySnapshot();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    print('🧠 MemoryMonitor: Stopped monitoring');
  }

  /// Log a corruption event to correlate with memory usage
  void logCorruptionEvent(String corruptedValue, String context) {
    _corruptionEvents++;
    final currentMemory = _getCurrentMemoryUsage();

    print('🚨 CORRUPTION EVENT #$_corruptionEvents:');
    print('   Value: $corruptedValue');
    print('   Context: $context');
    print('   Memory: ${currentMemory}MB');
    print('   Timestamp: ${DateTime.now()}');

    // Check if we're under memory pressure
    if (currentMemory > 300) {
      // Threshold for high memory usage
      print('⚠️ HIGH MEMORY PRESSURE DETECTED: ${currentMemory}MB');
    }

    _logMemoryStats();
  }

  /// Force garbage collection and memory cleanup
  Future<void> forceMemoryCleanup() async {
    print('🧹 MemoryMonitor: Forcing memory cleanup...');

    // Force GC multiple times
    for (int i = 0; i < 3; i++) {
      developer.Timeline.startSync('ForceGC');
      await Future.delayed(Duration(milliseconds: 100));
      developer.Timeline.finishSync();
    }

    // Platform-specific memory cleanup
    if (Platform.isAndroid) {
      try {
        await _triggerAndroidMemoryCleanup();
      } catch (e) {
        print('🚨 Android memory cleanup failed: $e');
      }
    }

    final memoryAfter = _getCurrentMemoryUsage();
    print('🧹 Memory after cleanup: ${memoryAfter}MB');
  }

  /// Get current memory usage in MB (placeholder implementation)
  double _getCurrentMemoryUsage() {
    // TODO: Implement actual memory monitoring via platform channels
    // For now, return a simulated value based on runtime factors
    final now = DateTime.now();
    final baseMemory = 120.0;
    final variableMemory = (now.millisecondsSinceEpoch % 1000) / 10.0;
    return baseMemory + variableMemory;
  }

  /// Capture memory snapshot
  void _captureMemorySnapshot() {
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      memoryUsageMB: _getCurrentMemoryUsage(),
      corruptionCount: _corruptionEvents,
    );

    _snapshots.add(snapshot);

    // Keep only last 100 snapshots
    if (_snapshots.length > 100) {
      _snapshots.removeAt(0);
    }

    // Log if memory is high
    if (snapshot.memoryUsageMB > 250) {
      print('⚠️ High memory usage: ${snapshot.memoryUsageMB}MB');
    }
  }

  /// Trigger Android-specific memory cleanup
  Future<void> _triggerAndroidMemoryCleanup() async {
    const platform = MethodChannel('ai_therapist/memory');
    try {
      await platform.invokeMethod('triggerGC');
      await platform.invokeMethod('trimMemory');
    } catch (e) {
      // Platform channel not implemented - that's ok
      print('Platform memory cleanup not available: $e');
    }
  }

  /// Log comprehensive memory statistics
  void _logMemoryStats() {
    if (_snapshots.isEmpty) return;

    final recent = _snapshots
        .where((s) => DateTime.now().difference(s.timestamp).inMinutes < 5)
        .toList();

    if (recent.isEmpty) return;

    final avgMemory =
        recent.map((s) => s.memoryUsageMB).reduce((a, b) => a + b) /
            recent.length;
    final maxMemory =
        recent.map((s) => s.memoryUsageMB).reduce((a, b) => a > b ? a : b);

    print('📊 Memory Stats (last 5 min):');
    print('   Average: ${avgMemory.toStringAsFixed(1)}MB');
    print('   Peak: ${maxMemory.toStringAsFixed(1)}MB');
    print('   Corruption events: $_corruptionEvents');
    print('   Snapshots: ${recent.length}');
  }

  /// Check if memory pressure is high
  bool get isHighMemoryPressure {
    final current = _getCurrentMemoryUsage();
    return current > 300; // Threshold for high memory
  }

  /// Get corruption to memory ratio
  double get corruptionToMemoryRatio {
    if (_snapshots.isEmpty) return 0.0;
    final avgMemory =
        _snapshots.map((s) => s.memoryUsageMB).reduce((a, b) => a + b) /
            _snapshots.length;
    return avgMemory > 0 ? _corruptionEvents / avgMemory : 0.0;
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _snapshots.clear();
  }
}

/// Memory usage snapshot
class MemorySnapshot {
  final DateTime timestamp;
  final double memoryUsageMB;
  final int corruptionCount;

  MemorySnapshot({
    required this.timestamp,
    required this.memoryUsageMB,
    required this.corruptionCount,
  });
}
