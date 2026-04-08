import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../models/user_preferences.dart';
import '../models/therapist_style.dart';
import '../di/interfaces/i_preferences_service.dart';
import '../data/datasources/local/prefs_manager.dart';
import '../config/llm_config.dart';
class PreferencesService implements IPreferencesService {
  static const String _preferencesKey = 'user_preferences';
  final PrefsManager _prefsManager;
  UserPreferences? _preferences;
  PreferencesService({PrefsManager? prefsManager})
      : _prefsManager = prefsManager ?? PrefsManager();
  @override
  UserPreferences? get preferences => _preferences;
  @override
  Future<void> init() async {
    if (_preferences != null) {
      return;
    }
    try {
      await _prefsManager.init();
      final Map<String, dynamic>? savedPrefs =
          _prefsManager.getJson(_preferencesKey);
      if (savedPrefs != null) {
        _preferences = UserPreferences.fromJson(savedPrefs);
        if (_preferences?.therapistStyleId != 'cbt') {
          _preferences = _preferences!.copyWith(therapistStyleId: 'cbt');
          await _savePreferences();
        }
        if (_preferences?.aiVoiceId != null &&
            _preferences!.aiVoiceId!.isNotEmpty) {
          LLMConfig.setPreferredTtsVoice(_preferences!.aiVoiceId!);
        }
      } else {
        _preferences = const UserPreferences(
          userId: 'default-user',
          therapistStyleId: 'cbt', // Default to CBT style
          reminderEnabled: true,
          reminderTime: TimeOfDay(hour: 18, minute: 0),
          darkModeEnabled: true, // Default to dark mode
          notificationsEnabled: true,
          audioEnabled: true,
          fontSizeLevel: 2, // Medium font size (1=small, 2=medium, 3=large)
          aiVoiceId: 'sage',
          useVoiceByDefault: false,
        );
        await _savePreferences();
        LLMConfig.setPreferredTtsVoice('sage');
      }
    } catch (e) {
      _preferences = const UserPreferences();
      if (_preferences?.aiVoiceId != null) {
        LLMConfig.setPreferredTtsVoice(_preferences!.aiVoiceId!);
      }
    }
  }
  Future<void> _savePreferences() async {
    if (_preferences != null) {
      try {
        await _prefsManager.setJson(_preferencesKey, _preferences!.toJson());
      } catch (e) {}
    }
  }
  @override
  Future<void> updatePreferences(UserPreferences newPreferences) async {
    _preferences = newPreferences.copyWith(
      therapistStyleId: 'cbt',
      lastUpdated: DateTime.now(),
    );
    await _savePreferences();
  }
  @override
  Future<void> updateSinglePreference({
    String? therapistStyleId,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? darkModeEnabled,
    bool? notificationsEnabled,
    bool? audioEnabled,
    int? fontSizeLevel,
    String? aiVoiceId,
    bool? useVoiceByDefault,
    TimeOfDay? dailyCheckInTime,
  }) async {
    if (_preferences == null) {
      await init();
    }
    const enforcedStyleId = 'cbt';
    _preferences = _preferences!.copyWith(
      therapistStyleId: enforcedStyleId,
      reminderEnabled: reminderEnabled,
      reminderTime: reminderTime,
      darkModeEnabled: darkModeEnabled,
      notificationsEnabled: notificationsEnabled,
      audioEnabled: audioEnabled,
      fontSizeLevel: fontSizeLevel,
      aiVoiceId: aiVoiceId,
      useVoiceByDefault: useVoiceByDefault,
      dailyCheckInTime: dailyCheckInTime,
      lastUpdated: DateTime.now(),
    );
    if (aiVoiceId != null && aiVoiceId.isNotEmpty) {
      LLMConfig.setPreferredTtsVoice(aiVoiceId);
    }
    await _savePreferences();
  }
  @override
  List<TherapistStyle> getAvailableTherapistStyles() {
    return TherapistStyle.availableStyles;
  }
  @override
  TherapistStyle getCurrentTherapistStyle() {
    final styleId = _preferences?.therapistStyleId ?? 'cbt';
    return TherapistStyle.getById(styleId);
  }
  @override
  Future<void> setTherapistStyle(String styleId) async {
    await updateSinglePreference(therapistStyleId: 'cbt');
  }
  @override
  Future<void> setUseVoiceByDefault(bool enabled) async {
    await updateSinglePreference(useVoiceByDefault: enabled);
  }
  @override
  Future<void> setPreferredVoice(String voiceId) async {
    await updateSinglePreference(aiVoiceId: voiceId);
  }
  @override
  Future<void> setDailyCheckInTime(TimeOfDay? time) async {
    await updateSinglePreference(dailyCheckInTime: time);
  }
}
