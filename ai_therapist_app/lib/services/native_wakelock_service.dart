import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeWakelockService {
  static const MethodChannel _channel =
      MethodChannel('com.maya.uplift/wakelock');
  static bool _isEnabled = false;

  /// Enable wakelock using native method channel
  static Future<void> enable() async {
    try {
      final result = await _channel.invokeMethod('enable');
      _isEnabled = result == true;
      debugPrint('[NativeWakelockService] Wakelock enabled: $_isEnabled');
    } catch (e) {
      debugPrint('[NativeWakelockService] Failed to enable wakelock: $e');
    }
  }

  /// Disable wakelock using native method channel
  static Future<void> disable() async {
    try {
      final result = await _channel.invokeMethod('disable');
      _isEnabled = !(result == true);
      debugPrint('[NativeWakelockService] Wakelock disabled: ${!_isEnabled}');
    } catch (e) {
      debugPrint('[NativeWakelockService] Failed to disable wakelock: $e');
    }
  }

  /// Check if wakelock is enabled
  static Future<bool> get isEnabled async {
    try {
      final result = await _channel.invokeMethod('isEnabled');
      _isEnabled = result == true;
      return _isEnabled;
    } catch (e) {
      debugPrint('[NativeWakelockService] Failed to check wakelock status: $e');
      return _isEnabled; // Return cached value
    }
  }
}
