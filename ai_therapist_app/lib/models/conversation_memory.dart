// lib/models/conversation_memory.dart
import 'dart:convert';

/// Represents a single memory in a conversation between the user and the AI.
class ConversationMemory {
  /// The user's message that initiated this interaction.
  final String userMessage;

  /// The AI's response to the user's message.
  final String aiResponse;

  /// Metadata associated with this memory, such as detected emotions,
  /// conversation state, etc.
  final Map<String, dynamic> metadata;

  /// Timestamp when this memory was created.
  final DateTime timestamp;

  /// Constructor for creating a conversation memory.
  ConversationMemory({
    required this.userMessage,
    required this.aiResponse,
    this.metadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': timestamp.millisecondsSinceEpoch.toString(),
      'user_message': userMessage,
      'ai_response': aiResponse,
      'metadata': json.encode(metadata),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create a JSON string representation.
  String toJsonString() {
    return json.encode(toJson());
  }

  /// Create a ConversationMemory from a JSON map.
  factory ConversationMemory.fromJson(Map<String, dynamic> json) {
    var metadataMap = <String, dynamic>{};

    // Handle metadata that might be a string or a map
    if (json['metadata'] != null) {
      if (json['metadata'] is String) {
        try {
          metadataMap = jsonDecode(json['metadata'] as String);
        } catch (e) {
          // If decode fails, use empty map
          metadataMap = {};
        }
      } else if (json['metadata'] is Map) {
        metadataMap = Map<String, dynamic>.from(json['metadata'] as Map);
      }
    }

    return ConversationMemory(
      userMessage:
          json['user_message'] as String? ?? json['userMessage'] as String,
      aiResponse:
          json['ai_response'] as String? ?? json['aiResponse'] as String,
      metadata: metadataMap,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Create a ConversationMemory from a JSON string.
  factory ConversationMemory.fromJsonString(String jsonString) {
    return ConversationMemory.fromJson(
        json.decode(jsonString) as Map<String, dynamic>);
  }
}

/// Represents an insight gained during a therapy session.
class TherapyInsight {
  /// The text content of the insight.
  final String insight;

  /// Source of the insight (session summary, AI detection, user statement).
  final String source;

  /// Timestamp when this insight was recorded.
  final DateTime timestamp;

  /// Constructor for creating a therapy insight.
  TherapyInsight({
    required this.insight,
    required this.source,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'insight': insight,
      'source': source,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create a TherapyInsight from a JSON map.
  factory TherapyInsight.fromJson(Map<String, dynamic> json) {
    return TherapyInsight(
      insight: json['insight'] as String,
      source: json['source'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Represents an emotional state of the user at a particular point in time.
class EmotionalState {
  /// The emotion label (sad, happy, anxious, etc.).
  final String emotion;

  /// Intensity of the emotion on a scale from 0.0 to 10.0.
  final double intensity;

  /// What triggered this emotional state (optional).
  final String? trigger;

  /// Timestamp when this state was recorded.
  final DateTime timestamp;

  /// Constructor for creating an emotional state.
  EmotionalState({
    required this.emotion,
    required this.intensity,
    this.trigger,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'emotion': emotion,
      'intensity': intensity,
      'trigger': trigger,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create an EmotionalState from a JSON map.
  factory EmotionalState.fromJson(Map<String, dynamic> json) {
    return EmotionalState(
      emotion: json['emotion'] as String,
      intensity: json['intensity'] as double,
      trigger: json['trigger'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Represents a key personal anchor remembered about the user.
class UserAnchor {
  final int? id;
  final String anchorText;
  final String normalizedText;
  final String? anchorType;
  final double confidence;
  final int mentionCount;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int firstSessionIndex;
  final int lastSessionIndex;
  final int lastPromptedSession;
  final String? serverId;
  final String clientAnchorId;
  final DateTime updatedAt;
  final bool isDeleted;

  UserAnchor({
    this.id,
    required this.anchorText,
    required this.normalizedText,
    this.anchorType,
    this.confidence = 0.0,
    this.mentionCount = 1,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    this.firstSessionIndex = 0,
    this.lastSessionIndex = 0,
    this.lastPromptedSession = -1,
    this.serverId,
    String? clientAnchorId,
    DateTime? updatedAt,
    this.isDeleted = false,
  })  : firstSeenAt = firstSeenAt ?? DateTime.now(),
        lastSeenAt = lastSeenAt ?? DateTime.now(),
        clientAnchorId = clientAnchorId ?? normalizedText,
        updatedAt = updatedAt ?? DateTime.now();

  UserAnchor copyWith({
    int? id,
    String? anchorText,
    String? normalizedText,
    String? anchorType,
    double? confidence,
    int? mentionCount,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    int? firstSessionIndex,
    int? lastSessionIndex,
    int? lastPromptedSession,
    String? serverId,
    String? clientAnchorId,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return UserAnchor(
      id: id ?? this.id,
      anchorText: anchorText ?? this.anchorText,
      normalizedText: normalizedText ?? this.normalizedText,
      anchorType: anchorType ?? this.anchorType,
      confidence: confidence ?? this.confidence,
      mentionCount: mentionCount ?? this.mentionCount,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      firstSessionIndex: firstSessionIndex ?? this.firstSessionIndex,
      lastSessionIndex: lastSessionIndex ?? this.lastSessionIndex,
      lastPromptedSession: lastPromptedSession ?? this.lastPromptedSession,
      serverId: serverId ?? this.serverId,
      clientAnchorId: clientAnchorId ?? this.clientAnchorId,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'anchor_text': anchorText,
      'normalized_text': normalizedText,
      'anchor_type': anchorType,
      'confidence': confidence,
      'mention_count': mentionCount,
      'first_seen_at': firstSeenAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
      'first_session_index': firstSessionIndex,
      'last_session_index': lastSessionIndex,
      'last_prompted_session': lastPromptedSession,
      'server_id': serverId,
      'client_anchor_id': clientAnchorId,
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };

    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  factory UserAnchor.fromJson(Map<String, dynamic> json) {
    return UserAnchor(
      id: json['id'] as int?,
      anchorText: json['anchor_text'] as String,
      normalizedText: json['normalized_text'] as String,
      anchorType: json['anchor_type'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      mentionCount: json['mention_count'] as int? ?? 1,
      firstSeenAt: DateTime.parse(json['first_seen_at'] as String),
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      firstSessionIndex: json['first_session_index'] as int? ?? 0,
      lastSessionIndex: json['last_session_index'] as int? ?? 0,
      lastPromptedSession: json['last_prompted_session'] as int? ?? -1,
      serverId: json['server_id'] as String?,
      clientAnchorId: json['client_anchor_id'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.parse(json['last_seen_at'] as String),
      isDeleted: (json['is_deleted'] as int? ?? 0) == 1,
    );
  }

  static String normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
