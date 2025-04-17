import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/services/langchain/custom_langchain.dart';

class GroqService {
  // API client for making requests to backend
  late ApiClient _apiClient;
  
  // API connection details
  late String _llmModelId;
  late String _ttsModelId;
  late String _transcriptionModelId;
  
  // Flag to track if service is available
  bool _isAvailable = false;
  
  // LangChain conversation buffer memory
  ConversationBufferMemory? _memory;
  
  // Initialize the service
  Future<void> init() async {
    try {
      final config = serviceLocator<ConfigService>();
      _llmModelId = config.llmModelId;
      _ttsModelId = config.ttsModelId;
      _transcriptionModelId = config.transcriptionModelId;
      
      // Initialize API client with the backend URL
      _apiClient = ApiClient(baseUrl: config.llmApiEndpoint);
      
      // Initialize LangChain memory
      _memory = ConversationBufferMemory();
      
      if (kDebugMode) {
        print('GroqService: Initializing with endpoint: ${config.llmApiEndpoint}');
        print('GroqService: Using LLM model: $_llmModelId');
        print('GroqService: Using TTS model: $_ttsModelId');
        print('GroqService: Using Transcription model: $_transcriptionModelId');
        print('GroqService: Initialized LangChain memory');
      }
      
      // Check if backend LLM service is available
      try {
        // Use your backend's status endpoint
        final response = await _apiClient.get('/api/v1/llm/status');
        
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
            print('GroqService: API reported as unavailable. Response: $response');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('GroqService: Error checking API availability: $e');
          print('GroqService: Will continue with isAvailable=false');
          print('GroqService: Will try to manually set isAvailable=true to attempt API calls anyway');
        }
        _isAvailable = true; // Try to use the service anyway
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
  
  // Get TTS model ID
  String get ttsModelId => _ttsModelId;
  
  // Get transcription model ID
  String get transcriptionModelId => _transcriptionModelId;
  
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
      final response = await _apiClient.post('/api/v1/ai/response', body: {
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
  
  // Generate audio using the TTS model
  Future<String> generateSpeech({
    required String text,
    String? voice = 'claude',
  }) async {
    if (!_isAvailable) {
      throw Exception('GroqService is not available');
    }
    
    try {
      // Make API request to backend proxy for Groq TTS
      final response = await _apiClient.post('/voice/synthesize', body: {
        'text': text,
        'voice': voice,
        'model': _ttsModelId,
      });
      
      if (response != null && response.containsKey('audio_url')) {
        return response['audio_url'];
      } else {
        throw Exception('Invalid response format from TTS API');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GroqService: Error generating speech: $e');
      }
      rethrow;
    }
  }
  
  // Transcribe audio using the transcription model
  Future<String> transcribeAudio({
    required String audioUrl,
  }) async {
    if (!_isAvailable) {
      throw Exception('GroqService is not available');
    }
    
    try {
      // Make API request to backend proxy for Groq transcription
      final response = await _apiClient.post('/voice/transcribe', body: {
        'audio_url': audioUrl,
        'model': _transcriptionModelId,
      });
      
      if (response != null && response.containsKey('transcription')) {
        return response['transcription'];
      } else {
        throw Exception('Invalid response format from transcription API');
      }
    } catch (e) {
      if (kDebugMode) {
        print('GroqService: Error transcribing audio: $e');
      }
      rethrow;
    }
  }
} 