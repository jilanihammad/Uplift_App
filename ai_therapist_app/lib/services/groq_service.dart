import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/config/api.dart';
import 'package:ai_therapist_app/services/langchain/custom_langchain.dart';

/// Service for handling text completions via Groq LLM
/// This service is only used for text generation - TTS and transcription are handled by OpenAI
class GroqService {
  // API client for making requests to backend
  late ApiClient _apiClient;

  // API connection details
  late String _llmModelId;

  // Flag to track if service is available
  bool _isAvailable = false;

  // LangChain conversation buffer memory
  ConversationBufferMemory? _memory;

  // Initialize the service
  Future<void> init() async {
    try {
      // Get configuration service
      final config = serviceLocator<ConfigService>();

      // Set model ID - only care about LLM, not TTS or transcription
      _llmModelId = config.llmModelId.isNotEmpty
          ? config.llmModelId
          : "llama3-70b-8192"; // Default to Llama 3 if not specified

      // Initialize API client with the backend URL
      _apiClient = serviceLocator<ApiClient>();

      // Initialize LangChain memory
      _memory = ConversationBufferMemory();

      if (kDebugMode) {
        print('GroqService: Initialized with LLM model: $_llmModelId');
        print('GroqService: Using API base URL: ${ApiConfig.baseUrl}');
        print('GroqService: Initialized LangChain memory');
      }

      // Check if backend LLM service is available
      try {
        // Use backend's status endpoint
        final response = await _apiClient.get('/llm/status');

        if (kDebugMode) {
          print('GroqService: Status response: $response');
        }

        if (response != null && response['status'] == 'available') {
          _isAvailable = true;
          if (kDebugMode) {
            print('GroqService: API is available');
          }
        } else {
          _isAvailable = false;
          if (kDebugMode) {
            print(
                'GroqService: API reported as unavailable. Response: $response');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('GroqService: Error checking API availability: $e');
          print('GroqService: Will continue with isAvailable=false');
        }
        _isAvailable = false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('GroqService initialization error: $e');
      }
      _isAvailable = false;
    }
  }

  // Reset conversation memory
  void resetConversationMemory() {
    _memory = ConversationBufferMemory();
    if (kDebugMode) {
      print('GroqService: Reset conversation memory');
    }
  }

  // Get current memory as formatted context
  String? get conversationMemory {
    if (_memory == null) return null;
    return _memory.getBuffer();
  }

  // Check if service is available
  bool get isConfigured => _isAvailable;

  // Override isConfigured if needed for testing
  void setAvailable(bool available) {
    _isAvailable = available;
    if (kDebugMode) {
      print('GroqService: Manually set isAvailable=$available');
    }
  }

  // Get LLM model ID
  String get llmModelId => _llmModelId;

  // Generate chat completion using the LLM model
  Future<String> generateChatCompletion({
    required String userMessage,
    String systemPrompt = '',
    String? model,
    double temperature = 0.7,
    int maxTokens = 1000,
  }) async {
    if (!_isAvailable) {
      throw Exception('GroqService is not available');
    }

    try {
      // Add message to memory
      _memory?.addUserMessage(userMessage);

      // Make API request to backend proxy for Groq
      final response = await _apiClient.post('/ai/generate', body: {
        'message': userMessage,
        'system_prompt': systemPrompt,
        'model': model ?? _llmModelId,
        'temperature': temperature,
        'max_tokens': maxTokens,
      });

      if (response != null && response.containsKey('response')) {
        final aiResponse = response['response'];

        // Add response to memory
        _memory?.addAIMessage(aiResponse);

        return aiResponse;
      } else {
        throw Exception('Invalid response format from LLM API');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GroqService: Error generating chat completion: $e');
      }
      rethrow;
    }
  }

  // Test the connection to the backend LLM API
  Future<Map<String, dynamic>> testConnection() async {
    try {
      // Make API request to test the connection
      final response = await _apiClient.get('/ai/test-key');

      if (response != null) {
        // Update availability based on test result
        if (response.containsKey('groq_api') &&
            response['groq_api'] is Map<String, dynamic> &&
            response['groq_api'].containsKey('available')) {
          _isAvailable = response['groq_api']['available'] == true;
        }

        return response;
      } else {
        return {'available': false, 'error': 'No response from test endpoint'};
      }
    } catch (e) {
      if (kDebugMode) {
        print('GroqService: Error testing connection: $e');
      }
      return {'available': false, 'error': e.toString()};
    }
  }
}
