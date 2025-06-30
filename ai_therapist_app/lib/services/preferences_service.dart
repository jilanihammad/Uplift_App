import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../models/user_preferences.dart';
import '../models/therapist_style.dart';
import '../di/interfaces/i_preferences_service.dart';
import '../data/datasources/local/prefs_manager.dart';

// Implementation of user preferences service with persistent storage
class PreferencesService implements IPreferencesService {
  static const String _preferencesKey = 'user_preferences';
  
  final PrefsManager _prefsManager;
  UserPreferences? _preferences;

  // Constructor with dependency injection
  PreferencesService({PrefsManager? prefsManager}) 
      : _prefsManager = prefsManager ?? PrefsManager();

  // Get current preferences
  @override
  UserPreferences? get preferences => _preferences;

  // Method to initialize the preferences service
  @override
  Future<void> init() async {
    // Skip if already initialized
    if (_preferences != null) {
      return;
    }
    
    try {
      // Initialize the preferences manager
      await _prefsManager.init();

      // Try to load existing preferences from persistent storage
      final Map<String, dynamic>? savedPrefs = _prefsManager.getJson(_preferencesKey);
      
      if (savedPrefs != null) {
        // Load existing preferences
        _preferences = UserPreferences.fromJson(savedPrefs);
        if (kDebugMode) {
          print('Preferences loaded from storage');
        }
      } else {
        // Create default preferences if none exist
        _preferences = const UserPreferences(
          userId: 'default-user',
          therapistStyleId: 'cbt', // Default to CBT style
          reminderEnabled: true,
          reminderTime: TimeOfDay(hour: 18, minute: 0),
          darkModeEnabled: true, // Default to dark mode
          notificationsEnabled: true,
          audioEnabled: true,
          fontSizeLevel: 2, // Medium font size (1=small, 2=medium, 3=large)
          aiVoiceId: 'female-1',
          useVoiceByDefault: false,
        );

        // Save default preferences to storage
        await _savePreferences();
        
        if (kDebugMode) {
          print('Default preferences created and saved');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing preferences: $e');
      }
      // Fallback to default preferences
      _preferences = const UserPreferences();
    }
  }

  // Helper method to save preferences to storage
  Future<void> _savePreferences() async {
    if (_preferences != null) {
      try {
        await _prefsManager.setJson(_preferencesKey, _preferences!.toJson());
        if (kDebugMode) {
          print('Preferences saved to storage');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error saving preferences: $e');
        }
      }
    }
  }

  // Update preferences
  @override
  Future<void> updatePreferences(UserPreferences newPreferences) async {
    _preferences = newPreferences.copyWith(
      lastUpdated: DateTime.now(),
    );

    // Save to persistent storage
    await _savePreferences();

    if (kDebugMode) {
      print('Preferences updated: ${newPreferences.therapistStyleId}');
    }
  }

  // Update a single preference
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

    // Save to persistent storage
    await _savePreferences();

    if (kDebugMode) {
      print('Single preference updated and saved');
    }
  }

  // Get available therapist styles
  @override
  List<TherapistStyle> getAvailableTherapistStyles() {
    return TherapistStyle.availableStyles;
  }

  // Get current therapist style
  @override
  TherapistStyle getCurrentTherapistStyle() {
    final styleId = _preferences?.therapistStyleId ?? 'cbt';
    return TherapistStyle.getById(styleId);
  }

  // Set the therapist style
  @override
  Future<void> setTherapistStyle(String styleId) async {
    await updateSinglePreference(therapistStyleId: styleId);

    if (kDebugMode) {
      print('Therapist style updated to: $styleId');
    }
  }

  // Set voice by default option
  @override
  Future<void> setUseVoiceByDefault(bool enabled) async {
    await updateSinglePreference(useVoiceByDefault: enabled);

    if (kDebugMode) {
      print('Use voice by default set to: $enabled');
    }
  }

  // Set daily check-in time
  @override
  Future<void> setDailyCheckInTime(TimeOfDay? time) async {
    await updateSinglePreference(dailyCheckInTime: time);

    if (kDebugMode) {
      print(
          'Daily check-in time set to: ${time != null ? '${time.hour}:${time.minute}' : 'null'}');
    }
  }
}
