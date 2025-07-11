// lib/services/progress_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_progress.dart';
import '../services/notification_service.dart';
import 'package:flutter/foundation.dart';
import '../widgets/mood_selector.dart';
import '../di/interfaces/i_progress_service.dart';
import '../di/dependency_container.dart';

class ProgressService implements IProgressService {
  static const String _progressKey = 'user_progress';
  final NotificationService _notificationService;
  
  // Current progress in memory
  UserProgress _currentProgress = UserProgress();
  
  // Getter for current progress (immutable copy)
  @override
  UserProgress get progress => _currentProgress;
  
  // Value notifier for progress changes
  final _progressChangedController = ValueNotifier<UserProgress>(UserProgress());
  
  // Observable stream of progress changes
  @override
  ValueNotifier<UserProgress> get progressChanged => _progressChangedController;
  
  // Flag to track if mood log limit has been reached
  bool _moodLogLimitReached = false;
  @override
  bool get moodLogLimitReached => _moodLogLimitReached;
  
  // Mock mood history data
  final Map<String, List<Map<String, dynamic>>> _moodHistory = {};
  
  // Mock progress data
  final Map<String, int> _progressData = {
    'sessionsCompleted': 0,
    'streakDays': 0,
    'goalsAchieved': 0,
    'exercisesCompleted': 0,
  };
  
  ProgressService({required NotificationService notificationService}) 
      : _notificationService = notificationService;
  
  // Initialize progress
  @override
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final progressString = prefs.getString(_progressKey);
    
    if (progressString != null) {
      try {
        final json = jsonDecode(progressString);
        _currentProgress = UserProgress.fromJson(json);
      } catch (e) {
        debugPrint('Error loading progress: $e');
        _currentProgress = UserProgress();
      }
    }
    
    // Load real session data
    await _loadRealSessionData();
    
    // Update notifier with initial value
    _progressChangedController.value = _currentProgress;
    
