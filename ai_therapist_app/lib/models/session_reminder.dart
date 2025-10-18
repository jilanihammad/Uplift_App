// lib/models/session_reminder.dart

import 'package:flutter/foundation.dart';

/// Source of the reminder data, used to track whether it came from
/// the backend or a local fallback.
enum SessionReminderSource { backend, local }

/// Model representing a scheduled therapy session reminder.
@immutable
class SessionReminder {
  final String? id;
  final DateTime? scheduledTime;
  final String? title;
  final String? description;
  final bool isCompleted;
  final SessionReminderSource source;

  const SessionReminder({
    this.id,
    this.scheduledTime,
    this.title,
    this.description,
    this.isCompleted = false,
    this.source = SessionReminderSource.backend,
  });

  SessionReminder copyWith({
    String? id,
    DateTime? scheduledTime,
    String? title,
    String? description,
    bool? isCompleted,
    SessionReminderSource? source,
  }) {
    return SessionReminder(
      id: id ?? this.id,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      source: source ?? this.source,
    );
  }

  factory SessionReminder.fromJson(Map<String, dynamic> json,
      {SessionReminderSource source = SessionReminderSource.backend}) {
    DateTime? scheduledTime;
    final dynamic rawScheduled = json['scheduled_time'];
    if (rawScheduled is String && rawScheduled.isNotEmpty) {
      try {
        scheduledTime = DateTime.parse(rawScheduled).toLocal();
      } catch (_) {
        scheduledTime = null;
      }
    }

    return SessionReminder(
      id: json['id']?.toString(),
      scheduledTime: scheduledTime,
      title: json['title'] as String?,
      description: json['description'] as String?,
      isCompleted: (json['is_completed'] as bool?) ?? false,
      source: source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scheduled_time': scheduledTime?.toUtc().toIso8601String(),
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'source': describeEnum(source),
    };
  }
}
