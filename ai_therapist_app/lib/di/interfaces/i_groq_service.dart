// lib/di/interfaces/i_groq_service.dart
abstract class IGroqService {
  bool get isConfigured;
  String get llmModelId;
  String? get conversationMemory;
  String? get sessionId;
  set sessionId(String? value);
  Future<void> init();
  void resetConversationMemory();
  void setAvailable(bool available);
  Future<String> generateChatCompletion({
    required String userMessage,
    String systemPrompt = '',
    String? model,
    double temperature = 0.7,
    int maxTokens = 1000,
  });
  Future<Map<String, dynamic>> testConnection();
  Stream<Map<String, dynamic>> streamChatCompletionViaWebSocket({
    required String message,
    List<Map<String, dynamic>> history = const [],
    String? sessionId,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    Duration inactivityTimeout = const Duration(seconds: 30),
  });
}
