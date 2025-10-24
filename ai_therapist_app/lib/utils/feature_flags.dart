// lib/utils/feature_flags.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Feature flags management for controlled rollout of new features
class FeatureFlags {
  // Feature flag keys
  static const String useRefactoredVoicePipeline = 'useRefactoredVoicePipeline';
  static const String memoryPersistenceEnabled = 'memoryPersistenceEnabled';
  static const String moodPersistenceEnabled = 'moodPersistenceEnabled';

  // Default values
  static const Map<String, bool> _defaults = {
    useRefactoredVoicePipeline:
        true, // Enable new pipeline to test Maya self-detection fix
    memoryPersistenceEnabled:
        true, // Always keep memory persistence enabled by default
    moodPersistenceEnabled:
        false, // Mood logging sync rollout guarded by remote flag
  };

  static SharedPreferences? _prefs;

  /// Initialize feature flags with SharedPreferences
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('[FeatureFlags] Initialized with SharedPreferences');
  }

  /// Get the value of a feature flag
  static bool isEnabled(String flagKey) {
    if (_prefs == null) {
      debugPrint(
          '[FeatureFlags] WARNING: Not initialized, returning default for $flagKey');
      return _defaults[flagKey] ?? false;
    }

    final value = _prefs!.getBool(flagKey) ?? _defaults[flagKey] ?? false;
    debugPrint('[FeatureFlags] $flagKey = $value');
    return value;
  }

  /// Set the value of a feature flag
  static Future<void> setEnabled(String flagKey, bool value) async {
    if (_prefs == null) {
      debugPrint('[FeatureFlags] ERROR: Not initialized, cannot set $flagKey');
      return;
    }

    await _prefs!.setBool(flagKey, value);
    debugPrint('[FeatureFlags] Set $flagKey = $value');
  }

  /// Check if refactored voice pipeline should be used
  static bool get useNewVoicePipeline => isEnabled(useRefactoredVoicePipeline);

  /// Check if personalization persistence sync is enabled
  static bool get isMemoryPersistenceEnabled =>
      isEnabled(memoryPersistenceEnabled);

  /// Check if mood persistence sync is enabled
  static bool get isMoodPersistenceEnabled => isEnabled(moodPersistenceEnabled);

  /// Toggle the refactored voice pipeline flag
  static Future<void> toggleRefactoredVoicePipeline() async {
    final current = useNewVoicePipeline;
    await setEnabled(useRefactoredVoicePipeline, !current);
  }

  /// Reset all flags to defaults
  static Future<void> resetToDefaults() async {
    if (_prefs == null) {
      debugPrint('[FeatureFlags] ERROR: Not initialized');
      return;
    }

    for (final entry in _defaults.entries) {
      await _prefs!.setBool(entry.key, entry.value);
    }
    debugPrint('[FeatureFlags] Reset all flags to defaults');
  }

  /// Get all current flag values for debugging
  static Map<String, bool> getAllFlags() {
    final flags = <String, bool>{};
    for (final key in _defaults.keys) {
      flags[key] = isEnabled(key);
    }
    return flags;
  }

  /// Debug print all flags
  static void debugPrintFlags() {
    debugPrint('[FeatureFlags] Current flag values:');
    getAllFlags().forEach((key, value) {
      debugPrint('  $key: $value');
    });
  }
}
