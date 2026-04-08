// lib/utils/feature_flags.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
class FeatureFlags {
  static const String useRefactoredVoicePipeline = 'useRefactoredVoicePipeline';
  static const String memoryPersistenceEnabled = 'memoryPersistenceEnabled';
  static const String moodPersistenceEnabled = 'moodPersistenceEnabled';
  static const String voiceFacadeEnabled = 'voiceFacadeEnabled';
  static const String coordinatorVoiceGuardEnabled =
      'coordinatorVoiceGuardEnabled';
  static const Map<String, bool> _defaults = {
    useRefactoredVoicePipeline:
        true, // Enable new pipeline to test Maya self-detection fix
    memoryPersistenceEnabled:
        true, // Always keep memory persistence enabled by default
    moodPersistenceEnabled: true, // Mood logging sync enabled across the board
    voiceFacadeEnabled: true,
    coordinatorVoiceGuardEnabled: true,
  };
  static SharedPreferences? _prefs;
  static bool _initialized = false;
  static Future<void>? _initFuture;
  static final Map<String, bool> _deferredWrites = {};
  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initFuture ??= _initializePrefs();
    await _initFuture;
  }
  static Future<void> _initializePrefs() async {
    _prefs = await SharedPreferences.getInstance();
    for (final entry in _defaults.entries) {
      _prefs!.setBool(entry.key, _prefs!.getBool(entry.key) ?? entry.value);
    }
    await _prefs!.setBool(moodPersistenceEnabled, true);
    if (_deferredWrites.isNotEmpty) {
      for (final entry in _deferredWrites.entries) {
        await _prefs!.setBool(entry.key, entry.value);
      }
      _deferredWrites.clear();
    }
    _initialized = true;
    _initFuture = null;
  }
  static bool isEnabled(String flagKey) {
    if (_prefs == null) {
      return _defaults[flagKey] ?? false;
    }
    final value = _prefs!.getBool(flagKey) ?? _defaults[flagKey] ?? false;
    return value;
  }
  static Future<void> setEnabled(String flagKey, bool value) async {
    if (_prefs == null) {
      _deferredWrites[flagKey] = value;
      return;
    }
    await _prefs!.setBool(flagKey, value);
  }
  static bool get isInitialized => _initialized;
  static bool get useNewVoicePipeline => isEnabled(useRefactoredVoicePipeline);
  static bool get isMemoryPersistenceEnabled =>
      isEnabled(memoryPersistenceEnabled);
  static bool get isMoodPersistenceEnabled => isEnabled(moodPersistenceEnabled);
  static bool get isVoiceFacadeEnabled => isEnabled(voiceFacadeEnabled);
  static bool get isCoordinatorVoiceGuardEnabled =>
      isEnabled(coordinatorVoiceGuardEnabled);
  static Future<void> toggleRefactoredVoicePipeline() async {
    final current = useNewVoicePipeline;
    await setEnabled(useRefactoredVoicePipeline, !current);
  }
  static Future<void> resetToDefaults() async {
    if (_prefs == null) {
      return;
    }
    for (final entry in _defaults.entries) {
      await _prefs!.setBool(entry.key, entry.value);
    }
  }
  static Map<String, bool> getAllFlags() {
    final flags = <String, bool>{};
    for (final key in _defaults.keys) {
      flags[key] = isEnabled(key);
    }
    return flags;
  }
  static void debugPrintFlags() {
    if (!kDebugMode) {
      return;
    }
    getAllFlags().forEach((key, value) {
    });
  }
}
