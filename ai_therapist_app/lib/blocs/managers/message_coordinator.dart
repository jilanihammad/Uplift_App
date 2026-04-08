library;
import '../../models/therapy_message.dart';
import '../../widgets/mood_selector.dart';
import 'package:uuid/uuid.dart';
class MessageCoordinator {
  List<TherapyMessage> _messages = [];
  int _currentSequence = 0;
  final Map<Mood, String> _lastWelcomeMessageByMood = {};
  final _uuid = const Uuid();
  List<TherapyMessage> get messages => List.unmodifiable(_messages);
  int get currentSequence => _currentSequence;
  int get messageCount => _messages.length;
  bool get hasMessages => _messages.isNotEmpty;
  void resetMessages() {
    _messages = [];
    _currentSequence = 0;
  }
  TherapyMessage addUserMessage(String content) {
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
  TherapyMessage addAIMessage(String content) {
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
  TherapyMessage addMessage(TherapyMessage message) {
    if (message.sequence == 0) {
      _currentSequence++;
      message = message.copyWith(sequence: _currentSequence);
    } else if (message.sequence > _currentSequence) {
      _currentSequence = message.sequence;
    }
    _messages.add(message);
    return message;
  }
  TherapyMessage addWelcomeMessage(Mood mood) {
    final welcomeText = generateWelcomeMessage(mood);
    return addAIMessage(welcomeText);
  }
  String generateWelcomeMessage(Mood mood) {
    final messages = _getWelcomeMessagesForMood(mood);
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
  List<Map<String, String>> buildConversationHistory() {
    return _messages
        .map((message) => {
              'role': message.isUser ? 'user' : 'assistant',
              'content': message.content,
            })
        .toList();
  }
  List<TherapyMessage> getMessagesInRange(DateTime start, DateTime end) {
    return _messages
        .where((message) =>
            message.timestamp.isAfter(start) && message.timestamp.isBefore(end))
        .toList();
  }
  List<TherapyMessage> getLastMessages(int count) {
    if (_messages.length <= count) {
      return List.from(_messages);
    }
    return _messages.sublist(_messages.length - count);
  }
  List<TherapyMessage> getUserMessages() {
    return _messages.where((message) => message.isUser).toList();
  }
  List<TherapyMessage> getAIMessages() {
    return _messages.where((message) => !message.isUser).toList();
  }
  void updateMessages(List<TherapyMessage> messages, int sequence) {
    _messages = List.from(messages);
    _currentSequence = sequence;
  }
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
  TherapyMessage? findMessageById(String id) {
    try {
      return _messages.firstWhere((message) => message.id == id);
    } catch (e) {
      return null;
    }
  }
  bool removeMessage(String id) {
    final initialLength = _messages.length;
    _messages.removeWhere((message) => message.id == id);
    if (_messages.length < initialLength) {
      return true;
    }
    return false;
  }
}
