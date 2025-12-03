// lib/services/progress_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';
import '../data/datasources/local/database_provider.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/i_api_client.dart';
import '../data/datasources/remote/api_client.dart' show ApiException;
import '../di/interfaces/i_progress_service.dart';
import '../models/mood_entry_record.dart';
import '../models/user_progress.dart';
import '../services/notification_service.dart';
import '../widgets/mood_selector.dart';
import '../utils/feature_flags.dart';
import '../utils/connectivity_checker.dart';
import '../utils/date_time_utils.dart';

class ProgressService implements IProgressService {
  static const String _progressKey = 'user_progress';
  static const String _localUserIdKey = 'progress_local_user_id';
  static const String _moodEntriesTable = 'mood_entries';
  static const String _lastMoodSyncKey = 'last_mood_sync_at';
  static const Duration _moodRetentionDuration = Duration(days: 60);

  final NotificationService _notificationService;
  final DatabaseProvider _databaseProvider;

  UserProgress _currentProgress = UserProgress();

  final List<MoodEntryRecord> _moodEntries = [];
  final Map<String, List<Map<String, dynamic>>> _moodHistory = {};

  Future<void>? _moodCacheLoadFuture;
  bool _isMoodCacheLoaded = false;
  String? _cachedUserId;
  DateTime? _lastMoodSyncAt;
  Timer? _moodSyncDebounceTimer;
  final Random _random = Random();
  Timer? _dailyPurgeTimer;
  bool _lastMoodLogWasLocalOnly = false;
  bool _hasPendingMoodSyncError = false;

  final _progressChangedController =
      ValueNotifier<UserProgress>(UserProgress());

  bool _moodLogLimitReached = false;
  bool _isMoodSyncInProgress = false;

  ProgressService({
    required NotificationService notificationService,
    required DatabaseProvider databaseProvider,
  })  : _notificationService = notificationService,
        _databaseProvider = databaseProvider;

  @override
  UserProgress get progress => _currentProgress;

  @override
  ValueNotifier<UserProgress> get progressChanged => _progressChangedController;

  @override
  bool get moodLogLimitReached => _moodLogLimitReached;
  // Mock progress data
  final Map<String, int> _progressData = {
    'sessionsCompleted': 0,
    'streakDays': 0,
    'goalsAchieved': 0,
    'exercisesCompleted': 0,
  };

