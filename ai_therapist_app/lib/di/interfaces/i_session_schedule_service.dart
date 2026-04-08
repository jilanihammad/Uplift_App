// lib/di/interfaces/i_session_schedule_service.dart
import '../../models/session_reminder.dart';
abstract class ISessionScheduleService {
  SessionReminder? get currentReminder;
  Future<SessionReminder?> loadReminder({bool forceRefresh = false});
  Future<SessionReminder?> scheduleSession(
    DateTime scheduledTime, {
    String? title,
    String? description,
  });
  Future<void> clearReminder();
}
