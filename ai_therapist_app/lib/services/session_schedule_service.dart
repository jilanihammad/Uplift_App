// lib/services/session_schedule_service.dart

import 'package:flutter/foundation.dart';

import '../data/datasources/local/prefs_manager.dart';
import '../di/interfaces/i_api_client.dart';
import '../di/interfaces/i_session_schedule_service.dart';
import '../models/session_reminder.dart';
import 'package:ai_therapist_app/utils/date_time_utils.dart';

class SessionScheduleService implements ISessionScheduleService {
  static const String _prefsKeyNextSession = 'next_session_timestamp';
  static const String _defaultReminderTitle = 'Therapy Session Reminder';

  final IApiClient _apiClient;
  final PrefsManager _prefsManager;

  bool _prefsInitialized = false;
  SessionReminder? _currentReminder;

  SessionScheduleService({
    required IApiClient apiClient,
    PrefsManager? prefsManager,
  })  : _apiClient = apiClient,
        _prefsManager = prefsManager ?? PrefsManager();

  @override
  SessionReminder? get currentReminder => _currentReminder;

  Future<void> _ensurePrefsReady() async {
    if (_prefsInitialized) {
      return;
    }
    await _prefsManager.init();
    _prefsInitialized = true;
  }

  Future<void> _persistReminder(SessionReminder? reminder) async {
    _currentReminder = reminder;
    await _ensurePrefsReady();

    if (reminder?.scheduledTime != null) {
      await _prefsManager.setString(_prefsKeyNextSession,
          reminder!.scheduledTime!.toUtc().toIso8601String());
    } else {
      await _prefsManager.remove(_prefsKeyNextSession);
    }
  }

  Future<SessionReminder?> _loadFromPrefs() async {
    await _ensurePrefsReady();
    final stored = _prefsManager.getString(_prefsKeyNextSession);
    if (stored == null) {
      return null;
    }

    try {
      final timestamp = parseBackendDateTime(stored).toLocal();
      return SessionReminder(
        scheduledTime: timestamp,
        title: _currentReminder?.title ?? _defaultReminderTitle,
        description: _currentReminder?.description,
        source: SessionReminderSource.local,
      );
    } catch (e) {
      debugPrint(
          'SessionScheduleService: unable to parse stored next session timestamp: $e');
      await _prefsManager.remove(_prefsKeyNextSession);
      return null;
    }
  }

  bool _hasScheduledTime(Map<String, dynamic> json) {
    final dynamic raw = json['scheduled_time'];
    if (raw == null) {
      return false;
    }
    if (raw is String) {
      return raw.isNotEmpty;
    }
    return true;
  }

  @override
  Future<SessionReminder?> loadReminder({bool forceRefresh = false}) async {
    if (!forceRefresh && _currentReminder != null) {
      return _currentReminder;
    }

    try {
      final response = await _apiClient.get('/session-reminder');
      if (response.isEmpty || !_hasScheduledTime(response)) {
        await _persistReminder(null);
        return null;
      }

      final reminder = SessionReminder.fromJson(response);
      await _persistReminder(reminder);
      return reminder;
    } catch (e, stack) {
      debugPrint(
          'SessionScheduleService: failed to fetch reminder from backend: $e');
      debugPrint(stack.toString());

      final localReminder = await _loadFromPrefs();
      await _persistReminder(localReminder);
      return localReminder;
    }
  }

  @override
  Future<SessionReminder?> scheduleSession(
    DateTime scheduledTime, {
    String? title,
    String? description,
  }) async {
    final payload = <String, dynamic>{
      'scheduled_time': scheduledTime.toUtc().toIso8601String(),
    };
    if (title != null && title.isNotEmpty) {
      payload['title'] = title;
    }
    if (description != null && description.isNotEmpty) {
      payload['description'] = description;
    }

    try {
      final response = await _apiClient.put('/session-reminder', payload);
      final reminder = _hasScheduledTime(response)
          ? SessionReminder.fromJson(response)
          : SessionReminder(
              scheduledTime: scheduledTime,
              title: title ?? _defaultReminderTitle,
              description: description,
            );

      await _persistReminder(reminder);
      return reminder;
    } catch (e, stack) {
      debugPrint(
          'SessionScheduleService: failed to update reminder on backend: $e');
      debugPrint(stack.toString());

      final fallback = SessionReminder(
        scheduledTime: scheduledTime,
        title: title ?? _defaultReminderTitle,
        description: description,
        source: SessionReminderSource.local,
      );
      await _persistReminder(fallback);
      return fallback;
    }
  }

  @override
  Future<void> clearReminder() async {
    await _persistReminder(null);
  }
}
