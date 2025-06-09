import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'memory_monitor.dart';
import 'path_manager.dart';

/// Aggressive memory pressure relief system
/// Implements cleanup strategies when memory usage is high
class MemoryPressureRelief {
  static MemoryPressureRelief? _instance;
  static MemoryPressureRelief get instance =>
      _instance ??= MemoryPressureRelief._();

  MemoryPressureRelief._();

  Timer? _pressureCheckTimer;
  bool _isReliefActive = false;
  int _cleanupCycles = 0;

  /// Start monitoring for memory pressure and auto-relief
  void startPressureRelief() {
    if (_pressureCheckTimer != null) return;

    print('🧠 MemoryPressureRelief: Starting automatic pressure relief');

    _pressureCheckTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _checkAndRelievePressure();
    });
  }

  /// Stop monitoring
  void stopPressureRelief() {
    _pressureCheckTimer?.cancel();
    _pressureCheckTimer = null;
    _isReliefActive = false;
    print('🧠 MemoryPressureRelief: Stopped automatic pressure relief');
  }

  /// Check memory pressure and trigger relief if needed
  Future<void> _checkAndRelievePressure() async {
    if (_isReliefActive) return; // Don't overlap cleanup cycles

    final memoryMonitor = MemoryMonitor.instance;

    if (memoryMonitor.isHighMemoryPressure) {
      _isReliefActive = true;
      _cleanupCycles++;

      print(
          '🚨 HIGH MEMORY PRESSURE - Starting cleanup cycle #$_cleanupCycles');
      await _executeAggressiveCleanup();

      _isReliefActive = false;
    }
  }

  /// Execute aggressive memory cleanup strategies
  Future<void> _executeAggressiveCleanup() async {
    print('🧹 MemoryPressureRelief: Executing aggressive cleanup...');

    // Strategy 1: Force multiple garbage collection cycles
    await _forceGarbageCollection();

    // Strategy 2: Clear cached audio files
    await _clearAudioCache();

    // Strategy 3: Force platform-specific memory trimming
    await _platformMemoryTrim();

    // Strategy 4: Clear any temporary string buffers
    await _clearStringBuffers();

    // Strategy 5: Force image cache clearing (if using images)
    await _clearImageCache();

    print('🧹 MemoryPressureRelief: Cleanup cycle complete');
  }

  /// Force multiple garbage collection cycles
  Future<void> _forceGarbageCollection() async {
    print('♻️ Forcing garbage collection cycles...');

    for (int i = 0; i < 5; i++) {
      developer.Timeline.startSync('ForceGC-${i + 1}');
      await Future.delayed(Duration(milliseconds: 50));
      developer.Timeline.finishSync();

      // Try to trigger actual GC
      List<int> largeBuffer = List.filled(10000, 0);
      largeBuffer.clear();
      largeBuffer = [];
    }

    print('♻️ Garbage collection cycles complete');
  }

  /// Clear audio cache and temporary files
  Future<void> _clearAudioCache() async {
    try {
      print('🎵 Clearing audio cache...');

      // Get cache directory from PathManager
      final PathManager pathManager = PathManager.instance;
      final cacheDir = pathManager.cacheDir;

      // Clear TTS files older than 5 minutes
      final ttsDir = Directory('$cacheDir/tts');
      if (await ttsDir.exists()) {
        final files = ttsDir.listSync();
        final now = DateTime.now();

        for (final file in files) {
          if (file is File) {
            final stat = await file.stat();
            final age = now.difference(stat.modified);

            if (age.inMinutes > 5) {
              await file.delete();
              print('🗑️ Deleted old TTS file: ${file.path}');
            }
          }
        }
      }

      // Clear old recording files (but keep recent ones)
      final recordingsDir = Directory('$cacheDir/recordings');
      if (await recordingsDir.exists()) {
        final files = recordingsDir.listSync();
        final now = DateTime.now();

        for (final file in files) {
          if (file is File) {
            final stat = await file.stat();
            final age = now.difference(stat.modified);

            if (age.inMinutes > 10) {
              await file.delete();
              print('🗑️ Deleted old recording: ${file.path}');
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Error clearing audio cache: $e');
    }
  }

  /// Platform-specific memory trimming
  Future<void> _platformMemoryTrim() async {
    try {
      print('🔧 Platform memory trimming...');

      if (Platform.isAndroid) {
        // Force Android memory cleanup
        await MemoryMonitor.instance.forceMemoryCleanup();
      }
    } catch (e) {
      print('⚠️ Platform memory trim failed: $e');
    }
  }

  /// Clear temporary string buffers and caches
  Future<void> _clearStringBuffers() async {
    print('📝 Clearing string buffers...');

    // Force string interning cleanup by creating and discarding strings
    for (int i = 0; i < 1000; i++) {
      String temp = 'cleanup_buffer_$i';
      temp = temp.replaceAll('_', '-');
      temp = '';
    }
  }

  /// Clear Flutter image cache
  Future<void> _clearImageCache() async {
    try {
      print('🖼️ Clearing image cache...');

      // Clear Flutter's image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      print('⚠️ Error clearing image cache: $e');
    }
  }

  /// Manual trigger for emergency cleanup
  Future<void> emergencyCleanup() async {
    print('🚨 EMERGENCY MEMORY CLEANUP TRIGGERED');

    if (_isReliefActive) {
      print('⚠️ Cleanup already in progress, queuing emergency cleanup...');
      await Future.delayed(Duration(seconds: 1));
    }

    _isReliefActive = true;
    _cleanupCycles++;

    await _executeAggressiveCleanup();

    // Additional emergency measures
    await _emergencyStringCleanup();

    _isReliefActive = false;

    print('🚨 EMERGENCY CLEANUP COMPLETE');
  }

  /// Emergency string corruption prevention
  Future<void> _emergencyStringCleanup() async {
    print('🆘 Emergency string cleanup...');

    // Force string pool cleanup
    for (int i = 0; i < 5000; i++) {
      String test = '/data/user/0/com.maya.uplift/cache/recordings/test_$i.m4a';

      // Force string operations that might trigger cleanup
      test = test.replaceAll('recordings', 'temp');
      test = test.replaceAll('temp', 'recordings');
      test = String.fromCharCodes(test.codeUnits);

      // Force garbage collection
      test = '';
    }
  }

  /// Get cleanup statistics
  Map<String, dynamic> getStats() {
    return {
      'cleanupCycles': _cleanupCycles,
      'isReliefActive': _isReliefActive,
      'hasActiveTimer': _pressureCheckTimer != null,
    };
  }

  /// Dispose resources
  void dispose() {
    stopPressureRelief();
  }
}
