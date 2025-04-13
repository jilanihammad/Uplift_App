// lib/services/notification_service.dart
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// A simulated notification service that logs notifications instead of showing them
/// This is a temporary implementation until we resolve the flutter_local_notifications compatibility issue
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  // Store scheduled notifications for simulation
  final List<Map<String, dynamic>> _scheduledNotifications = [];

  Future<void> init() async {
    // Initialize timezone data
    tz_data.initializeTimeZones();
    
    debugPrint('🔔 NotificationService initialized (simulated)');
  }

  // Show immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Log instead of showing
    debugPrint('🔔 NOTIFICATION: ID=$id, TITLE=$title, BODY=$body, PAYLOAD=$payload');
  }

  // Schedule notification for future time
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    // Don't schedule if time is in the past
    if (scheduledTime.isBefore(DateTime.now())) {
      debugPrint('⚠️ Cannot schedule notification in the past: $scheduledTime');
      return;
    }

    // Store in our simulated list
    _scheduledNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'scheduledTime': scheduledTime,
      'payload': payload,
    });

    debugPrint('🔔 SCHEDULED: ID=$id, TITLE=$title, TIME=${scheduledTime.toIso8601String()}');
  }
  
  // Schedule a daily repeating notification at specific time
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    // Calculate next occurrence
    final now = DateTime.now();
    final scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    
    // If time has passed for today, schedule for tomorrow
    final actualScheduleTime = scheduledTime.isBefore(now)
        ? scheduledTime.add(const Duration(days: 1))
        : scheduledTime;
    
    // Store with repeat info
    _scheduledNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'scheduledTime': actualScheduleTime,
      'payload': payload,
      'repeats': 'daily',
      'hour': hour,
      'minute': minute,
    });

    debugPrint('🔔 SCHEDULED DAILY: ID=$id, TITLE=$title, TIME=$hour:$minute');
  }

  // Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    _scheduledNotifications.removeWhere((notification) => notification['id'] == id);
    debugPrint('🔔 Cancelled notification with ID=$id');
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    _scheduledNotifications.clear();
    debugPrint('🔔 Cancelled all notifications');
  }

  // Get all scheduled notifications (for UI display)
  List<Map<String, dynamic>> getScheduledNotifications() {
    return List.from(_scheduledNotifications);
  }
}