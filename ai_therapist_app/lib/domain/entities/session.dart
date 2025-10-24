// lib/domain/entities/session.dart
import 'dart:convert';

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
    // Parse action items from JSON - handle both string and list formats
    List<String> actionItems = [];
    if (json['action_items'] != null) {
      if (json['action_items'] is String) {
        // If stored as JSON string, try to parse it or use as single item
        final actionItemsStr = json['action_items'] as String;
        if (actionItemsStr.isNotEmpty) {
          if (actionItemsStr.startsWith('[')) {
            // Try to parse as JSON array
            try {
              final decoded = jsonDecode(actionItemsStr) as List<dynamic>;
              actionItems = decoded.map((item) => item.toString()).toList();
            } catch (e) {
              // If parsing fails, treat as single item
              actionItems = [actionItemsStr];
            }
          } else {
            // Treat as single item
            actionItems = [actionItemsStr];
          }
        }
      } else if (json['action_items'] is List) {
        // If already a list, convert to List<String>
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
      createdAt: DateTime.parse(json['created_at']).toUtc(),
      lastModified: DateTime.parse(json['last_modified']).toUtc(),
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