  // Initialize progress
  @override
  Future<void> init() async {
    await _databaseProvider.init();
    await _loadPersistedProgress();
    await _loadRealSessionData();
    await _ensureMoodCacheLoaded();
    _scheduleDailyMoodPurge();

    if (FeatureFlags.isMoodPersistenceEnabled) {
      _scheduleMoodSync();
    }

    _progressChangedController.value = _currentProgress;

    if (kDebugMode) {
      debugPrint('Progress service initialized with real data and mood cache');
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
          final dayStart =
              DateTime(sessionDate.year, sessionDate.month, sessionDate.day);

          // Calculate duration in minutes (default to 30 if not available)
          int duration = 30; // Default duration if not available
          // TODO: Add duration calculation when session model has endTime field

          // Add or update session for this day
          realSessionHistory[dayStart] =
              (realSessionHistory[dayStart] ?? 0) + duration;
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
          if (daysDiff == currentStreak ||
              (daysDiff == currentStreak + 1 && currentStreak == 0)) {
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
            longestStreak =
                tempStreak > longestStreak ? tempStreak : longestStreak;
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
      debugPrint(
          'Current streak: $currentStreak, Longest streak: $longestStreak');
    } catch (e) {
      debugPrint('Error loading real session data: $e');
      // If we can't load real data, add some mock data for demo purposes
      final today = DateTime.now();
      await _addMockMoodHistory(today);
      _addMockSessionHistory(today);
    }
  }

  Future<void> _ensureMoodCacheLoaded() async {
    if (_isMoodCacheLoaded) {
      return;
    }

    _moodCacheLoadFuture ??= _loadMoodEntriesFromDatabase();
    await _moodCacheLoadFuture;
  }

  Future<void> _loadMoodEntriesFromDatabase() async {
    try {
      final userId = await _resolveUserId();
      await _purgeExpiredMoodEntries(userId);

      final cutoff = DateTime.now().toUtc().subtract(_moodRetentionDuration);
      final rows = await _databaseProvider.query(
        _moodEntriesTable,
        where: 'user_id = ? AND datetime(logged_at) >= datetime(?)',
        whereArgs: [userId, cutoff.toIso8601String()],
        orderBy: 'datetime(logged_at) DESC',
      );

      final entries = rows
          .map((row) => MoodEntryRecord.fromMap(row))
          .toList(growable: false);

      await _replaceMoodEntries(entries, persist: false);
      _moodLogLimitReached = _entriesForDay(DateTime.now()).length >= 3;
      _hasPendingMoodSyncError =
          _moodEntries.any((entry) => entry.syncError?.isNotEmpty ?? false);
      _isMoodCacheLoaded = true;
    } catch (e, stackTrace) {
      debugPrint('Error loading mood entries from database: $e');
      debugPrint('$stackTrace');
      _isMoodCacheLoaded = true;
    }
  }

  Future<void> _replaceMoodEntries(List<MoodEntryRecord> entries,
      {bool persist = true}) async {
    _moodEntries
      ..clear()
      ..addAll(entries);
    _rebuildMoodAggregates();

    if (persist) {
      await _saveProgress();
    } else {
      _progressChangedController.value = _currentProgress;
    }
  }

  void _rebuildMoodAggregates() {
    _moodHistory.clear();
    final Map<DateTime, List<MoodEntryRecord>> entriesByDay = {};

    if (kDebugMode) {
      debugPrint('[ProgressService] _rebuildMoodAggregates called with ${_moodEntries.length} entries');
    }

    for (final entry in _moodEntries) {
      final loggedAtLocal = entry.loggedAt.toLocal();
      final dayStart =
          DateTime(loggedAtLocal.year, loggedAtLocal.month, loggedAtLocal.day);
      entriesByDay.putIfAbsent(dayStart, () => []).add(entry);

      final dayKey = _formatDate(dayStart);
      _moodHistory.putIfAbsent(dayKey, () => []).add({
        'mood': _moodFromIndex(entry.mood),
        'timestamp': loggedAtLocal.millisecondsSinceEpoch,
        'notes': entry.notes,
        'clientEntryId': entry.clientEntryId,
        'isPending': entry.isPending,
        'syncError': entry.syncError,
      });
    }

    final Map<DateTime, int> aggregated = {};
    entriesByDay.forEach((day, records) {
      if (records.isEmpty) {
        return;
      }
      final averageMood = records
              .map((record) => record.mood)
              .fold<int>(0, (sum, value) => sum + value) /
          records.length;
      final clamped = averageMood.round().clamp(0, Mood.values.length - 1);
      aggregated[day] = clamped;
    });

    _currentProgress = _currentProgress.copyWith(moodHistory: aggregated);

    if (kDebugMode) {
      debugPrint('[ProgressService] After aggregation: ${aggregated.length} days in moodHistory');
      if (aggregated.isNotEmpty) {
        final sortedEntries = aggregated.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        debugPrint('[ProgressService] First day: ${sortedEntries.first.key} -> ${sortedEntries.first.value}');
        debugPrint('[ProgressService] Last day: ${sortedEntries.last.key} -> ${sortedEntries.last.value}');
      }
    }
  }

  Future<void> _purgeExpiredMoodEntries(String userId) async {
    final cutoff = DateTime.now().toUtc().subtract(_moodRetentionDuration);
    await _databaseProvider.delete(
      _moodEntriesTable,
      where: 'user_id = ? AND datetime(logged_at) < datetime(?)',
      whereArgs: [userId, cutoff.toIso8601String()],
    );
  }

  Mood _moodFromIndex(int index) {
    if (index < 0 || index >= Mood.values.length) {
      return Mood.neutral;
    }
    return Mood.values[index];
  }

  Future<String> _resolveUserId() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      _cachedUserId = firebaseUser.uid;
      return firebaseUser.uid;
    }

