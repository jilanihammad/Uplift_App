import 'package:flutter/material.dart';
import 'package:ai_therapist_app/utils/date_time_utils.dart';

// User preferences model for storing app settings
class UserPreferences {
  final String? userId;
  final String? therapistStyleId; // ID of selected therapist style
  final bool reminderEnabled;
  final TimeOfDay? reminderTime;
  final bool darkModeEnabled;
  final bool notificationsEnabled;
  final bool audioEnabled;
  final int fontSizeLevel; // 1=small, 2=medium, 3=large
  final String? aiVoiceId;
  final DateTime? lastUpdated;
  final List<String> goals;
  final String? focusArea;
  final bool useVoiceByDefault;
  final TimeOfDay? dailyCheckInTime;

  // Constructor with default values
  const UserPreferences({
    this.userId,
    this.therapistStyleId = 'cbt',
    this.reminderEnabled = true,
    this.reminderTime,
    this.darkModeEnabled = false,
    this.notificationsEnabled = true,
    this.audioEnabled = true,
    this.fontSizeLevel = 2,
    this.aiVoiceId,
    this.lastUpdated,
    this.goals = const [],
    this.focusArea,
    this.useVoiceByDefault = false,
    this.dailyCheckInTime,
  });

  // Create a copy with modified fields
  UserPreferences copyWith({
    String? userId,
    String? therapistStyleId,
    bool? reminderEnabled,
    TimeOfDay? reminderTime,
    bool? darkModeEnabled,
    bool? notificationsEnabled,
    bool? audioEnabled,
    int? fontSizeLevel,
    String? aiVoiceId,
    DateTime? lastUpdated,
    List<String>? goals,
    String? focusArea,
    bool? useVoiceByDefault,
    TimeOfDay? dailyCheckInTime,
  }) {
    return UserPreferences(
      userId: userId ?? this.userId,
      therapistStyleId: therapistStyleId ?? this.therapistStyleId,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      darkModeEnabled: darkModeEnabled ?? this.darkModeEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
      aiVoiceId: aiVoiceId ?? this.aiVoiceId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      goals: goals ?? this.goals,
      focusArea: focusArea ?? this.focusArea,
      useVoiceByDefault: useVoiceByDefault ?? this.useVoiceByDefault,
      dailyCheckInTime: dailyCheckInTime ?? this.dailyCheckInTime,
    );
  }

  // Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'therapistStyleId': therapistStyleId,
      'reminderEnabled': reminderEnabled,
      'reminderTimeHour': reminderTime?.hour,
      'reminderTimeMinute': reminderTime?.minute,
      'darkModeEnabled': darkModeEnabled,
      'notificationsEnabled': notificationsEnabled,
      'audioEnabled': audioEnabled,
      'fontSizeLevel': fontSizeLevel,
      'aiVoiceId': aiVoiceId,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'goals': goals,
      'focusArea': focusArea,
      'useVoiceByDefault': useVoiceByDefault,
      'dailyCheckInTimeHour': dailyCheckInTime?.hour,
      'dailyCheckInTimeMinute': dailyCheckInTime?.minute,
    };
  }

  // Deserialize from JSON
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      userId: json['userId'],
      therapistStyleId: json['therapistStyleId'],
      reminderEnabled: json['reminderEnabled'] ?? true,
      reminderTime:
          json['reminderTimeHour'] != null && json['reminderTimeMinute'] != null
              ? TimeOfDay(
                  hour: json['reminderTimeHour'],
                  minute: json['reminderTimeMinute'],
                )
              : null,
      darkModeEnabled: json['darkModeEnabled'] ?? false,
      notificationsEnabled: json['notificationsEnabled'] ?? true,
      audioEnabled: json['audioEnabled'] ?? true,
      fontSizeLevel: json['fontSizeLevel'] ?? 2,
      aiVoiceId: json['aiVoiceId'],
      lastUpdated: json['lastUpdated'] != null
          ? parseBackendDateTime(json['lastUpdated'] as String)
          : null,
      goals:
          json['goals'] != null ? List<String>.from(json['goals']) : const [],
      focusArea: json['focusArea'],
      useVoiceByDefault: json['useVoiceByDefault'] ?? false,
      dailyCheckInTime: json['dailyCheckInTimeHour'] != null &&
              json['dailyCheckInTimeMinute'] != null
          ? TimeOfDay(
              hour: json['dailyCheckInTimeHour'],
              minute: json['dailyCheckInTimeMinute'],
            )
          : null,
    );
  }
}
