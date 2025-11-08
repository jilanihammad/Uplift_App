import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/datasources/remote/api_client.dart';
import '../utils/logger_util.dart';
import '../config/app_config.dart';
import '../config/llm_config.dart'; // Import LLM Configuration
import './langchain/custom_langchain.dart'; // Added for ConversationBufferMemory
import './config_service.dart'; // Added for ConfigService
import '../di/interfaces/i_groq_service.dart'; // Added for GroqService streaming
import '../utils/box_logger.dart';
import '../utils/log_channels.dart';

/// Handles processing of user messages and generating AI responses
class MessageProcessor {
  final ConversationBufferMemory _conversationHistory;
  final ConfigService _configService;
  final ApiClient apiClient;
  final IGroqService _groqService;

  bool _directLLMEnabled = false;
  static const String _directLLMLogTag = '[MessageProcessorDirectLLM]';

  // Cache for API responses to avoid redundant processing
  final Map<String, String> _responseCache = {};
  String? _lastFallbackResponse;

  // List of predefined therapist responses based on keywords
  final Map<String, List<String>> _responseTemplates = {
    'anxious': [
      "It sounds like you're experiencing anxiety. Let's explore what might be triggering these feelings.",
      "Anxiety can be challenging to deal with. Can you tell me more about when you notice these feelings arising?",
      "I'm hearing that anxiety is something you're struggling with. What strategies have you tried in the past to manage it?"
    ],
    'sad': [
      "I can hear that you're feeling down right now. Would you like to talk more about what's contributing to these feelings?",
      "Feeling sad is a natural emotion. Can you tell me more about what's been happening recently?",
      "Thank you for sharing that you're feeling sad. Is there something specific that triggered these emotions?"
    ],
    'stress': [
      "Stress can be quite overwhelming. What are the main sources of stress in your life right now?",
      "It sounds like you're under a lot of pressure. How has this been affecting your daily life?",
      "Managing stress is important for our wellbeing. What self-care activities have you found helpful in the past?"
    ],
    'work': [
      "Work challenges can be quite impactful on our mental health. Can you tell me more about what's happening at work?",
      "I understand work is causing some difficulty for you. How has your work-life balance been lately?",
      "Work stress is very common. What aspects of your job do you find most challenging?"
    ],
    'relationship': [
      "Relationships can be complex and emotionally demanding. How long have you been experiencing these difficulties?",
      "It sounds like your relationship is currently challenging. What do you think might help improve the situation?",
      "Thank you for sharing about your relationship concerns. How have you been communicating your needs?"
    ],
    'help': [
      "It takes courage to ask for help, and I'm glad you reached out. What kind of support would be most helpful right now?",
      "I'm here to support you. Let's think together about what might be most helpful for your situation.",
      "Asking for help is a sign of strength. What specific areas would you like to focus on in our conversations?"
    ]
  };

  MessageProcessor({
    required ConversationBufferMemory conversationHistory,
    required ConfigService configService,
    required IGroqService groqService,
  })  : _conversationHistory = conversationHistory,
        _configService = configService,
        _groqService = groqService,
        apiClient = ApiClient(configService: configService) {
    _init();
    debugPrint(
        '[MessageProcessor] Initialized. ApiClient hash: ${apiClient.hashCode}');
  }

  Future<void> _init() async {
    // Initialize _directLLMEnabled, perhaps from _configService or AppConfig
    // Assuming ConfigService holds this mode flag or can derive it
    _directLLMEnabled = _configService.directLLMModeEnabled;
    debugPrint(
        '[MessageProcessor] _init complete. Direct LLM Mode: $_directLLMEnabled');
  }

