import 'package:flutter_test/flutter_test.dart';
import 'package:ai_therapist_app/services/groq_service.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/services/langchain/therapy_conversation_graph.dart';
import 'package:ai_therapist_app/services/langchain/prompt_templates.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'dart:convert';

// Simple manual mock of the GroqService for testing
class SimpleGroqServiceMock implements GroqService {
  bool _isAvailable = true;
  final List<Map<String, String>> _messages = [];
  
  @override
  Future<void> init() async {
    _isAvailable = true;
  }
  
  @override
  Future<String> generateChatCompletion({
    required String userMessage,
    String systemPrompt = '',
    String model = 'meta-llama/llama-4-scout-17b-16e-instruct',
    double temperature = 0.7,
    int maxTokens = 1000,
  }) async {
    // Store user message
    _messages.add({
      'role': 'user',
      'content': userMessage,
    });
    
    // Simple mock response based on the message
    String response = 'This is a test response from the mock GroqService.';
    
    if (userMessage.contains('help')) {
      response = 'I understand you need help. How can I assist you today?';
    } else if (userMessage.contains('anxious') || userMessage.contains('anxiety')) {
      response = 'I hear that you\'re feeling anxious. Let\'s explore that together.';
    } else if (userMessage.contains('sad') || userMessage.contains('depressed')) {
      response = 'I'm sorry to hear you're feeling sad. Would you like to talk more about what's going on?';
    }
    
    // Store AI response
    _messages.add({
      'role': 'assistant',
      'content': response,
    });
    
    return response;
  }
  
  @override
  Future<String> generateChatCompletionWithHistory({
    required List<Map<String, String>> messages,
    String model = 'meta-llama/llama-4-scout-17b-16e-instruct',
    double temperature = 0.7,
    int maxTokens = 1000,
  }) async {
    // Simple mock based on the last user message
    final lastUserMessage = messages.lastWhere((msg) => msg['role'] == 'user', orElse: () => {'content': ''})['content'] ?? '';
    return generateChatCompletion(userMessage: lastUserMessage);
  }
  
  @override
  void resetConversationMemory() {
    _messages.clear();
  }
  
  @override
  String? get conversationMemory {
    final buffer = StringBuffer();
    for (var message in _messages) {
      buffer.writeln('${message['role']}: ${message['content']}');
    }
    return buffer.toString();
  }
  
  @override
  bool get isConfigured => _isAvailable;
  
  @override
  void setAvailable(bool available) {
    _isAvailable = available;
  }
}

void main() {
  setUp(() {
    // Set up a simple service locator for tests
    if (!serviceLocator.isRegistered<ConfigService>()) {
      serviceLocator.registerSingleton<ConfigService>(ConfigService(
        llmApiEndpoint: 'https://test-endpoint.com',
        voiceModelEndpoint: 'https://test-endpoint.com',
        groqApiKey: 'test-api-key',
        useMockTranscription: true,
        useMockLlmResponses: true,
        isProductionMode: false,
      ));
    }
    
    // Register the mock GroqService
    if (serviceLocator.isRegistered<GroqService>()) {
      serviceLocator.unregister<GroqService>();
    }
    serviceLocator.registerSingleton<GroqService>(SimpleGroqServiceMock());
  });
  
  group('Therapy Conversation Tests', () {
    test('TherapyConversationGraph should handle basic conversation', () async {
      final graph = TherapyConversationGraph();
      await graph.initializeSession();
      
      final response = await graph.processUserMessage('I\'m feeling anxious today');
      
      expect(response, contains('anxious'));
      expect(graph.isSessionActive, isTrue);
      expect(graph.conversationHistory.length, 2); // User message and AI response
    });
    
    test('Prompt Templates should format properly', () {
      final formattedPrompt = TherapyPromptTemplates.formatTherapistPrompt(
        therapistStyle: 'cbt',
        sessionPhase: 'exploration',
        topic: 'anxiety',
        issues: 'work stress',
        mood: 'stressed',
        specificInstructions: 'Help the user identify thought patterns.',
      );
      
      expect(formattedPrompt, contains('Cognitive Behavioral Therapy'));
      expect(formattedPrompt, contains('exploration'));
      expect(formattedPrompt, contains('anxiety'));
      expect(formattedPrompt, contains('work stress'));
      expect(formattedPrompt, contains('stressed'));
      expect(formattedPrompt, contains('Help the user identify thought patterns'));
    });
  });
} 