    if (kDebugMode) {
      print('Progress service initialized with real data');
    }
  }
  
  // Load real session data from SessionRepository
  Future<void> _loadRealSessionData() async {
    try {
      final sessionRepository = DependencyContainer().sessionRepository;
      final sessions = await sessionRepository.getSessions();
      
      // Convert sessions to session history map
      final Map<DateTime, int> realSessionHistory = {};
      int currentStreak = 0;
      int longestStreak = 0;
      
      for (final session in sessions) {
        try {
          final sessionDate = session.createdAt ?? DateTime.now();
          final dayStart = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);
          
          // Calculate duration in minutes (default to 30 if not available)
          int duration = 30; // Default duration if not available
          // TODO: Add duration calculation when session model has endTime field
          
          // Add or update session for this day
          realSessionHistory[dayStart] = (realSessionHistory[dayStart] ?? 0) + duration;
        } catch (e) {
          debugPrint('Error processing session: $e');
        }
      }
      
      // Calculate streaks
      if (realSessionHistory.isNotEmpty) {
        final sortedDays = realSessionHistory.keys.toList()..sort();
        
        // Calculate current streak
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);
        currentStreak = 0;
        
        for (int i = sortedDays.length - 1; i >= 0; i--) {
          final daysDiff = todayStart.difference(sortedDays[i]).inDays;
          if (daysDiff == currentStreak || (daysDiff == currentStreak + 1 && currentStreak == 0)) {
            currentStreak++;
          } else {
            break;
          }
        }
        
        // Calculate longest streak
        int tempStreak = 1;
        longestStreak = 1;
        
        for (int i = 1; i < sortedDays.length; i++) {
          if (sortedDays[i].difference(sortedDays[i - 1]).inDays == 1) {
            tempStreak++;
            longestStreak = tempStreak > longestStreak ? tempStreak : longestStreak;
          } else {
            tempStreak = 1;
          }
        }
      }
      
      // Update progress with real data
      _currentProgress = _currentProgress.copyWith(
        sessionHistory: realSessionHistory,
        currentStreak: currentStreak,
        longestStreak: longestStreak,
      );
      
      // Save updated progress
      await _saveProgress();
      
      debugPrint('Loaded ${sessions.length} real sessions');
      debugPrint('Current streak: $currentStreak, Longest streak: $longestStreak');
      
    } catch (e) {
      debugPrint('Error loading real session data: $e');
      // If we can't load real data, add some mock data for demo purposes
      final today = DateTime.now();
      _addMockMoodHistory(today);
      _addMockSessionHistory(today);
    }
  }
  
  // Add mock mood history entries
  void _addMockMoodHistory(DateTime today) {
    // Create map for storing mock history
    final mockMoodHistory = <DateTime, int>{};
    
    // Add entries for the past week to test consistency tracking
    for (int i = 1; i <= 5; i++) {
      final day = today.subtract(Duration(days: i));
      // Add a mood entry (use different moods for variety)
      mockMoodHistory[day] = (i % 5) + 1; // Values 1-5 for different moods
    }
    
    // Add today's entry
    mockMoodHistory[today] = 0; // Happy mood for today
    
    // Update the current progress with mock data
    _currentProgress = _currentProgress.copyWith(
      moodHistory: mockMoodHistory,
    );
    
    // Also add to mood history in the format used by other methods
    mockMoodHistory.forEach((dateTime, moodValue) {
      final dateStr = _formatDate(dateTime);
      
      // Convert numeric mood value to enum
      Mood mood = Mood.values[moodValue % Mood.values.length];
      
      if (!_moodHistory.containsKey(dateStr)) {
        _moodHistory[dateStr] = [];
      }
      
      _moodHistory[dateStr]!.add({
        'mood': mood, 
        'timestamp': dateTime.millisecondsSinceEpoch,
      });
    });
  }
  
  // Add mock session history for testing consistency
  void _addMockSessionHistory(DateTime today) {
    // Create map for storing mock sessions
    final mockSessionHistory = <DateTime, int>{};
    
    // Add entries for the past week to test consistency tracking
    for (int i = 0; i <= 4; i += 2) { // Sessions every other day
      final day = today.subtract(Duration(days: i));
      // Add a session entry (minutes)
      mockSessionHistory[day] = 20 + (i * 5); // Session duration 20-40 minutes
    }
    
    // Update the current progress with mock data
    _currentProgress = _currentProgress.copyWith(
      sessionHistory: mockSessionHistory,
      currentStreak: 3, // Set a mock streak
    );
  }
  
  // Format date as YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
  
  // Get today's date as a string
  String _getTodayDate() {
    final now = DateTime.now();
    return _formatDate(now);
  }
  
  // Get mood logs for the current day
  List<Map<String, dynamic>> _getTodayMoodLogs() {
    final today = _getTodayDate();
    return _moodHistory[today] ?? [];
  }
  
  // Save progress to storage
  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_currentProgress.toJson());
      await prefs.setString(_progressKey, json);
      
      // Update notifier with new value
      _progressChangedController.value = _currentProgress;
    } catch (e) {
      debugPrint('Error saving progress: $e');
    }
  }
  
  // Get user consistency rate (percentage of active days in the last week)
  @override
  double getConsistencyRate() {
    // We're now using the getter from UserProgress
    return _currentProgress.activeDaysLastWeek / 7.0;
  }

  // Get consistency status
  @override
  String getConsistencyStatus() {
    final rate = getConsistencyRate();
    if (rate >= 0.75) return 'Very Consistent';
    if (rate >= 0.5) return 'Consistent';
    return 'Inconsistent';
  }
  
  // Get consistency color
  @override
  Color getConsistencyColor() {
    final rate = getConsistencyRate();
    if (rate >= 0.75) return Colors.green;
    if (rate >= 0.5) return Colors.orange;
    return Colors.red;
  }
  
  // Log a mood entry
  @override
  Future<bool> logMood(Mood mood, [String? notes]) async {
    try {
      // Check if we've reached the daily limit of 3 entries
      final todayLogs = _getTodayMoodLogs();
      if (todayLogs.length >= 3) {
        _moodLogLimitReached = true;
        return false;
      }
      
      // Reset limit flag
      _moodLogLimitReached = false;
      
      // Get today's date
      final today = _getTodayDate();
      final todayDateTime = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      
      // Create mood entry
      final entry = {
        'mood': mood, 
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'notes': notes
      };
      
      // Add to history
      if (!_moodHistory.containsKey(today)) {
        _moodHistory[today] = [];
      }
      _moodHistory[today]!.add(entry);
      
      // Update progress mood history
      final updatedMoodHistory = Map<DateTime, int>.from(_currentProgress.moodHistory);
      updatedMoodHistory[todayDateTime] = (updatedMoodHistory[todayDateTime] ?? 0) + 1;
      
      // Update the progress object
      _currentProgress = _currentProgress.copyWith(
        moodHistory: updatedMoodHistory,
      );
      
      // Save to persistent storage
      await _saveProgress();
      
      if (kDebugMode) {
        print('Mood logged: $mood, Notes: $notes');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error logging mood: $e');
      }
      return false;
    }
  }
  
  // Get mood history for a specific date range
  @override
  Map<String, List<Map<String, dynamic>>> getMoodHistory({
    DateTime? startDate, 
    DateTime? endDate
  }) {
    // If no date range is specified, return all history
    if (startDate == null && endDate == null) {
      return Map.from(_moodHistory);
    }
    
    // Filter by date range
    final filteredHistory = <String, List<Map<String, dynamic>>>{};
    final now = DateTime.now();
    final start = startDate ?? DateTime(2000);
    final end = endDate ?? now;
    
    _moodHistory.forEach((dateStr, entries) {
      final dateParts = dateStr.split('-');
      final date = DateTime(
        int.parse(dateParts[0]), 
        int.parse(dateParts[1]), 
        int.parse(dateParts[2])
      );
      
      if (date.isAfter(start) && date.isBefore(end.add(const Duration(days: 1)))) {
        filteredHistory[dateStr] = entries;
      }
    });
    
    return filteredHistory;
  }
  
  // Get a progress metric
  @override
  int getProgressMetric(String metric) {
    return _progressData[metric] ?? 0;
  }
  
  // Update a progress metric
  @override
  Future<void> updateProgressMetric(String metric, int value) async {
    _progressData[metric] = value;
    // In a real app, we would save to persistent storage here
  }
  
  // Increment a progress metric
  @override
  Future<void> incrementProgressMetric(String metric, [int amount = 1]) async {
    final currentValue = _progressData[metric] ?? 0;
    _progressData[metric] = currentValue + amount;
    // In a real app, we would save to persistent storage here
  }
  
  // Log a completed session
  @override
  Future<void> logSession(int sessionDuration) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Update session history
    final updatedSessionHistory = Map<DateTime, int>.from(_currentProgress.sessionHistory);
    updatedSessionHistory[today] = (updatedSessionHistory[today] ?? 0) + sessionDuration;
    
    // Recalculate streaks after adding new session
    final sortedDays = updatedSessionHistory.keys.toList()..sort();
    int currentStreak = 0;
    int longestStreak = 0;
    
    if (sortedDays.isNotEmpty) {
      // Calculate current streak
      final todayStart = DateTime(now.year, now.month, now.day);
      currentStreak = 0;
      
      for (int i = sortedDays.length - 1; i >= 0; i--) {
        final daysDiff = todayStart.difference(sortedDays[i]).inDays;
        if (daysDiff == currentStreak || (daysDiff == currentStreak + 1 && currentStreak == 0)) {
          currentStreak++;
        } else {
          break;
        }
      }
      
      // Calculate longest streak
      int tempStreak = 1;
      longestStreak = 1;
      
      for (int i = 1; i < sortedDays.length; i++) {
        if (sortedDays[i].difference(sortedDays[i - 1]).inDays == 1) {
          tempStreak++;
          longestStreak = tempStreak > longestStreak ? tempStreak : longestStreak;
        } else {
          tempStreak = 1;
        }
      }
    }
    
    // Award points based on session duration (1 point per minute, capped at 60)
    final pointsEarned = sessionDuration < 60 ? sessionDuration : 60;
    final updatedPoints = _currentProgress.totalPoints + pointsEarned;
    
    // Check for first session achievement
    List<Achievement> updatedAchievements = List.from(_currentProgress.achievements);
    if (!_hasAchievement('first_session')) {
      updatedAchievements.add(Achievement.firstSession);
      
      // Show achievement notification
      _notificationService.showNotification(
        id: 104,
        title: 'Achievement Unlocked!',
        body: 'First Step: You completed your first therapy session',
      );
    }
    
    // Check for level up
    int currentLevel = _currentProgress.currentLevel;
    if (updatedPoints >= currentLevel * 100) {
      currentLevel += 1;
      
      // Show level up notification
      _notificationService.showNotification(
        id: 105,
        title: 'Level Up!',
        body: 'You reached Level $currentLevel',
      );
    }
    
    // Update progress with recalculated streaks
    _currentProgress = _currentProgress.copyWith(
      sessionHistory: updatedSessionHistory,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalPoints: updatedPoints,
      currentLevel: currentLevel,
      achievements: updatedAchievements,
    );
    
    await _saveProgress();
  }
  
  // Sync session data from repository (call this after session completion)
  @override
  Future<void> syncSessionData() async {
    await _loadRealSessionData();
  }
  
  // Check if user has an achievement
  bool _hasAchievement(String achievementId) {
    return _currentProgress.achievements.any((a) => a.id == achievementId);
  }
  
  // Get mood data for visualization
  @override
  List<MapEntry<DateTime, int>> getMoodDataForLastDays(int days) {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));
    
    return _currentProgress.moodHistory.entries
        .where((entry) => entry.key.isAfter(startDate) && entry.key.isBefore(endDate))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }
  
  // Get session data for visualization
  @override
  List<MapEntry<DateTime, int>> getSessionDataForLastDays(int days) {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));
    
    return _currentProgress.sessionHistory.entries
        .where((entry) => entry.key.isAfter(startDate) && entry.key.isBefore(endDate))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }
  
  // Reset all progress data
  @override
  Future<void> resetProgress() async {
    _currentProgress = UserProgress();
    await _saveProgress();
  }
} 