  /// Process a user message and get an AI response
  Future<String> processMessage(
    String userMessage,
    String systemPrompt,
    Map<String, dynamic> graphResult, {
    List<Map<String, String>>? history,
  }) async {
    try {
      if (userMessage.trim().isEmpty) {
        return "I didn't catch that. Could you please repeat?";
      }

      log.d(
          'Processing message with graph state: ${graphResult['state'] ?? 'unknown'}');
      if (history != null && history.isNotEmpty) {
        log.d('MessageProcessor received history of length: ${history.length}');
        // Log the actual history content for debugging if needed (be mindful of PII in production logs)
        // history.forEach((msg) => log.d('History: Role: ${msg["role"]}, Content: ${msg["content"]?.substring(0, min(msg["content"]?.length ?? 0, 50))}...'));
      } else {
        log.d('MessageProcessor received no history or empty history.');
      }

      final cacheKey =
          '$userMessage-${systemPrompt.hashCode}-${graphResult.toString()}-${history?.toString().hashCode ?? 0}';
      if (_responseCache.containsKey(cacheKey)) {
        log.d('Cache hit! Using cached response for key: $cacheKey');
        return _responseCache[cacheKey]!;
      }

      String response;

      if (_directLLMEnabled) {
        response = await _processMessageDirectLLM(
            userMessage, systemPrompt, graphResult,
            history: history);
      } else {
        response = await _processMessageViaBackend(
            userMessage, systemPrompt, graphResult,
            history: history);
      }

      _responseCache[cacheKey] = response;

      if (_responseCache.length > 100) {
        final oldestKey = _responseCache.keys.first;
        _responseCache.remove(oldestKey);
      }

      return response;
    } catch (e, stackTrace) {
      log.e('General error processing message', e, stackTrace);
      return "I'm having trouble understanding that right now. Could you try expressing that differently?";
    }
  }

  /// Process message using direct LLM API calls
  Future<String> _processMessageDirectLLM(
    String userMessage,
    String systemPrompt,
    Map<String, dynamic> graphResult, {
    List<Map<String, String>>? history,
  }) async {
    try {
      log.d(
          'Using direct LLM calls (${LLMConfig.activeLLMProvider} - ${LLMConfig.activeLLMModelId})');

      final effectiveSystemPrompt =
          _buildSystemPrompt(systemPrompt, graphResult);

      // Use the internal conversation history
      final currentLLMHistory = _conversationHistory.getMessages();
      log.d(
          '[MessageProcessorDirectLLM] Using internal history of length: ${currentLLMHistory.length}');

      final response = await apiClient.callLLMDirect(
        effectiveSystemPrompt,
        userMessage,
        conversationHistory: currentLLMHistory,
        additionalParams: {
          'temperature': 0.7,
          'max_tokens': 1000,
        },
      );

      // Future-proof version validation for direct LLM calls
      final responseText = _validateAndExtractResponse(response, 'direct LLM');

      if (kDebugMode) {
        debugPrint(
            '$_directLLMLogTag Direct LLM response received: ${responseText.length} characters');
        if (response.containsKey('usage')) {
          debugPrint('$_directLLMLogTag Token usage: ${response['usage']}');
        }
      }

      return responseText.trim();
    } catch (e) {
      log.e(
          '$_directLLMLogTag Error with direct LLM call, falling back to local response',
          e);
      return _generateFallbackResponseLocally(userMessage);
    }
  }

  /// Process message using backend proxy (original behavior)
  Future<String> _processMessageViaBackend(
    String userMessage,
    String systemPrompt,
    Map<String, dynamic> graphResult, {
    List<Map<String, String>>? history,
  }) async {
    try {
      final effectiveSystemPrompt =
          _buildSystemPrompt(systemPrompt, graphResult);

      // Use the internal conversation history
      final currentLLMHistory = _conversationHistory.getMessages();
      log.d(
          '[MessageProcessorBackend] Using internal history of length: ${currentLLMHistory.length}');
      if (history != null) {
        log.d(
            '[MessageProcessorBackend] Received history parameter with length: ${history.length}');
      } else {
        log.d('[MessageProcessorBackend] Received null history parameter.');
      }

      final payload = {
        'message': userMessage,
        'system_prompt': effectiveSystemPrompt,
        'conversation_state': graphResult['state'] ?? 'exploration',
        'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
        'topics': graphResult['analysis']?['topics'] ?? [],
        'history': history ??
            currentLLMHistory, // Ensure we use the passed-in history if available
      };

      try {
        final payloadPreview = json.encode({
          'message': payload['message'],
          'state': payload['conversation_state'],
          'historyCount': (payload['history'] as List).length,
        });
        if (LogChannels.therapyTrace && kDebugMode) {
          log.d(
              'Preparing to call API endpoint: /ai/response with payload: ${json.encode(payload)}');
        } else {
          BoxLogger.debug(
            '🌐',
            'MessageProcessor',
            'Calling /ai/response',
            details: {'payload': payloadPreview},
          );
        }
        // The AppConfig().backendUrl might be slightly different from _configService.llmApiEndpoint
        // if directLLMMode is true, but for backend calls, this should be fine.
        // ApiClient will use the correct base URL from ConfigService.llmApiEndpoint getter.
        // REMOVED: final backendApiUrl = _configService.backendBaseUrl;
        // log.d('Using API URL: $backendApiUrl/ai/response');

        final response = await apiClient.post('/ai/response', payload);

        // Future-proof version validation - prepare for schema versioning
        return _validateAndExtractResponse(response, 'backend API');
      } catch (e, stackTrace) {
        log.e('Backend API Error', e, stackTrace);
        _logDetailedError(e);
        rethrow; // Re-throw to be caught by the outer try-catch
      }
    } catch (e) {
      log.w('Backend call failed, generating fallback response');
      return _generateFallbackResponseLocally(userMessage);
    }
  }

