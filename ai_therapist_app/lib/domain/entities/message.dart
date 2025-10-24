// lib/domain/entities/message.dart
class Message {
  final String id;
  final String sessionId;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isSynced;

  Message({
    required this.id,
    required this.sessionId,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isSynced = true,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      sessionId: json['session_id'],
      content: json['content'],
      isUser: json['is_user'] ?? false,
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'content': content,
      'is_user': isUser,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