    if (_cachedUserId != null) {
      return _cachedUserId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_localUserIdKey);
    if (stored != null && stored.isNotEmpty) {
      _cachedUserId = stored;
      return stored;
    }

    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_localUserIdKey, localId);
    _cachedUserId = localId;
    return localId;
  }

  IApiClient? _getApiClientOrNull() {
    try {
      return DependencyContainer().apiClient;
    } catch (_) {
      return null;
    }
  }

  List<MoodEntryRecord> _entriesForDay(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final nextDay = dayStart.add(const Duration(days: 1));
    return _moodEntries.where((entry) {
      final loggedAtLocal = entry.loggedAt.toLocal();
      return !loggedAtLocal.isBefore(dayStart) &&
          loggedAtLocal.isBefore(nextDay);
    }).toList(growable: false);
  }

  void _scheduleMoodSync() {
    if (!FeatureFlags.isMoodPersistenceEnabled) {
      return;
    }

    const minDelayMs = 500;
    const maxDelayMs = 3000;
    final jitterMs =
        minDelayMs + (_random.nextDouble() * (maxDelayMs - minDelayMs)).round();

    _moodSyncDebounceTimer?.cancel();
    _moodSyncDebounceTimer = Timer(
        Duration(milliseconds: jitterMs), () => unawaited(syncMoodEntries()));
  }

  void _scheduleDailyMoodPurge() {
    _dailyPurgeTimer?.cancel();
    _dailyPurgeTimer = Timer.periodic(
        const Duration(hours: 24), (_) => unawaited(_runDailyMoodPurge()));
    unawaited(_runDailyMoodPurge());
  }

  Future<void> _runDailyMoodPurge() async {
    try {
      final userId = await _resolveUserId();
      await _purgeExpiredMoodEntries(userId);
      final cutoff = DateTime.now().toUtc().subtract(_moodRetentionDuration);
      _moodEntries.removeWhere((entry) => entry.loggedAt.isBefore(cutoff));
      _rebuildMoodAggregates();
      await _saveProgress();
    } catch (e, stackTrace) {
      debugPrint('Error during daily mood purge: $e');
      debugPrint('$stackTrace');
    }
  }

  String? _sanitizeNotes(String? notes) {
    if (notes == null) {
      return null;
    }

    final trimmed = notes.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.length > 512) {
      return trimmed.substring(0, 512);
    }

    return trimmed;
  }

  Iterable<List<MoodEntryRecord>> _chunkMoodEntries(
      List<MoodEntryRecord> entries, int chunkSize) sync* {
    if (chunkSize <= 0) {
      yield entries;
      return;
    }

    for (var i = 0; i < entries.length; i += chunkSize) {
      final end =
          (i + chunkSize) > entries.length ? entries.length : i + chunkSize;
      yield entries.sublist(i, end);
    }
  }

  Future<void> _pushMoodEntries(
      IApiClient apiClient, List<MoodEntryRecord> batch) async {
    if (batch.isEmpty) {
      return;
    }

    final payload = {
      'entries': batch
          .map((entry) => {
                'client_entry_id': entry.clientEntryId,
                'mood': entry.mood,
                'notes': _sanitizeNotes(entry.notes),
                'logged_at': entry.loggedAt.toUtc().toIso8601String(),
              })
          .toList(growable: false),
    };

    final response =
        await apiClient.post('/mood_entries:batch_upsert', payload);
    final results = (response['results'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    if (results.isNotEmpty) {
      await _applyUpsertResults(results);
    }
  }

  Future<void> _applyUpsertResults(List<Map<String, dynamic>> results) async {
    if (results.isEmpty) {
      return;
    }

    final userId = await _resolveUserId();
    final syncMoment = DateTime.now().toUtc();

    for (final item in results) {
      final clientEntryId = item['client_entry_id'] as String;
      final serverId = item['id'] as String?;
      final updatedAtIso = item['updated_at'] as String?;
      final loggedAtIso = item['logged_at'] as String?;
      final moodValue = (item['mood'] as num?)?.toInt();
      final notesValue = _sanitizeNotes(item['notes'] as String?);

      final updateValues = <String, Object?>{
        'server_id': serverId,
        'is_pending': 0,
        'sync_error': null,
        'last_synced_at': syncMoment.toIso8601String(),
      };

      if (updatedAtIso != null) {
        updateValues['updated_at'] = parseBackendDateTimeToUtc(updatedAtIso)
            .toIso8601String();
      }
      if (loggedAtIso != null) {
        updateValues['logged_at'] =
            parseBackendDateTimeToUtc(loggedAtIso).toIso8601String();
      }
      if (moodValue != null) {
        updateValues['mood'] = moodValue;
      }
      updateValues['notes'] = notesValue;

      final updated = await _databaseProvider.update(
        _moodEntriesTable,
        updateValues,
        where: 'user_id = ? AND client_entry_id = ?',
        whereArgs: [userId, clientEntryId],
      );

      if (updated == 0) {
        final record = MoodEntryRecord(
          id: serverId ?? clientEntryId,
          userId: userId,
          clientEntryId: clientEntryId,
          mood: moodValue ?? 0,
          notes: notesValue,
          loggedAt: loggedAtIso != null
              ? parseBackendDateTimeToUtc(loggedAtIso)
              : DateTime.now().toUtc(),
          serverId: serverId,
          updatedAt: updatedAtIso != null
              ? parseBackendDateTimeToUtc(updatedAtIso)
              : DateTime.now().toUtc(),
          isPending: false,
          lastSyncedAt: syncMoment,
          syncError: null,
        );
        await _databaseProvider.insert(_moodEntriesTable, record.toMap());
      }
    }
  }

  Future<void> _markEntriesSyncError(
      List<MoodEntryRecord> entries, String code) async {
    if (entries.isEmpty) {
      return;
    }

    final userId = await _resolveUserId();
    _hasPendingMoodSyncError = true;
    for (final entry in entries) {
      await _databaseProvider.update(
        _moodEntriesTable,
        {
          'sync_error': code,
          'is_pending': 1,
        },
        where: 'user_id = ? AND client_entry_id = ?',
        whereArgs: [userId, entry.clientEntryId],
      );
    }

    unawaited(_notificationService.showNotification(
      id: 901,
      title: 'Mood sync pending',
      body: 'Saved locally; we\'ll sync when you\'re online.',
    ));
  }

  Future<void> _pullMoodEntries(IApiClient apiClient) async {
    final sinceIso = _lastMoodSyncAt?.toUtc().toIso8601String();
    String? beforeToken;
    var safetyCounter = 0;

    while (safetyCounter < 10) {
      final queryParams = <String, String>{
        'limit': '50',
      };
      if (sinceIso != null) {
        queryParams['since'] = sinceIso;
      }
      if (beforeToken != null) {
        queryParams['before'] = beforeToken;
      }

      Map<String, dynamic> response;
      try {
        response = await apiClient.get(
          '/mood_entries',
          queryParams: queryParams,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          if (kDebugMode) {
            debugPrint('Mood entries endpoint unavailable (404); skipping');
          }
          return;
        }
        rethrow;
      }

      final results = (response['results'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      if (results.isEmpty) {
        break;
      }

      await _ingestRemoteEntries(results);

      beforeToken = response['next_before'] as String?;
      if (beforeToken == null) {
        break;
      }

      safetyCounter++;
    }

    _lastMoodSyncAt = DateTime.now().toUtc();
  }

  Future<void> _ingestRemoteEntries(List<Map<String, dynamic>> entries) async {
    if (entries.isEmpty) {
      return;
    }

    final userId = await _resolveUserId();
    final syncMoment = DateTime.now().toUtc();

    for (final item in entries) {
      final record = _recordFromRemoteMap(userId, item, syncMoment);
      await _databaseProvider.insert(_moodEntriesTable, record.toMap());
    }
  }

  MoodEntryRecord _recordFromRemoteMap(
      String userId, Map<String, dynamic> data, DateTime syncMoment) {
    final serverId = data['id'] as String?;
    final clientEntryId = data['client_entry_id'] as String;
    final moodValue = (data['mood'] as num?)?.toInt() ?? 0;
    final notesValue = _sanitizeNotes(data['notes'] as String?);
    final loggedAtIso = data['logged_at'] as String?;
    final updatedAtIso = data['updated_at'] as String?;
    final loggedAt = loggedAtIso != null
        ? parseBackendDateTimeToUtc(loggedAtIso)
        : DateTime.now().toUtc();
    final updatedAt = updatedAtIso != null
        ? parseBackendDateTimeToUtc(updatedAtIso)
        : DateTime.now().toUtc();

    return MoodEntryRecord(
      id: serverId ?? clientEntryId,
      userId: userId,
      clientEntryId: clientEntryId,
      mood: moodValue,
      notes: notesValue,
      loggedAt: loggedAt,
      serverId: serverId,
      updatedAt: updatedAt,
      isPending: false,
      lastSyncedAt: syncMoment,
      syncError: null,
    );
  }

  Future<void> _loadPersistedProgress() async {
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

    final lastSyncIso = prefs.getString(_lastMoodSyncKey);
    if (lastSyncIso != null && lastSyncIso.isNotEmpty) {
      try {
        _lastMoodSyncAt = parseBackendDateTimeToUtc(lastSyncIso);
      } catch (e) {
        debugPrint('Error parsing last mood sync timestamp: $e');
        _lastMoodSyncAt = null;
      }
    }
  }

  // Add mock mood history entries
  Future<void> _addMockMoodHistory(DateTime today) async {
    final userId = await _resolveUserId();
    final mockEntries = <MoodEntryRecord>[];

    for (int i = 5; i >= 1; i--) {
      final day = today.subtract(Duration(days: i));
      final moodIndex = i % Mood.values.length;
      mockEntries.add(
        MoodEntryRecord.newLocal(
          userId: userId,
          mood: moodIndex,
          loggedAt: day,
        ).copyWith(isPending: false),
      );
    }

    mockEntries.add(
      MoodEntryRecord.newLocal(
        userId: userId,
        mood: 0,
        loggedAt: today,
      ).copyWith(isPending: false),
    );

    await _replaceMoodEntries(mockEntries, persist: false);
  }

  // Add mock session history for testing consistency
  void _addMockSessionHistory(DateTime today) {
    // Create map for storing mock sessions
    final mockSessionHistory = <DateTime, int>{};

    // Add entries for the past week to test consistency tracking
    for (int i = 0; i <= 4; i += 2) {
      // Sessions every other day
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
      if (_lastMoodSyncAt != null) {
        await prefs.setString(
            _lastMoodSyncKey, _lastMoodSyncAt!.toUtc().toIso8601String());
      } else {
        await prefs.remove(_lastMoodSyncKey);
      }

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
  Color getConsistencyColor(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final rate = getConsistencyRate();

    if (rate >= 0.75) {
      return palette?.accentPrimary ?? theme.colorScheme.secondary;
    }
    if (rate >= 0.5) {
      return palette?.accentSecondary ?? theme.colorScheme.tertiary;
    }
    return theme.colorScheme.error;
  }

  // Log a mood entry
  @override
  Future<bool> logMood(Mood mood, [String? notes]) async {
    try {
      if (kDebugMode) {
        debugPrint('[ProgressService] logMood called with mood: ${mood.label}');
      }

      await _ensureMoodCacheLoaded();

      if (kDebugMode) {
        debugPrint('[ProgressService] Mood cache loaded. Total entries: ${_moodEntries.length}');
      }

      final bool offline = FeatureFlags.isMoodPersistenceEnabled &&
          await ConnectivityChecker().isOffline();
      _lastMoodLogWasLocalOnly = offline;

      if (kDebugMode) {
        debugPrint('[ProgressService] Offline status: $offline');
      }

      // Check if we've reached the daily limit of 3 entries
      final now = DateTime.now();
      final todayEntries = _entriesForDay(now);
      if (kDebugMode) {
        debugPrint('[ProgressService] Current date/time: $now (local)');
        debugPrint('[ProgressService] Today\'s entries count: ${todayEntries.length}');
        if (todayEntries.isNotEmpty) {
          debugPrint('[ProgressService] Today\'s entries:');
          for (final entry in todayEntries) {
            debugPrint('  - ${entry.loggedAt.toLocal()}: ${Mood.values[entry.mood].label}');
          }
        }
      }

      // If we've reached the daily limit of 3 entries, remove the oldest one
      if (todayEntries.length >= 3) {
        // Sort by logged time to find the oldest entry
        final oldestEntry = todayEntries.reduce((a, b) =>
          a.loggedAt.isBefore(b.loggedAt) ? a : b
        );

        if (kDebugMode) {
          debugPrint('[ProgressService] Daily limit reached (3 moods). Removing oldest: ${oldestEntry.loggedAt.toLocal()}');
        }

        // Delete the oldest entry from database
        await _databaseProvider.delete(
          _moodEntriesTable,
          where: 'client_entry_id = ?',
          whereArgs: [oldestEntry.clientEntryId],
        );

        // Remove from in-memory cache
        _moodEntries.removeWhere((e) => e.clientEntryId == oldestEntry.clientEntryId);

        if (kDebugMode) {
          debugPrint('[ProgressService] Oldest mood entry removed. Now have ${todayEntries.length - 1} entries today.');
        }
      }

      // Update limit flag - will be recalculated after insert
      _moodLogLimitReached = false;

      final sanitizedNotes = _sanitizeNotes(notes);
      final userId = await _resolveUserId();
      final record = MoodEntryRecord.newLocal(
        userId: userId,
        mood: mood.index,
        loggedAt: DateTime.now(),
        notes: sanitizedNotes,
      );

      await _databaseProvider.insert(_moodEntriesTable, record.toMap());

      // Prepend to local cache and recompute aggregates
      _moodEntries.insert(0, record);
      _rebuildMoodAggregates();

      // Debug: Log mood aggregates after rebuild
      if (kDebugMode) {
        debugPrint('[ProgressService] After _rebuildMoodAggregates:');
        debugPrint('  _moodEntries.length: ${_moodEntries.length}');
        debugPrint('  _currentProgress.moodHistory.length: ${_currentProgress.moodHistory.length}');
        if (_currentProgress.moodHistory.isNotEmpty) {
          debugPrint('  First moodHistory entry: ${_currentProgress.moodHistory.entries.first}');
        }
      }

      await _saveProgress();

      // Update limit flag after insert
      final updatedTodayEntries = _entriesForDay(DateTime.now());
      _moodLogLimitReached = updatedTodayEntries.length >= 3;

      _scheduleMoodSync();

      if (kDebugMode) {
        debugPrint('Mood logged: $mood, Notes: $notes');
      }

      if (kDebugMode) {
        debugPrint('[ProgressService] ✅ Mood logged successfully');
      }

      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[ProgressService] ❌ Error logging mood: $e');
        debugPrint('[ProgressService] Stack trace: $stackTrace');
      }
      return false;
    }
  }

  // Get mood history for a specific date range
  @override
  Map<String, List<Map<String, dynamic>>> getMoodHistory(
      {DateTime? startDate, DateTime? endDate}) {
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
      final date = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]),
          int.parse(dateParts[2]));

      if (date.isAfter(start) &&
          date.isBefore(end.add(const Duration(days: 1)))) {
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
    final updatedSessionHistory =
        Map<DateTime, int>.from(_currentProgress.sessionHistory);
    updatedSessionHistory[today] =
        (updatedSessionHistory[today] ?? 0) + sessionDuration;

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
        if (daysDiff == currentStreak ||
            (daysDiff == currentStreak + 1 && currentStreak == 0)) {
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
          longestStreak =
              tempStreak > longestStreak ? tempStreak : longestStreak;
        } else {
          tempStreak = 1;
        }
      }
    }

    // Award points based on session duration (1 point per minute, capped at 60)
    final pointsEarned = sessionDuration < 60 ? sessionDuration : 60;
    final updatedPoints = _currentProgress.totalPoints + pointsEarned;

    // Check for first session achievement
    List<Achievement> updatedAchievements =
        List.from(_currentProgress.achievements);
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
    _progressChangedController.value = _currentProgress;
  }

  // Sync session data from repository (call this after session completion)
  @override
  Future<void> syncSessionData() async {
    await _loadRealSessionData();
  }

  @override
  Future<void> syncMoodEntries({bool force = false}) async {
    if (_isMoodSyncInProgress) {
      return;
    }

    if (!force && !FeatureFlags.isMoodPersistenceEnabled) {
      debugPrint(
          '[ProgressService] syncMoodEntries skipped: feature flag disabled');
      return;
    }

    if (!force) {
      final connectivity = ConnectivityChecker();
      final offline = await connectivity.isOffline();
      if (offline) {
        debugPrint('[ProgressService] syncMoodEntries skipped: offline');
        return;
      }
    }

    final apiClient = _getApiClientOrNull();
    if (apiClient == null) {
      debugPrint(
          '[ProgressService] syncMoodEntries skipped: API client unavailable');
      return;
    }

    _isMoodSyncInProgress = true;
    try {
      await _ensureMoodCacheLoaded();

      final pendingEntries = await getPendingMoodEntries();
      var syncFailed = false;

      if (pendingEntries.isNotEmpty) {
        for (final batch in _chunkMoodEntries(pendingEntries, 20)) {
          try {
            await _pushMoodEntries(apiClient, batch);
          } catch (e, stackTrace) {
            debugPrint('Error syncing mood batch: $e');
            if (kDebugMode) {
              debugPrint('$stackTrace');
            }
            await _markEntriesSyncError(batch, 'NETWORK');
            syncFailed = true;
            break;
          }
        }
      }

      if (!syncFailed) {
        try {
          await _pullMoodEntries(apiClient);
        } catch (e, stackTrace) {
          debugPrint('Error pulling mood entries: $e');
          if (kDebugMode) {
            debugPrint('$stackTrace');
          }
        }
      }

      await _loadMoodEntriesFromDatabase();
      _moodLogLimitReached = _entriesForDay(DateTime.now()).length >= 3;
      _hasPendingMoodSyncError =
          _moodEntries.any((entry) => entry.syncError?.isNotEmpty ?? false);
      await _saveProgress();
    } finally {
      _isMoodSyncInProgress = false;
    }
  }

  @override
  Future<List<MoodEntryRecord>> getPendingMoodEntries() async {
    await _ensureMoodCacheLoaded();
    return _moodEntries
        .where((entry) =>
            entry.isPending || (entry.syncError?.isNotEmpty ?? false))
        .toList(growable: false);
  }

  @override
  Future<void> clearMoodSyncErrors() async {
    await _ensureMoodCacheLoaded();
    final userId = await _resolveUserId();

    await _databaseProvider.update(
      _moodEntriesTable,
      {'sync_error': null},
      where: 'user_id = ? AND sync_error IS NOT NULL',
      whereArgs: [userId],
    );

    final cleanedEntries = _moodEntries
        .map((entry) =>
            entry.syncError != null ? entry.copyWith(syncError: null) : entry)
        .toList(growable: false);

    await _replaceMoodEntries(cleanedEntries, persist: false);
  }

  @override
  bool consumeLastMoodLogWasLocalOnly() {
    final result = _lastMoodLogWasLocalOnly;
    _lastMoodLogWasLocalOnly = false;
    return result;
  }

  @override
  bool consumePendingMoodSyncError() {
    final result = _hasPendingMoodSyncError;
    _hasPendingMoodSyncError = false;
    return result;
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
        .where((entry) =>
            !entry.key.isBefore(startDate) && !entry.key.isAfter(endDate))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  int getTotalMoodEntriesCount() {
    return _moodEntries.length;
  }

  // Get session data for visualization
  @override
  List<MapEntry<DateTime, int>> getSessionDataForLastDays(int days) {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));

    return _currentProgress.sessionHistory.entries
        .where((entry) =>
            entry.key.isAfter(startDate) && entry.key.isBefore(endDate))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  // Reset all progress data
  @override
  Future<void> resetProgress() async {
    _currentProgress = UserProgress();
    final userId = await _resolveUserId();
    await _databaseProvider.delete(
      _moodEntriesTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    _moodEntries.clear();
    _moodHistory.clear();
    _moodLogLimitReached = false;
    _isMoodCacheLoaded = false;
    _moodCacheLoadFuture = null;
    _lastMoodSyncAt = null;
    _moodSyncDebounceTimer?.cancel();
    _moodSyncDebounceTimer = null;
    _dailyPurgeTimer?.cancel();
    _dailyPurgeTimer = null;
    _lastMoodLogWasLocalOnly = false;
    _hasPendingMoodSyncError = false;
    await _saveProgress();
    _progressChangedController.value = _currentProgress;
  }
}
