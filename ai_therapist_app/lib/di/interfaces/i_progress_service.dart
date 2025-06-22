// lib/di/interfaces/i_progress_service.dart

import 'package:flutter/material.dart';
import '../../models/user_progress.dart';
import '../../widgets/mood_selector.dart';

/// Interface for progress service operations
/// Provides contract for user progress tracking and gamification
abstract class IProgressService {
  // Current progress
  UserProgress get progress;
  ValueNotifier<UserProgress> get progressChanged;
  
  // Mood logging limits
  bool get moodLogLimitReached;
  
  // Initialization
  Future<void> init();
  
  // Progress metrics
  double getConsistencyRate();
  String getConsistencyStatus();
  Color getConsistencyColor();
  int getProgressMetric(String metric);
  Future<void> updateProgressMetric(String metric, int value);
  Future<void> incrementProgressMetric(String metric, [int amount = 1]);
  
  // Mood tracking
  Future<bool> logMood(Mood mood, [String? notes]);
  Map<String, List<Map<String, dynamic>>> getMoodHistory({
    DateTime? startDate, 
    DateTime? endDate
  });
  List<MapEntry<DateTime, int>> getMoodDataForLastDays(int days);
  
  // Session tracking
  Future<void> logSession(int sessionDuration);
  List<MapEntry<DateTime, int>> getSessionDataForLastDays(int days);
  
  // Progress management
  Future<void> resetProgress();
}