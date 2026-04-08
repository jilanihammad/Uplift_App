// lib/di/interfaces/i_preferences_service.dart
import 'package:flutter/material.dart' show TimeOfDay;
import '../../models/user_preferences.dart';
import '../../models/therapist_style.dart';
abstract class IPreferencesService {
  UserPreferences? get preferences;
  Future<void> init();
  Future<void> updatePreferences(UserPreferences newPreferences);
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
  });
  List<TherapistStyle> getAvailableTherapistStyles();
  TherapistStyle getCurrentTherapistStyle();
  Future<void> setTherapistStyle(String styleId);
  Future<void> setUseVoiceByDefault(bool enabled);
  Future<void> setDailyCheckInTime(TimeOfDay? time);
  Future<void> setPreferredVoice(String voiceId);
}
