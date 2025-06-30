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
      id: json['id'].toString(),
      title: json['title'],
      summary: json['summary'] ?? '',
      createdAt: DateTime.parse(json['created_at']).toUtc(),
      lastModified: DateTime.parse(json['last_modified']).toUtc(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'created_at': createdAt.toUtc().toIso8601String(),
      'last_modified': lastModified.toUtc().toIso8601String(),
    };
  }
}