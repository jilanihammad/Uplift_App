import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class WakelockService {
  static bool _isEnabled = false;

  /// Enable wakelock to keep screen awake during therapy sessions
  static Future<void> enable() async {
    try {
      await WakelockPlus.enable();
      _isEnabled = true;
      debugPrint('[WakelockService] Wakelock enabled successfully');
    } catch (e) {
      debugPrint('[WakelockService] Failed to enable wakelock: $e');
      rethrow;
    }
  }

  /// Disable wakelock to allow screen to sleep
  static Future<void> disable() async {
    try {
      await WakelockPlus.disable();
      _isEnabled = false;
      debugPrint('[WakelockService] Wakelock disabled successfully');
    } catch (e) {
      debugPrint('[WakelockService] Failed to disable wakelock: $e');
      rethrow;
    }
  }

  /// Check if wakelock is currently enabled
  static Future<bool> get isEnabled async {
    try {
      return await WakelockPlus.enabled;
    } catch (e) {
      debugPrint('[WakelockService] Failed to check wakelock status: $e');
      return false;
    }
  }
}
