// lib/di/interfaces/i_progress_service.dart
import 'package:flutter/material.dart';
import '../../models/user_progress.dart';
import '../../models/mood_entry_record.dart';
import '../../widgets/mood_selector.dart';
abstract class IProgressService {
  UserProgress get progress;
  ValueNotifier<UserProgress> get progressChanged;
  bool get moodLogLimitReached;
  Future<void> init();
  double getConsistencyRate();
  String getConsistencyStatus();
  Color getConsistencyColor(BuildContext context);
  int getProgressMetric(String metric);
  Future<void> updateProgressMetric(String metric, int value);
  Future<void> incrementProgressMetric(String metric, [int amount = 1]);
  Future<bool> logMood(Mood mood, [String? notes]);
  Map<String, List<Map<String, dynamic>>> getMoodHistory(
      {DateTime? startDate, DateTime? endDate});
  List<MapEntry<DateTime, int>> getMoodDataForLastDays(int days);
  int getTotalMoodEntriesCount();
  Future<void> logSession(int sessionDuration);
  List<MapEntry<DateTime, int>> getSessionDataForLastDays(int days);
  Future<void> syncSessionData();
  Future<void> syncMoodEntries({bool force});
  Future<List<MoodEntryRecord>> getPendingMoodEntries();
  Future<void> clearMoodSyncErrors();
  bool consumeLastMoodLogWasLocalOnly();
  bool consumePendingMoodSyncError();
  Future<void> resetProgress();
}