  /// Process parameters and generate a fallback response
  String _pickNonRepeating(List<String> options, int index) {
    if (options.isEmpty) {
      return '';
    }
    var choice = options[index % options.length];
    if (_lastFallbackResponse != null &&
        options.length > 1 &&
        choice == _lastFallbackResponse) {
      choice = options[(index + 1) % options.length];
    }
    _lastFallbackResponse = choice;
    return choice;
  }

  /// Generate a fallback response locally (without compute)
  String _generateFallbackResponseLocally(String userMessage) {
    final lowerMessage = userMessage.toLowerCase();

    // Generate a seed based on the message content for consistent but varied responses
    int seed = 0;
    for (int i = 0; i < userMessage.length; i++) {
      seed += userMessage.codeUnitAt(i);
    }

    // Find matching keywords
    List<String> matchedKeywords = [];
    for (final keyword in _responseTemplates.keys) {
      if (lowerMessage.contains(keyword)) {
        matchedKeywords.add(keyword);
      }
    }

    // If we found matches, use those templates
    if (matchedKeywords.isNotEmpty) {
      final keyword = matchedKeywords[seed % matchedKeywords.length];
      final responses = _responseTemplates[keyword]!;
      return _pickNonRepeating(responses, seed);
    }

    // Default responses for when no keywords match
    final List<String> defaultResponses = [
      "Thank you for sharing that with me. Could you tell me more about how that makes you feel?",
      "I appreciate you opening up. How long have you been experiencing this?",
      "I'm listening and I'm here to support you. What would be helpful for you right now?",
      "That sounds challenging. Would you like to explore this further together?",
    ];

    return _pickNonRepeating(defaultResponses, seed);
  }

  /// Build system prompt based on graph analysis results
  String _buildSystemPrompt(
      String basePrompt, Map<String, dynamic> graphResult) {
    String prompt = basePrompt;

    // Add graph-specific prompt guidance if available
    if (graphResult.containsKey('prompt') && graphResult['prompt'] != null) {
      prompt = '$prompt\n\n${graphResult['prompt']}';
    }

    // Add state context
    if (graphResult.containsKey('state') && graphResult['state'] != null) {
      prompt = '$prompt\n\nCurrent conversation state: ${graphResult['state']}';
    }

    // Add technique guidance if available
    if (graphResult.containsKey('techniques') &&
        graphResult['techniques'] != null) {
      final techniques = graphResult['techniques'];
      if (techniques is List && techniques.isNotEmpty) {
        prompt =
            '$prompt\n\nUse these therapeutic techniques: ${techniques.join(', ')}';
      }
    }

    return prompt;
  }

  /// Log detailed error information based on error type
  void _logDetailedError(dynamic e) {
    if (e is SocketException) {
      log.e(
          'Network error: ${e.message}. Address: ${e.address}, Port: ${e.port}');
    } else if (e is TimeoutException) {
      log.e('Request timed out');
    } else if (e is FormatException) {
      log.e('Format exception (likely JSON parsing error): ${e.message}');
    } else if (e is HttpException) {
      log.e('HTTP exception: ${e.message}');
    }
  }

