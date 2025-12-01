// Model class for chat messages in therapy sessions
import 'package:ai_therapist_app/utils/date_time_utils.dart';

class TherapyMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? audioUrl;
  final int sequence;

  TherapyMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.audioUrl,
    required this.sequence,
  });

  // Create a copy of this message with modified fields
  TherapyMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    String? audioUrl,
    int? sequence,
  }) {
    return TherapyMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      audioUrl: audioUrl ?? this.audioUrl,
      sequence: sequence ?? this.sequence,
    );
  }

  // Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'audioUrl': audioUrl,
      'sequence': sequence,
    };
  }

  // Deserialize from JSON
  factory TherapyMessage.fromJson(Map<String, dynamic> json) {
    return TherapyMessage(
      id: json['id'],
      content: json['content'],
      isUser: json['isUser'],
      timestamp: parseBackendDateTime(json['timestamp'] as String),
      audioUrl: json['audioUrl'],
      sequence: json['sequence'],
    );
  }
}
