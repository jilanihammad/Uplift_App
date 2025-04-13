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
      'userMessage': userMessage,
      'aiResponse': aiResponse,
      'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  /// Create a JSON string representation.
  String toJsonString() {
    return json.encode(toJson());
  }
  
  /// Create a ConversationMemory from a JSON map.
  factory ConversationMemory.fromJson(Map<String, dynamic> json) {
    return ConversationMemory(
      userMessage: json['userMessage'] as String,
      aiResponse: json['aiResponse'] as String,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
  
  /// Create a ConversationMemory from a JSON string.
  factory ConversationMemory.fromJsonString(String jsonString) {
    return ConversationMemory.fromJson(json.decode(jsonString) as Map<String, dynamic>);
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