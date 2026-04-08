// lib/domain/entities/session.dart
import 'dart:convert';
import 'package:ai_therapist_app/utils/date_time_utils.dart';
class Session {
  final String id;
  final String title;
  final String summary;
  final List<String> actionItems;
  final DateTime createdAt;
  final DateTime lastModified;
  final bool isSynced;
  Session({
    required this.id,
    required this.title,
    required this.summary,
    this.actionItems = const [],
    required this.createdAt,
    required this.lastModified,
    this.isSynced = true,
  });
  factory Session.fromJson(Map<String, dynamic> json) {
    List<String> actionItems = [];
    if (json['action_items'] != null) {
      if (json['action_items'] is String) {
        final actionItemsStr = json['action_items'] as String;
        if (actionItemsStr.isNotEmpty) {
          if (actionItemsStr.startsWith('[')) {
            try {
              final decoded = jsonDecode(actionItemsStr) as List<dynamic>;
              actionItems = decoded.map((item) => item.toString()).toList();
            } catch (e) {
              actionItems = [actionItemsStr];
            }
          } else {
            actionItems = [actionItemsStr];
          }
        }
      } else if (json['action_items'] is List) {
        actionItems = (json['action_items'] as List<dynamic>)
            .map((item) => item.toString())
            .toList();
      }
    }
    return Session(
      id: json['id'].toString(),
      title: json['title'],
      summary: json['summary'] ?? '',
      actionItems: actionItems,
      createdAt:
          parseBackendDateTimeToUtc(json['created_at'] as String),
      lastModified:
          parseBackendDateTimeToUtc(json['last_modified'] as String),
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'action_items': actionItems,
      'created_at': createdAt.toUtc().toIso8601String(),
      'last_modified': lastModified.toUtc().toIso8601String(),
    };
  }
}
