/// MessageCoordinator - Phase 1.1.3
///
/// Manages message processing, sequencing, and conversation history for VoiceSessionBloc.
/// This manager handles all message-related functionality including adding messages,
/// maintaining conversation history, and generating appropriate responses.
///
/// Responsibilities:
/// - Message sequencing and ordering
/// - Conversation history management
/// - Welcome message generation
/// - Message state updates
/// - History building for AI context
///
/// Thread Safety: Async operations return to main thread
/// Dependencies: None (pure Dart)

import 'package:flutter/foundation.dart';
import '../../models/therapy_message.dart';
import '../../widgets/mood_selector.dart';
import 'package:uuid/uuid.dart';

/// Manages message processing and conversation history
class MessageCoordinator {
  /// Current list of messages
  List<TherapyMessage> _messages = [];

  /// Current message sequence number
  int _currentSequence = 0;

  /// Track last welcome message used per mood to avoid repetition
  final Map<Mood, String> _lastWelcomeMessageByMood = {};

  /// UUID generator for message IDs
  final _uuid = const Uuid();

  /// Get current messages (immutable copy)
  List<TherapyMessage> get messages => List.unmodifiable(_messages);

  /// Get current sequence number
  int get currentSequence => _currentSequence;

  /// Get message count
  int get messageCount => _messages.length;

  /// Check if conversation has messages
  bool get hasMessages => _messages.isNotEmpty;

  /// Initialize or reset messages
  void resetMessages() {
    if (kDebugMode) {
      debugPrint('[MessageCoordinator] Resetting messages and sequence');
    }
    _messages = [];
    _currentSequence = 0;
  }

  /// Add a user message with auto-sequencing
  TherapyMessage addUserMessage(String content) {
    if (kDebugMode) {
      debugPrint(
          '[MessageCoordinator] Adding user message: "${content.substring(0, content.length.clamp(0, 50))}..."');
    }

    _currentSequence++;

    final message = TherapyMessage(
      id: _uuid.v4(),
      content: content,
      isUser: true,
      timestamp: DateTime.now(),
      sequence: _currentSequence,
    );

    _messages.add(message);
    return message;
  }

  /// Add an AI message with auto-sequencing
  TherapyMessage addAIMessage(String content) {
    if (kDebugMode) {
      debugPrint(
          '[MessageCoordinator] Adding AI message: "${content.substring(0, content.length.clamp(0, 50))}..."');
    }

    _currentSequence++;

    final message = TherapyMessage(
      id: _uuid.v4(),
      content: content,
      isUser: false,
      timestamp: DateTime.now(),
      sequence: _currentSequence,
    );

    _messages.add(message);
    return message;
  }

  /// Add a pre-built message with sequence override
  TherapyMessage addMessage(TherapyMessage message) {
    if (kDebugMode) {
      debugPrint(
          '[MessageCoordinator] Adding pre-built message with sequence: ${message.sequence}');
    }

    // Update sequence if not provided or if we need to maintain order
    if (message.sequence == 0) {
      _currentSequence++;
      message = message.copyWith(sequence: _currentSequence);
    } else if (message.sequence > _currentSequence) {
      _currentSequence = message.sequence;
    }

    _messages.add(message);
    return message;
  }

  /// Generate and add welcome message based on mood
  TherapyMessage addWelcomeMessage(Mood mood) {
    final welcomeText = generateWelcomeMessage(mood);

    if (kDebugMode) {
      debugPrint('[MessageCoordinator] Adding welcome message for mood: $mood');
    }

    return addAIMessage(welcomeText);
  }

  /// Generate welcome message text based on mood
  String generateWelcomeMessage(Mood mood) {
    final messages = _getWelcomeMessagesForMood(mood);

    // Use timestamp-based selection for variety
    int index = DateTime.now().millisecond % messages.length;
    String selected = messages[index];

    final lastMessage = _lastWelcomeMessageByMood[mood];
    if (messages.length > 1 && selected == lastMessage) {
      index = (index + 1) % messages.length;
      selected = messages[index];
    }

    _lastWelcomeMessageByMood[mood] = selected;
    return selected;
  }

