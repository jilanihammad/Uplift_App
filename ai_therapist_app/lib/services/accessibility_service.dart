/// Accessibility service for managing motion sensitivity and other accessibility features
///
/// Provides configuration for users who are sensitive to motion and animations

import 'package:shared_preferences/shared_preferences.dart';

class AccessibilityService {
  static const String _motionSensitiveKey = 'motion_sensitive_mode';
  static const String _reducedAnimationsKey = 'reduced_animations';
  static const String _highContrastKey = 'high_contrast_mode';

  /// Get motion sensitivity setting
  /// Returns true if user has requested reduced motion
  static Future<bool> getMotionSensitive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_motionSensitiveKey) ?? false;
  }

  /// Set motion sensitivity setting
  static Future<void> setMotionSensitive(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_motionSensitiveKey, enabled);
  }

  /// Get reduced animations setting
  static Future<bool> getReducedAnimations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reducedAnimationsKey) ?? false;
  }

  /// Set reduced animations setting
  static Future<void> setReducedAnimations(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedAnimationsKey, enabled);
  }

  /// Get high contrast mode setting
  static Future<bool> getHighContrast() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_highContrastKey) ?? false;
  }

  /// Set high contrast mode setting
  static Future<void> setHighContrast(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highContrastKey, enabled);
  }

  /// Get all accessibility settings at once
  static Future<AccessibilitySettings> getSettings() async {
    final motionSensitive = await getMotionSensitive();
    final reducedAnimations = await getReducedAnimations();
    final highContrast = await getHighContrast();

    return AccessibilitySettings(
      motionSensitive: motionSensitive,
      reducedAnimations: reducedAnimations,
      highContrast: highContrast,
    );
  }
}

/// Data class for accessibility settings
class AccessibilitySettings {
  final bool motionSensitive;
  final bool reducedAnimations;
  final bool highContrast;

  const AccessibilitySettings({
    required this.motionSensitive,
    required this.reducedAnimations,
    required this.highContrast,
  });

  AccessibilitySettings copyWith({
    bool? motionSensitive,
    bool? reducedAnimations,
    bool? highContrast,
  }) {
    return AccessibilitySettings(
      motionSensitive: motionSensitive ?? this.motionSensitive,
      reducedAnimations: reducedAnimations ?? this.reducedAnimations,
      highContrast: highContrast ?? this.highContrast,
    );
  }
}
