// lib/di/interfaces/i_session_schedule_service.dart

import '../../models/session_reminder.dart';

/// Contract for managing scheduled therapy sessions and reminders.
abstract class ISessionScheduleService {
  /// Most recently loaded reminder (may be null if nothing scheduled).
  SessionReminder? get currentReminder;

  /// Fetch the latest reminder from the backend, falling back to local cache
  /// if the network call fails. When [forceRefresh] is false and a reminder is
  /// already cached, the cached value is returned immediately.
  Future<SessionReminder?> loadReminder({bool forceRefresh = false});

  /// Update or create the next scheduled session in the backend. The returned
  /// object represents the persisted reminder (or a local fallback if the
  /// backend call failed).
  Future<SessionReminder?> scheduleSession(
    DateTime scheduledTime, {
    String? title,
    String? description,
  });

  /// Remove any cached reminder data, both in memory and local storage.
  Future<void> clearReminder();
}
