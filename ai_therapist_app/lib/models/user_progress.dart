import 'package:flutter/material.dart';

class UserProgress {
  final int currentStreak;
  final int longestStreak;
  final int totalPoints;
  final int currentLevel;
  final List<Achievement> achievements;
  final Map<DateTime, int> moodHistory;
  final Map<DateTime, int> sessionHistory;
  final bool moodLogLimitReached;

  UserProgress({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalPoints = 0,
    this.currentLevel = 1,
    this.achievements = const [],
    this.moodHistory = const {},
    this.sessionHistory = const {},
    this.moodLogLimitReached = false,
  });

  UserProgress copyWith({
    int? currentStreak,
    int? longestStreak,
    int? totalPoints,
    int? currentLevel,
    List<Achievement>? achievements,
    Map<DateTime, int>? moodHistory,
    Map<DateTime, int>? sessionHistory,
    bool? moodLogLimitReached,
  }) {
    return UserProgress(
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      totalPoints: totalPoints ?? this.totalPoints,
      currentLevel: currentLevel ?? this.currentLevel,
      achievements: achievements ?? this.achievements,
      moodHistory: moodHistory ?? this.moodHistory,
      sessionHistory: sessionHistory ?? this.sessionHistory,
      moodLogLimitReached: moodLogLimitReached ?? this.moodLogLimitReached,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'totalPoints': totalPoints,
      'currentLevel': currentLevel,
      'achievements': achievements.map((a) => a.toJson()).toList(),
      'moodHistory': moodHistory
          .map((key, value) => MapEntry(key.toIso8601String(), value)),
      'sessionHistory': sessionHistory
          .map((key, value) => MapEntry(key.toIso8601String(), value)),
      'moodLogLimitReached': moodLogLimitReached,
    };
  }

  factory UserProgress.fromJson(Map<String, dynamic> json) {
    final moodHistoryMap = (json['moodHistory'] as Map<String, dynamic>?) ?? {};
    final sessionHistoryMap =
        (json['sessionHistory'] as Map<String, dynamic>?) ?? {};

    // Convert string dates back to DateTime
    final moodHistory = moodHistoryMap
        .map((key, value) => MapEntry(DateTime.parse(key), value as int));
    final sessionHistory = sessionHistoryMap
        .map((key, value) => MapEntry(DateTime.parse(key), value as int));

    return UserProgress(
      currentStreak: json['currentStreak'] ?? 0,
      longestStreak: json['longestStreak'] ?? 0,
      totalPoints: json['totalPoints'] ?? 0,
      currentLevel: json['currentLevel'] ?? 1,
      achievements: ((json['achievements'] as List<dynamic>?) ?? [])
          .map((item) => Achievement.fromJson(item as Map<String, dynamic>))
          .toList(),
      moodHistory: moodHistory,
      sessionHistory: sessionHistory,
      moodLogLimitReached: json['moodLogLimitReached'] ?? false,
    );
  }

  // Calculate the points needed for the next level
  int get pointsForNextLevel => currentLevel * 100;

  // Calculate progress towards next level (0.0 to 1.0)
  double get levelProgress {
    final pointsInCurrentLevel = totalPoints - ((currentLevel - 1) * 100);
    return pointsInCurrentLevel / pointsForNextLevel;
  }

  // Calculate the number of active days in the last week (days with mood logs or sessions)
  int get activeDaysLastWeek {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final oneWeekAgo =
        todayStart.subtract(const Duration(days: 6)); // Include today

    // Collect all dates from mood and session history
    final Set<DateTime> activeDays = {};

    // Add days with mood logs
    for (final entry in moodHistory.entries) {
      final dayStart = DateTime(entry.key.year, entry.key.month, entry.key.day);
      if (dayStart.isAfter(oneWeekAgo.subtract(const Duration(days: 1))) &&
          dayStart.isBefore(todayStart.add(const Duration(days: 1)))) {
        activeDays.add(dayStart);
      }
    }

    // Add days with sessions
    for (final entry in sessionHistory.entries) {
      final dayStart = DateTime(entry.key.year, entry.key.month, entry.key.day);
      if (dayStart.isAfter(oneWeekAgo.subtract(const Duration(days: 1))) &&
          dayStart.isBefore(todayStart.add(const Duration(days: 1)))) {
        activeDays.add(dayStart);
      }
    }

    return activeDays.length;
  }

  // Get the number of therapy sessions in the last week
  int get sessionsThisWeek {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final oneWeekAgo =
        todayStart.subtract(const Duration(days: 6)); // Include today

    return sessionHistory.entries.where((entry) {
      final dayStart = DateTime(entry.key.year, entry.key.month, entry.key.day);
      return dayStart.isAfter(oneWeekAgo.subtract(const Duration(days: 1))) &&
          dayStart.isBefore(todayStart.add(const Duration(days: 1)));
    }).length;
  }

  // Get the number of mood logs in the last week
  int get moodLogsThisWeek {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final oneWeekAgo =
        todayStart.subtract(const Duration(days: 6)); // Include today

    return moodHistory.entries.where((entry) {
      final dayStart = DateTime(entry.key.year, entry.key.month, entry.key.day);
      return dayStart.isAfter(oneWeekAgo.subtract(const Duration(days: 1))) &&
          dayStart.isBefore(todayStart.add(const Duration(days: 1)));
    }).length;
  }

  // Get today's mood logs count
  int getTodayMoodLogsCount() {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final tomorrow = today.add(const Duration(days: 1));

    return moodHistory.entries
        .where(
            (entry) => entry.key.isAfter(today) && entry.key.isBefore(tomorrow))
        .length;
  }
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int pointValue;
  final DateTime earnedDate;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.pointValue,
    required this.earnedDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      'pointValue': pointValue,
      'earnedDate': earnedDate.toIso8601String(),
    };
  }

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      icon: Icons.emoji_events,
      pointValue: json['pointValue'],
      earnedDate: DateTime.parse(json['earnedDate']),
    );
  }

  // Predefined achievements
  static Achievement firstSession = Achievement(
    id: 'first_session',
    title: 'First Step',
    description: 'Completed your first therapy session',
    icon: Icons.emoji_events,
    pointValue: 50,
    earnedDate: DateTime.now(),
  );

  static Achievement weekStreak = Achievement(
    id: 'week_streak',
    title: 'Consistent Care',
    description: 'Maintained a 7-day streak',
    icon: Icons.emoji_events,
    pointValue: 100,
    earnedDate: DateTime.now(),
  );

  static Achievement moodTracker = Achievement(
    id: 'mood_tracker',
    title: 'Self-Aware',
    description: 'Tracked your mood for 5 consecutive days',
    icon: Icons.emoji_events,
    pointValue: 75,
    earnedDate: DateTime.now(),
  );
}
