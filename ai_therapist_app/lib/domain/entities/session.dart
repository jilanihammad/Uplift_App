// lib/domain/entities/session.dart
class Session {
  final String id;
  final String title;
  final String summary;
  final DateTime createdAt;
  final DateTime lastModified;
  final bool isSynced;
  
  Session({
    required this.id,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.lastModified,
    this.isSynced = true,
  });
  
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'],
      title: json['title'],
      summary: json['summary'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      lastModified: DateTime.parse(json['last_modified']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'created_at': createdAt.toIso8601String(),
      'last_modified': lastModified.toIso8601String(),
    };
  }
}