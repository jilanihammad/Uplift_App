// lib/di/interfaces/i_preferences_service.dart

import 'package:flutter/material.dart' show TimeOfDay;
import '../../models/user_preferences.dart';
import '../../models/therapist_style.dart';

/// Interface for preferences service operations
/// Provides contract for user preferences management
abstract class IPreferencesService {
  // Current preferences
  UserPreferences? get preferences;

  // Initialization
  Future<void> init();

  // Preferences management
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

  // Therapist style management
  List<TherapistStyle> getAvailableTherapistStyles();
  TherapistStyle getCurrentTherapistStyle();
  Future<void> setTherapistStyle(String styleId);

  // Specific preference setters
  Future<void> setUseVoiceByDefault(bool enabled);
  Future<void> setDailyCheckInTime(TimeOfDay? time);
  Future<void> setPreferredVoice(String voiceId);
}
