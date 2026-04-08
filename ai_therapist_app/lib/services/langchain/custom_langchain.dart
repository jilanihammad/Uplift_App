// A simple implementation of conversation memory for LLM context
class ConversationBufferMemory {
  // Store conversation history
  final List<Map<String, String>> _messages = [];
  final int maxMessages;
  ConversationBufferMemory({this.maxMessages = 20});
  void addUserMessage(String message) {
    _messages.add({
      'role': 'user',
      'content': message,
    });
    _trimHistory();
  }
  void addAIMessage(String message) {
    _messages.add({
      'role': 'assistant',
      'content': message,
    });
    _trimHistory();
  }
  void _trimHistory() {
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }
  List<Map<String, String>> getMessages() {
    return List.from(_messages);
  }
  String getBuffer() {
    StringBuffer buffer = StringBuffer();
    for (var message in _messages) {
      buffer.writeln('${message['role']}: ${message['content']}');
      buffer.writeln();
    }
    return buffer.toString();
  }
  void clear() {
    _messages.clear();
  }
}