  /// Get welcome messages for specific mood
  List<String> _getWelcomeMessagesForMood(Mood mood) {
    switch (mood) {
      case Mood.happy:
        return [
          "Heyyy! What's keeping your spirits high today?",
          "Hello hello! Your positivity is contagious! What's on your mind?",
          "Hey there! Glad you're feeling upbeat! How can I support you today?",
          "Heyyy! Hearing you're happy makes me happy! Anything special you'd like to talk about?",
          "Hello hello! Would you like to share more about what's brightening your day?"
        ];

      case Mood.sad:
        return [
          "I'm here for you. What's been weighing on your heart lately?",
          "Thank you for trusting me with your feelings. How can I support you today?",
          "I hear you're going through a tough time. Would you like to share what's on your mind?",
          "It takes courage to reach out when you're feeling down. I'm glad you're here.",
          "I'm here to listen. What's been making you feel this way?"
        ];

      case Mood.anxious:
        return [
          "I understand you're feeling anxious. Let's take this one step at a time. What's on your mind?",
          "Anxiety can feel overwhelming. I'm here to help you work through it. What's been triggering these feelings?",
          "Thank you for reaching out. Anxiety is tough, but you're not alone. What would you like to talk about?",
          "I can sense you're feeling anxious. Let's explore what's been causing these feelings together.",
          "It's okay to feel anxious. I'm here to support you. What's been on your mind lately?"
        ];

      case Mood.angry:
        return [
          "I can feel the intensity of your emotions. What's been frustrating you?",
          "Anger often signals that something important to you has been affected. What's going on?",
          "Thank you for being honest about your anger. What's been triggering these feelings?",
          "I'm here to listen without judgment. What's been making you feel this way?",
          "Anger can be a powerful emotion. Let's explore what's behind it together."
        ];

      case Mood.neutral:
        return [
          "Hello! I'm here to listen. What's been on your mind lately?",
          "Thanks for reaching out today. What would you like to talk about?",
          "I'm glad you're here. What's been going on in your life?",
          "How are you feeling today? What would you like to explore together?",
          "I'm here to support you. What's been on your mind?"
        ];

      case Mood.stressed:
        return [
          "I can sense you're feeling stressed. Let's work through this together. What's been weighing on you?",
          "Stress can feel overwhelming. I'm here to help you find some relief. What's been the biggest challenge?",
          "Thank you for sharing that you're stressed. What's been contributing to these feelings?",
          "I understand stress can be exhausting. Let's take this one step at a time. What's been most difficult?",
          "It takes strength to recognize when you're stressed. What would help you feel more balanced?"
        ];
    }
  }

  /// Build conversation history for AI context
  List<Map<String, String>> buildConversationHistory() {
    return _messages
        .map((message) => {
              'role': message.isUser ? 'user' : 'assistant',
              'content': message.content,
            })
        .toList();
  }

  /// Get messages for a specific time range
  List<TherapyMessage> getMessagesInRange(DateTime start, DateTime end) {
    return _messages
        .where((message) =>
            message.timestamp.isAfter(start) && message.timestamp.isBefore(end))
        .toList();
  }

  /// Get last N messages
  List<TherapyMessage> getLastMessages(int count) {
    if (_messages.length <= count) {
      return List.from(_messages);
    }
    return _messages.sublist(_messages.length - count);
  }

  /// Get messages by user type
  List<TherapyMessage> getUserMessages() {
    return _messages.where((message) => message.isUser).toList();
  }

  List<TherapyMessage> getAIMessages() {
    return _messages.where((message) => !message.isUser).toList();
  }

  /// Update messages list (for state restoration)
  void updateMessages(List<TherapyMessage> messages, int sequence) {
    if (kDebugMode) {
      debugPrint(
          '[MessageCoordinator] Updating messages list with ${messages.length} messages, sequence: $sequence');
    }
    _messages = List.from(messages);
    _currentSequence = sequence;
  }

  /// Get conversation summary
  Map<String, dynamic> getConversationSummary() {
    return {
      'totalMessages': _messages.length,
      'userMessages': getUserMessages().length,
      'aiMessages': getAIMessages().length,
      'currentSequence': _currentSequence,
      'hasMessages': hasMessages,
      'conversationDuration': hasMessages
          ? _messages.last.timestamp
              .difference(_messages.first.timestamp)
              .inMinutes
          : 0,
    };
  }

  /// Find message by ID
  TherapyMessage? findMessageById(String id) {
    try {
      return _messages.firstWhere((message) => message.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Remove message by ID (for error recovery)
  bool removeMessage(String id) {
    final initialLength = _messages.length;
    _messages.removeWhere((message) => message.id == id);

    if (_messages.length < initialLength) {
      if (kDebugMode) {
        debugPrint('[MessageCoordinator] Removed message with ID: $id');
      }
      return true;
    }
    return false;
  }
}
