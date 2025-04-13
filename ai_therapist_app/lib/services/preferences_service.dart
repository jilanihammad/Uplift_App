import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../models/user_preferences.dart';
import '../models/therapist_style.dart';

// Mock implementation of user preferences service
class PreferencesService {
  // Mock user preferences
  UserPreferences? _preferences;
  
  // Get current preferences
  UserPreferences? get preferences => _preferences;
  
  // Method to initialize the preferences service
  Future<void> init() async {
    // In a real app, this would load preferences from persistent storage
    // For now, we'll just use default values
    _preferences = UserPreferences(
      userId: 'mock-user-1',
      therapistStyleId: 'cbt', // Default to CBT style
      reminderEnabled: true,
      reminderTime: const TimeOfDay(hour: 18, minute: 0),
      darkModeEnabled: false,
      notificationsEnabled: true,
      audioEnabled: true,
      fontSizeLevel: 2, // Medium font size (1=small, 2=medium, 3=large)
      aiVoiceId: 'female-1',
      lastUpdated: DateTime.now(),
    );
    
    if (kDebugMode) {
      print('Preferences service initialized');
    }
  }
  
  // Update preferences
  Future<void> updatePreferences(UserPreferences newPreferences) async {
    _preferences = newPreferences.copyWith(
      lastUpdated: DateTime.now(),
    );
    
    // In a real app, we would save to persistent storage here
    if (kDebugMode) {
      print('Preferences updated: ${newPreferences.therapistStyleId}');
    }
  }
  
  // Update a single preference
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
    
    _preferences = _preferences!.copyWith(
      therapistStyleId: therapistStyleId,
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
    
    // In a real app, we would save to persistent storage here
    if (kDebugMode) {
      print('Single preference updated');
    }
  }
  
  // Get available therapist styles
  List<TherapistStyle> getAvailableTherapistStyles() {
    return TherapistStyle.availableStyles;
  }
  
  // Get current therapist style
  TherapistStyle getCurrentTherapistStyle() {
    final styleId = _preferences?.therapistStyleId ?? 'cbt';
    return TherapistStyle.getById(styleId);
  }
  
  // Set the therapist style
  Future<void> setTherapistStyle(String styleId) async {
    await updateSinglePreference(therapistStyleId: styleId);
    
    if (kDebugMode) {
      print('Therapist style updated to: $styleId');
    }
  }
  
  // Set voice by default option
  Future<void> setUseVoiceByDefault(bool enabled) async {
    await updateSinglePreference(useVoiceByDefault: enabled);
    
    if (kDebugMode) {
      print('Use voice by default set to: $enabled');
    }
  }
  
  // Set daily check-in time
  Future<void> setDailyCheckInTime(TimeOfDay? time) async {
    await updateSinglePreference(dailyCheckInTime: time);
    
    if (kDebugMode) {
      print('Daily check-in time set to: ${time != null ? '${time.hour}:${time.minute}' : 'null'}');
    }
  }
} 