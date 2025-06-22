// lib/di/interfaces/i_groq_service.dart

/// Interface for Groq LLM service operations
/// Provides contract for text generation using Groq API
abstract class IGroqService {
  // Service state
  bool get isConfigured;
  String get llmModelId;
  String? get conversationMemory;
  String? get sessionId;
  set sessionId(String? value);
  
  // Initialization
  Future<void> init();
  
  // Memory management
  void resetConversationMemory();
  
  // Configuration
  void setAvailable(bool available);
  
  // Text generation
  Future<String> generateChatCompletion({
    required String userMessage,
    String systemPrompt = '',
    String? model,
    double temperature = 0.7,
    int maxTokens = 1000,
  });
  
  // Connection testing
  Future<Map<String, dynamic>> testConnection();
  
  // Streaming chat
  Stream<Map<String, dynamic>> streamChatCompletionViaWebSocket({
    required String message,
    List<Map<String, dynamic>> history = const [],
    String? sessionId,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    Duration inactivityTimeout = const Duration(seconds: 30),
  });
}