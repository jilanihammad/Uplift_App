import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/config/api.dart';
import 'package:ai_therapist_app/services/langchain/custom_langchain.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:async';
import '../di/interfaces/i_groq_service.dart';

/// Service for handling text completions via Groq LLM
/// This service is only used for text generation - TTS and transcription are handled by OpenAI
class GroqService implements IGroqService {
  // Dependencies
  final ConfigService _configService;
  final ApiClient _apiClient;

  // Constructor with dependency injection
  GroqService({
    ConfigService? configService,
    ApiClient? apiClient,
  }) : _configService = configService ?? DependencyContainer().configService,
       _apiClient = apiClient ?? DependencyContainer().apiClientConcrete;

  // API connection details
  late String _llmModelId;

  // Flag to track if service is available
  bool _isAvailable = false;

  // LangChain conversation buffer memory
  ConversationBufferMemory? _memory;

  String? _sessionId;

  // Getter and setter for sessionId
  @override
  String? get sessionId => _sessionId;
  @override
  set sessionId(String? value) => _sessionId = value;

  // Initialize the service
  @override
  Future<void> init() async {
    try {
      // Set model ID - only care about LLM, not TTS or transcription
      _llmModelId = _configService.llmModelId.isNotEmpty
          ? _configService.llmModelId
          : "llama3-70b-8192"; // Default to Llama 3 if not specified

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
  @override
  void resetConversationMemory() {
    _memory = ConversationBufferMemory();
    if (kDebugMode) {
      print('GroqService: Reset conversation memory');
    }
  }

  // Get current memory as formatted context
  @override
  String? get conversationMemory {
    return _memory?.getBuffer();
  }

  // Check if service is available
  @override
  bool get isConfigured => _isAvailable;

  // Override isConfigured if needed for testing
  @override
  void setAvailable(bool available) {
    _isAvailable = available;
    if (kDebugMode) {
      print('GroqService: Manually set isAvailable=$available');
    }
  }

  // Get LLM model ID
  @override
  String get llmModelId => _llmModelId;

  // Generate chat completion using the LLM model
  @override
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
      final response = await _apiClient.post('/ai/generate', {
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
  @override
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

  /// Stream chat completion from backend via WebSocket
  /// [history] should be a list of message objects: [{"role": ..., "content": ...}]
  @override
  Stream<Map<String, dynamic>> streamChatCompletionViaWebSocket({
    required String message,
    List<Map<String, dynamic>> history = const [],
    String? sessionId,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    Duration inactivityTimeout = const Duration(seconds: 30),
  }) async* {
    final String httpBase = ApiConfig.baseUrlWithoutPath;
    String wsProtocol;
    if (httpBase.startsWith('https://')) {
      wsProtocol = 'wss://';
    } else if (httpBase.startsWith('http://')) {
      wsProtocol = 'ws://';
    } else {
      throw Exception('Invalid backend URL: $httpBase');
    }
    final String host = httpBase.replaceFirst(RegExp(r'^https?://'), '');
    final String wsUrl = wsProtocol + host + '/api/v1/llm/ws/chat';

    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      final input = {
        'type': 'message',
        'message': message,
        'history': history,
        if ((sessionId ?? _sessionId) != null)
          'session_id': sessionId ?? _sessionId,
      };
      channel.sink.add(jsonEncode(input));
      bool shouldRetry = false;
      bool timedOut = false;
      DateTime lastMessageTime = DateTime.now();
      final timer = Timer.periodic(const Duration(seconds: 2), (t) {
        if (DateTime.now().difference(lastMessageTime) > inactivityTimeout) {
          timedOut = true;
          channel.sink.close(status.normalClosure);
          t.cancel();
        }
      });
      try {
        await for (final event in channel.stream) {
          lastMessageTime = DateTime.now();
          if (event is String) {
            print('RAW WS EVENT: ' +
                event); // <-- Debug print for raw WebSocket response
            try {
              final data = jsonDecode(event);
              // Store session_id if present in the first chunk or done message
              if (data is Map<String, dynamic> &&
                  data.containsKey('session_id')) {
                _sessionId = data['session_id'];
              }
              if (data is! Map<String, dynamic> ||
                  !data.containsKey('type') ||
                  !(data['type'] == 'chunk' ||
                      data['type'] == 'done' ||
                      data['type'] == 'error')) {
                yield {
                  'type': 'error',
                  'detail': 'Malformed message: missing or invalid type',
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                };
                channel.sink.close(status.normalClosure);
                break;
              }
              yield data;
              if (data['type'] == 'done' || data['type'] == 'error') {
                channel.sink.close(status.normalClosure);
                break;
              }
            } catch (e) {
              yield {
                'type': 'error',
                'detail': 'Failed to decode message: $e',
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              };
              channel.sink.close(status.normalClosure);
              break;
            }
          }
        }
        timer.cancel();
        if (timedOut) {
          yield {
            'type': 'error',
            'detail': 'Connection timed out due to inactivity.',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };
          break;
        }
        break;
      } catch (e) {
        timer.cancel();
        if (e is WebSocketChannelException ||
            e.toString().contains('SocketException')) {
          if (attempt < maxRetries) {
            shouldRetry = true;
            await Future.delayed(retryDelay);
            continue;
          }
        }
        yield {
          'type': 'error',
          'detail': 'Something went wrong. Please try again. (${e.toString()})',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };
        channel.sink.close(status.normalClosure);
        break;
      }
      if (!shouldRetry) break;
    }
  }
}
