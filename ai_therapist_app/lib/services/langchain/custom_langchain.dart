// A simple implementation of conversation memory for LLM context
class ConversationBufferMemory {
  // Store conversation history
  final List<Map<String, String>> _messages = [];

  // Maximum number of messages to store
  final int maxMessages;

  // Constructor with default limit
  ConversationBufferMemory({this.maxMessages = 20});

  // Add a user message
  void addUserMessage(String message) {
    _messages.add({
      'role': 'user',
      'content': message,
    });
    _trimHistory();
  }

  // Add an AI message
  void addAIMessage(String message) {
    _messages.add({
      'role': 'assistant',
      'content': message,
    });
    _trimHistory();
  }

  // Trim history to max length
  void _trimHistory() {
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }

  // Get messages for LLM context
  List<Map<String, String>> getMessages() {
    return List.from(_messages);
  }

  // Get formatted buffer as string
  String getBuffer() {
    StringBuffer buffer = StringBuffer();
    for (var message in _messages) {
      buffer.writeln('${message['role']}: ${message['content']}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  // Clear conversation history
  void clear() {
    _messages.clear();
  }
}
