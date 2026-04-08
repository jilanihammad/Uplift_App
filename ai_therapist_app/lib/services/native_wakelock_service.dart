import 'package:flutter/services.dart';
class NativeWakelockService {
  static const MethodChannel _channel =
      MethodChannel('com.maya.uplift/wakelock');
  static bool _isEnabled = false;
  static Future<void> enable() async {
    try {
      final result = await _channel.invokeMethod('enable');
      _isEnabled = result == true;
    } catch (e) {}
  }
  static Future<void> disable() async {
    try {
      final result = await _channel.invokeMethod('disable');
      _isEnabled = !(result == true);
    } catch (e) {}
  }
  static Future<bool> get isEnabled async {
    try {
      final result = await _channel.invokeMethod('isEnabled');
      _isEnabled = result == true;
      return _isEnabled;
    } catch (e) {
      return _isEnabled; // Return cached value
    }
  }
}