  /// Generate end of session summary
  Future<Map<String, dynamic>> generateSessionSummary(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    String? sessionTitle,
    int? userId,
  }) async {
    try {
      log.i('Generating session summary for ${messages.length} messages');

      if (_directLLMEnabled) {
        // Use direct LLM call for session summary
        return await _generateSessionSummaryDirectLLM(messages, systemPrompt);
      } else {
        // Use backend proxy (original behavior)
        return await _generateSessionSummaryViaBackend(messages, systemPrompt,
            sessionTitle: sessionTitle, userId: userId);
      }
    } catch (e) {
      log.e('Error ending session', e);
      return {
        'error': 'Unable to generate session summary',
        'details': e.toString(),
        'summary': 'Your session has ended. Thank you for using AI Therapist.',
        'action_items': [
          'Practice self-care',
          'Remember the strategies discussed'
        ],
      };
    }
  }

  /// Generate session summary using direct LLM call
  Future<Map<String, dynamic>> _generateSessionSummaryDirectLLM(
      List<Map<String, dynamic>> messages, String systemPrompt) async {
    try {
      log.d('Using direct LLM call for session summary');

      // Build conversation text
      final conversationText = messages.map((msg) {
        final role = msg['isUser'] == true ? 'User' : 'Therapist';
        return '$role: ${msg['content']}';
      }).join('\n\n');

      // Create summary prompt
      final summaryPrompt =
          '''Based on this therapy session conversation, please provide:

1. A compassionate summary of the session (2-3 sentences)
2. 3-5 actionable items for the client to consider
3. Key topics discussed

Return your response in JSON format:
{
  "summary": "...",
  "action_items": ["...", "...", "..."],
  "topics": ["...", "...", "..."]
}

Conversation:
$conversationText''';

      // Make direct LLM call
      final response = await apiClient.callLLMDirect(
        'You are an expert therapist creating session summaries. Provide thoughtful, actionable insights.',
        summaryPrompt,
        additionalParams: {
          'temperature': 0.3, // Lower temperature for more consistent summaries
          'max_tokens': 1500,
        },
      );

      if (response.containsKey('response') && response['response'] != null) {
        final responseText = response['response'] as String;

        // Try to parse as JSON with improved format validation
        final jsonCandidate = _extractJsonFromResponse(responseText);
        if (jsonCandidate != null && _isValidJsonFormat(jsonCandidate)) {
          try {
            final parsedJson =
                json.decode(jsonCandidate) as Map<String, dynamic>;

            log.i(
                'Session summary generated successfully via direct LLM (JSON format)');
            return {
              'summary':
                  parsedJson['summary'] ?? 'Session completed successfully.',
              'action_items':
                  parsedJson['action_items'] ?? ['Practice self-care'],
              'topics': parsedJson['topics'] ?? [],
              'generated_via': 'direct_llm',
            };
          } on FormatException catch (e) {
            log.w('FormatException parsing LLM response as JSON: ${e.message}');
            // Continue to plain text processing
          } catch (e) {
            log.w('Unexpected error parsing LLM response as JSON: $e');
            // Continue to plain text processing
          }
        } else {
          log.i(
              'LLM response detected as plain text format, processing accordingly');
        }

        // If JSON parsing fails, create summary from text
        return {
          'summary': responseText.length > 500
              ? '${responseText.substring(0, 500)}...'
              : responseText,
          'action_items': ['Reflect on today\'s session', 'Practice self-care'],
          'topics': [],
          'generated_via': 'direct_llm_text',
        };
      }

      throw Exception('No response from direct LLM call');
    } catch (e) {
      log.e('Error with direct LLM session summary, falling back', e);
      return _generateFallbackSummary(messages);
    }
  }

  /// Generate session summary using backend proxy (original behavior)
  Future<Map<String, dynamic>> _generateSessionSummaryViaBackend(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    String? sessionTitle,
    int? userId,
  }) async {
    try {
      log.i('Making API call to end_session with payload: ${json.encode({
            'messages_count': messages.length,
            'system_prompt_length': systemPrompt.length
          })}');

      // Make API call to end session and get summary
      final payload = {
        'messages': messages,
        'system_prompt': systemPrompt,
      };

      // Add optional session metadata if provided
      if (sessionTitle != null) {
        payload['session_title'] = sessionTitle;
      }
      if (userId != null) {
        payload['user_id'] = userId;
      }

      final response = await apiClient.post('/therapy/end_session', payload);

      log.i('Received response from end_session API: ${json.encode(response)}');
      log.i('Session summary generated successfully');
      return response;
    } catch (e) {
      log.e('Backend API error in generateSessionSummary', e);
      _logDetailedError(e);
      return _generateFallbackSummary(messages);
    }
  }

  /// Generate a fallback summary when the API call fails
  Map<String, dynamic> _generateFallbackSummary(
      List<Map<String, dynamic>> messages) {
    try {
      log.i('Generating fallback summary for ${messages.length} messages');

      // Extract user messages for topics
      final userMessages = messages
          .where((m) => m['isUser'] == true)
          .map((m) => m['content'] as String)
          .toList();

      // Simple topic extraction
      final List<String> possibleTopics = [
        'anxiety',
        'stress',
        'depression',
        'relationships',
        'work',
        'family',
        'health',
        'emotions',
        'self-care',
        'goals',
        'challenges'
      ];

      final List<String> detectedTopics = [];
      for (final topic in possibleTopics) {
        if (userMessages
            .any((msg) => msg.toLowerCase().contains(topic.toLowerCase()))) {
          detectedTopics.add(topic);
        }
      }

      final summary = 'Thank you for your session today. '
          'We discussed ${detectedTopics.isEmpty ? 'some important topics' : 'topics including ${detectedTopics.take(3).join(', ')}'}, '
          'and explored ways to approach these areas in your life. '
          'Remember that personal growth takes time, and it\'s important to be patient with yourself.';

      final actionItems = [
        'Take time for self-reflection',
        'Practice the strategies we discussed',
        'Be kind to yourself',
        'Return for another session when you feel ready'
      ];

      return {
        'summary': summary,
        'action_items': actionItems,
        'topics': detectedTopics.take(5).toList(),
        'generated_locally': true
      };
    } catch (e) {
      log.e('Error generating fallback summary', e);

      // Most basic fallback
      return {
        'summary':
            'Thank you for your session today. I hope our conversation was helpful.',
        'action_items': [
          'Take care of yourself',
          'Return soon for another session'
        ],
        'error': 'Could not generate detailed summary: $e'
      };
    }
  }

  /// Check the status of all backend services
  Future<Map<String, dynamic>> checkServiceStatus() async {
    try {
      log.d('Checking service status...');
      final backendUrl = AppConfig().backendUrl;

      try {
        // Make a request to the service status endpoint
        log.d('Making request to $backendUrl/llm/status');
        final response = await apiClient.get('/llm/status');

        log.d('Service status response: $response');
        return response;
      } catch (e) {
        log.e('Error checking service status', e);
        _logDetailedError(e);

        if (e is SocketException) {
          return {
            'error': 'Network error: ${e.message}',
            'status': 'offline',
            'details': 'Cannot connect to server'
          };
        } else if (e is TimeoutException) {
          return {
            'error': 'Request timed out',
            'status': 'timeout',
            'details': 'Server took too long to respond'
          };
        }

        return {'error': 'Unknown error: ${e.toString()}', 'status': 'error'};
      }
    } catch (e) {
      log.e('General error in checkServiceStatus', e);
      return {
        'error': 'Error checking service status: ${e.toString()}',
        'status': 'error'
      };
    }
  }

  /// Stream a user message and get an AI response via WebSocket
  Stream<Map<String, dynamic>> streamMessage(
    String userMessage,
    String systemPrompt,
    Map<String, dynamic> graphResult, {
    List<Map<String, dynamic>>? history,
  }) async* {
    try {
      if (userMessage.trim().isEmpty) {
        yield {
          'type': 'error',
          'detail': "I didn't catch that. Could you please repeat?",
        };
        return;
      }

      log.d(
          'Starting message streaming with graph state: ${graphResult['state'] ?? 'unknown'}');

      // Prepare the conversation history
      List<Map<String, dynamic>> conversationHistory = history ?? [];

      // Add system prompt to history if provided
      if (systemPrompt.isNotEmpty) {
        conversationHistory.insert(0, {
          'role': 'system',
          'content': _buildSystemPrompt(systemPrompt, graphResult),
        });
      }

      log.d('Streaming message via WebSocket to LLM...');

      // Stream the response from GroqService
      await for (final chunk in _groqService.streamChatCompletionViaWebSocket(
        message: userMessage,
        history: conversationHistory,
      )) {
        yield chunk;
      }
    } catch (e) {
      log.e('Error in message streaming', e);
      yield {
        'type': 'error',
        'detail': 'Error processing message: ${e.toString()}',
      };
    }
  }

  /// Extract potential JSON content from LLM response text
  String? _extractJsonFromResponse(String responseText) {
    // First try to find JSON wrapped in code blocks
    final codeBlockRegex =
        RegExp(r'```(?:json)?\s*(\{.*?\})\s*```', dotAll: true);
    final codeBlockMatch = codeBlockRegex.firstMatch(responseText);
    if (codeBlockMatch != null) {
      return codeBlockMatch.group(1)?.trim();
    }

    // Then try to find standalone JSON object
    final jsonRegex = RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', dotAll: true);
    final jsonMatch = jsonRegex.firstMatch(responseText);
    if (jsonMatch != null) {
      return jsonMatch.group(0)?.trim();
    }

    return null;
  }

  /// Enhanced JSON format validation to reduce false positives
  bool _isValidJsonFormat(String text) {
    final trimmed = text.trim();

    // Basic structure check - must start with { and end with }
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return false;
    }

    // Must contain at least one colon (key-value pairs)
    if (!trimmed.contains(':')) {
      return false;
    }

    // Should have matching braces
    int braceCount = 0;
    for (int i = 0; i < trimmed.length; i++) {
      if (trimmed[i] == '{') braceCount++;
      if (trimmed[i] == '}') braceCount--;
      if (braceCount < 0) return false; // More closing than opening braces
    }

    // Final brace count should be zero
    if (braceCount != 0) return false;

    // Quick validation for common JSON patterns
    if (trimmed.contains('"') &&
        (trimmed.contains('":') || trimmed.contains('" :'))) {
      return true;
    }

    // If it looks like JSON but doesn't have quotes, it might be malformed
    // In this case, we'll let jsonDecode handle it and catch the FormatException
    return true;
  }

  /// Future-proof response validation with version awareness
  /// Validates API response format and extracts content with explicit type safety
  String _validateAndExtractResponse(
      Map<String, dynamic>? response, String source) {
    if (response == null) {
      throw BackendSchemaException(
        message: '$source returned null response',
        expectedField: 'response',
        receivedResponse: response,
      );
    }

    // Future enhancement: Check for schema version if present
    if (response.containsKey('schema')) {
      final schema = response['schema'];
      log.d('Response includes schema version: $schema');

      // Future: Handle different schema versions here
      switch (schema) {
        case 'v1':
          // Current format: {"schema": "v1", "response": "text"}
          break;
        case 'v2':
          // Future format: {"schema": "v2", "content": "text", "metadata": {...}}
          if (response.containsKey('content')) {
            return response['content'] as String;
          }
          throw BackendSchemaException(
            message: 'Schema v2 response missing content field',
            expectedField: 'content',
            receivedResponse: response,
          );
        default:
          log.w(
              'Unknown schema version: $schema, falling back to default parsing');
      }
    }

    // Current format validation: expect "response" field
    if (response.containsKey('response') && response['response'] != null) {
      log.d('$source call successful. Response received.');
      // Explicit cast for type safety - fails fast if backend sends wrong type
      return response['response'] as String;
    } else {
      log.w('Invalid response format from $source. Response was: $response');
      throw BackendSchemaException(
        message: '$source response missing required field',
        expectedField: 'response',
        receivedResponse: response,
      );
    }
  }
}
