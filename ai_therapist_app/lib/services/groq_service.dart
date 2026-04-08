import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/data/datasources/remote/api_client.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/services/config_service.dart';
import 'package:ai_therapist_app/config/api.dart';
import 'package:ai_therapist_app/services/langchain/custom_langchain.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:async';
import '../di/interfaces/i_groq_service.dart';
class GroqService implements IGroqService {
  final ConfigService _configService;
  final ApiClient _apiClient;
  GroqService({
    ConfigService? configService,
    ApiClient? apiClient,
  })  : _configService = configService ?? DependencyContainer().configService,
        _apiClient = apiClient ?? DependencyContainer().apiClientConcrete;
  late String _llmModelId;
  bool _isAvailable = false;
  ConversationBufferMemory? _memory;
  String? _sessionId;
  @override
  String? get sessionId => _sessionId;
  @override
  set sessionId(String? value) => _sessionId = value;
  @override
  Future<void> init() async {
    try {
      _llmModelId = _configService.llmModelId.isNotEmpty
          ? _configService.llmModelId
          : "llama3-70b-8192"; // Default to Llama 3 if not specified
      _memory = ConversationBufferMemory();
      try {
        final response = await _apiClient.get('/llm/status');
        if (response['status'] == 'available') {
          _isAvailable = true;
        } else {
          _isAvailable = false;
        }
      } catch (e) {
        _isAvailable = false;
      }
    } catch (e) {
      _isAvailable = false;
    }
  }
  @override
  void resetConversationMemory() {
    _memory = ConversationBufferMemory();
  }
  @override
  String? get conversationMemory {
    return _memory?.getBuffer();
  }
  @override
  bool get isConfigured => _isAvailable;
  @override
  void setAvailable(bool available) {
    _isAvailable = available;
  }
  @override
  String get llmModelId => _llmModelId;
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
      _memory?.addUserMessage(userMessage);
      final response = await _apiClient.post('/ai/generate', {
        'message': userMessage,
        'system_prompt': systemPrompt,
        'model': model ?? _llmModelId,
        'temperature': temperature,
        'max_tokens': maxTokens,
      });
      if (response.containsKey('response')) {
        final aiResponse = response['response'];
        _memory?.addAIMessage(aiResponse);
        return aiResponse;
      } else {
        throw Exception('Invalid response format from LLM API');
      }
    } catch (e) {
      rethrow;
    }
  }
  @override
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await _apiClient.get('/ai/test-key');
      if (response.containsKey('groq_api') &&
          response['groq_api'] is Map<String, dynamic> &&
          response['groq_api'].containsKey('available')) {
        _isAvailable = response['groq_api']['available'] == true;
      }
      return response;
        } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }
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
    final String wsUrl = '$wsProtocol$host/api/v1/llm/ws/chat';
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
            try {
              final data = jsonDecode(event);
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
