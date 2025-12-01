import 'package:uuid/uuid.dart';
import 'package:ai_therapist_app/utils/date_time_utils.dart';

class MoodEntryRecord {
  MoodEntryRecord({
    required this.id,
    required this.userId,
    required this.clientEntryId,
    required this.mood,
    required this.loggedAt,
    required this.updatedAt,
    this.notes,
    this.serverId,
    this.isPending = true,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String userId;
  final String clientEntryId;
  final int mood;
  final String? notes;
  final DateTime loggedAt;
  final String? serverId;
  final DateTime updatedAt;
  final bool isPending;
  final DateTime? lastSyncedAt;
  final String? syncError;

  static const _uuid = Uuid();

  factory MoodEntryRecord.newLocal({
    required String userId,
    required int mood,
    required DateTime loggedAt,
    String? notes,
  }) {
    final now = DateTime.now().toUtc();
    return MoodEntryRecord(
      id: _uuid.v4(),
      userId: userId,
      clientEntryId: _uuid.v4(),
      mood: mood,
      notes: notes,
      loggedAt: loggedAt.toUtc(),
      updatedAt: now,
      isPending: true,
    );
  }

  MoodEntryRecord copyWith({
    String? id,
    String? userId,
    String? clientEntryId,
    int? mood,
    String? notes,
    DateTime? loggedAt,
    String? serverId,
    DateTime? updatedAt,
    bool? isPending,
    DateTime? lastSyncedAt,
    String? syncError,
  }) {
    return MoodEntryRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      clientEntryId: clientEntryId ?? this.clientEntryId,
      mood: mood ?? this.mood,
      notes: notes ?? this.notes,
      loggedAt: loggedAt ?? this.loggedAt,
      serverId: serverId ?? this.serverId,
      updatedAt: updatedAt ?? this.updatedAt,
      isPending: isPending ?? this.isPending,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: syncError ?? this.syncError,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'client_entry_id': clientEntryId,
      'mood': mood,
      'notes': notes,
      'logged_at': loggedAt.toUtc().toIso8601String(),
      'server_id': serverId,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'is_pending': isPending ? 1 : 0,
      'last_synced_at': lastSyncedAt?.toUtc().toIso8601String(),
      'sync_error': syncError,
    };
  }

  factory MoodEntryRecord.fromMap(Map<String, Object?> map) {
    DateTime parseDate(Object? value) {
      if (value == null) {
        return DateTime.now().toUtc();
      }
      if (value is DateTime) {
        return value.toUtc();
      }
      return parseBackendDateTime(value.toString()).toUtc();
    }

    DateTime? parseNullableDate(Object? value) {
      if (value == null) return null;
      if (value is DateTime) return value.toUtc();
      return parseBackendDateTime(value.toString()).toUtc();
    }

    return MoodEntryRecord(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      clientEntryId: map['client_entry_id'] as String,
      mood: (map['mood'] as num).toInt(),
      notes: map['notes'] as String?,
      loggedAt: parseDate(map['logged_at']),
      serverId: map['server_id'] as String?,
      updatedAt: parseDate(map['updated_at']),
      isPending: (map['is_pending'] as num? ?? 0) != 0,
      lastSyncedAt: parseNullableDate(map['last_synced_at']),
      syncError: map['sync_error'] as String?,
    );
  }
}
