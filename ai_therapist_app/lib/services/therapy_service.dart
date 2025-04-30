import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../di/service_locator.dart';
import 'voice_service.dart';
import 'memory_service.dart';
import '../services/therapy_graph_service.dart';
import '../services/therapy_conversation_graph.dart';
import '../models/conversation_memory.dart';
import '../data/datasources/remote/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TherapyMood {
  veryHappy,
  happy,
  neutral,
  sad,
  verySad,
  anxious,
  angry,
  calm,
  stressed,
  confused
}

class TherapySession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  final List<TherapyServiceMessage> messages;
  final TherapyMood? initialMood;
  TherapyMood? finalMood;
  String? summary;
  List<String>? actionItems;

  TherapySession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.messages,
    this.initialMood,
    this.finalMood,
    this.summary,
    this.actionItems,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'initialMood': initialMood?.toString().split('.').last,
      'finalMood': finalMood?.toString().split('.').last,
      'summary': summary,
      'actionItems': actionItems,
    };
  }

  factory TherapySession.fromJson(Map<String, dynamic> json) {
    return TherapySession(
      id: json['id'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      messages: (json['messages'] as List)
          .map((m) => TherapyServiceMessage.fromJson(m))
          .toList(),
      initialMood: json['initialMood'] != null
          ? TherapyMood.values.firstWhere(
              (e) => e.toString().split('.').last == json['initialMood'])
          : null,
      finalMood: json['finalMood'] != null
          ? TherapyMood.values.firstWhere(
              (e) => e.toString().split('.').last == json['finalMood'])
          : null,
      summary: json['summary'],
      actionItems: json['actionItems'] != null
          ? List<String>.from(json['actionItems'])
          : null,
    );
  }
}

class TherapyServiceMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? audioUrl;

  TherapyServiceMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.audioUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'audioUrl': audioUrl,
    };
  }

  factory TherapyServiceMessage.fromJson(Map<String, dynamic> json) {
    return TherapyServiceMessage(
      id: json['id'],
      content: json['content'],
      isUser: json['isUser'],
      timestamp: DateTime.parse(json['timestamp']),
      audioUrl: json['audioUrl'],
    );
  }
}

// Enhanced therapy service with LangChain and LangGraph inspired features
class TherapyService {
  // Latest system prompt for the AI therapist
  String _systemPrompt = '';

  // Voice service for audio generation
  final VoiceService _voiceService;

  // Memory service for maintaining context
  final MemoryService _memoryService;

  // API client for making requests
  final ApiClient _apiClient;

  // Therapy conversation graph for managing the flow of therapy
  late TherapyConversationGraph _conversationGraph;

  // Therapeutic approach (defaults to supportive)
  TherapeuticApproach _therapeuticApproach = TherapeuticApproach.supportive;

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

  // Cache for API responses to avoid redundant processing
  final Map<String, String> _responseCache = {};

  // Constructor with injected dependencies
  TherapyService({
    required VoiceService voiceService,
    required MemoryService memoryService,
    required ApiClient apiClient,
  })  : _voiceService = voiceService,
        _memoryService = memoryService,
        _apiClient = apiClient {
    // Initialize conversation graph
    _conversationGraph = TherapyConversationGraph();
  }

  // Process parameters in background for API response
  static Future<Map<String, dynamic>> _prepareApiPayload(
      Map<String, dynamic> params) async {
    final userMessage = params['userMessage'] as String;
    final memoryContext = params['memoryContext'] as String;
    final systemPrompt = params['systemPrompt'] as String;
    final graphResult = params['graphResult'] as Map<String, dynamic>;
    final therapeuticApproach = params['therapeuticApproach'] as String;

    // Prepare system prompt with context
    String effectiveSystemPrompt = systemPrompt;
    if (graphResult.containsKey('prompt') && graphResult['prompt'] != null) {
      effectiveSystemPrompt = '$systemPrompt\n\n${graphResult['prompt']}';
    }

    // Add memory context to the system prompt
    if (memoryContext.isNotEmpty) {
      effectiveSystemPrompt =
          '$effectiveSystemPrompt\n\nRELEVANT CONTEXT FROM PREVIOUS SESSIONS:\n$memoryContext';
    }

    // Return the prepared payload
    return {
      'message': userMessage,
      'system_prompt': effectiveSystemPrompt,
      'conversation_state': graphResult['state'] ?? 'exploration',
      'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
      'topics': graphResult['analysis']?['topics'] ?? [],
      'approach': therapeuticApproach,
    };
  }

  // Method to initialize the therapy service
  Future<void> init() async {
    // Initialize memory service
    await _memoryService.init();

    // Initialize voice service
    try {
      await _voiceService.initialize();
      if (kDebugMode) {
        print('Voice service initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Warning: Voice service not initialized: $e');
        print('Therapy service will operate without voice capabilities');
      }
    }

    // Initialize conversation graph with default CBT approach
    _conversationGraph = TherapyConversationGraph.createCbtGraph();

    if (kDebugMode) {
      print('Therapy service initialized with conversation graph');
    }
  }

  // Set the therapist style system prompt
  void setTherapistStyle(String systemPrompt) {
    _systemPrompt = systemPrompt;
  }

  // Set the therapeutic approach
  void setTherapeuticApproach(TherapeuticApproach approach) {
    _therapeuticApproach = approach;

    // Update conversation graph based on selected approach
    if (approach == TherapeuticApproach.act) {
      _conversationGraph = TherapyConversationGraph.createActGraph();
    } else if (approach == TherapeuticApproach.cbt) {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    } else {
      // Default to CBT if no specific graph is available
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    }

    if (_conversationGraph != null) {
      _conversationGraph.approach = approach;
    }

    if (kDebugMode) {
      print(
          'Therapeutic approach set to: ${approach.toString().split('.').last}');
    }
  }

  // Process a user message and generate a therapist response with audio
  Future<Map<String, dynamic>> processUserMessageWithAudio(
      String userMessage) async {
    bool voiceServiceAvailable = true;

    try {
      // Check if voice service is initialized (do this on main thread since it's quick)
      try {
        await _voiceService.initialize();
      } catch (e) {
        if (kDebugMode) {
          print('Voice service not available: $e');
        }
        voiceServiceAvailable = false;
      }

      // Get text response (already optimized with compute)
      final textResponse = await processUserMessage(userMessage);

      // Process audio generation in parallel to UI updates
      String? audioPath;
      if (voiceServiceAvailable) {
        try {
          // Get token for authentication in the background isolate
          final prefs = await SharedPreferences.getInstance();
          final authToken = prefs.getString('auth_token');

          // Use compute to move audio generation to a separate isolate
          audioPath = await compute(_generateAudioInBackground, {
            'text': textResponse,
            'voiceServiceUrl': _voiceService.apiUrl,
            'authToken': authToken
          });

          // If background generation failed, try direct generation as fallback
          if (audioPath == null) {
            if (kDebugMode) {
              print(
                  'Background audio generation failed, trying direct generation');
            }
            audioPath = await _voiceService.generateAudio(textResponse,
                isAiSpeaking: true);
          }
        } catch (e) {
          if (kDebugMode) {
            print('Warning: Could not generate audio in background: $e');
            print('Trying direct audio generation as fallback...');
          }

          // Try with direct generation as a fallback
          try {
            audioPath = await _voiceService.generateAudio(textResponse,
                isAiSpeaking: true);
          } catch (fallbackError) {
            if (kDebugMode) {
              print('Fallback audio generation also failed: $fallbackError');
            }
          }
        }
      }

      // Return response with audio path if available
      return {
        'text': textResponse,
        'audioPath': audioPath,
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error processing user message with audio: $e');
      }

      return {
        'text':
            "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?",
        'audioPath': null,
      };
    }
  }

  // Generate audio in a background isolate
  static Future<String?> _generateAudioInBackground(
      Map<String, dynamic> params) async {
    final text = params['text'] as String;
    final apiUrl = params['voiceServiceUrl'] as String;
    final authToken = params['authToken'] as String?;

    try {
      print(
          '[DEBUG] Background audio generation started for text: "${text.substring(0, min(20, text.length))}..."');

      // Force the correct backend URL regardless of what's passed in
      final backendUrl = 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';

      print('[DEBUG] Using API URL: $backendUrl');
      print(
          '[DEBUG] Authentication token available: ${authToken != null ? 'Yes' : 'No'}');

      // Simple audio generation using HTTP directly since we can't use the VoiceService in isolate
      final uri = Uri.parse('$backendUrl/voice/synthesize');
      final headers = {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

      print('[DEBUG] Sending request to: $uri');
      final stopwatch = Stopwatch()..start();
      final response = await http.post(uri,
          headers: headers, body: jsonEncode({'text': text, 'voice': 'sage'}));
      stopwatch.stop();

      print(
          '[DEBUG] Response received in ${stopwatch.elapsedMilliseconds}ms with status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[DEBUG] Response body: ${response.body}');

        // Use the correct backend URL for the audio file URL
        String audioUrl = data['url'];
        if (audioUrl != null && audioUrl.startsWith('/')) {
          audioUrl = '$backendUrl$audioUrl';
        }
        print('[DEBUG] Successfully generated audio, URL: $audioUrl');
        return audioUrl;
      } else {
        print(
            '[DEBUG] Audio generation failed with status code: ${response.statusCode}');
        print('[DEBUG] Response body: ${response.body}');
        print('[DEBUG] Response headers: ${response.headers}');
      }
    } catch (e) {
      print('[DEBUG] Error generating audio in background: $e');
      print('[DEBUG] Error type: ${e.runtimeType}');

      if (e is SocketException) {
        print(
            '[DEBUG] Socket exception details: ${e.message}, address: ${e.address}, port: ${e.port}');
      } else if (e is http.ClientException) {
        print('[DEBUG] HTTP client exception: ${e.message}');
      } else if (e is FormatException) {
        print(
            '[DEBUG] Format exception (likely JSON parsing error): ${e.message}');
      } else if (e is TimeoutException) {
        print('[DEBUG] Request timed out');
      }
    }

    print(
        '[DEBUG] Background audio generation returned null - falling back to direct generation');
    return null;
  }

  // Process a user message and get AI response
  Future<String> processUserMessage(String userMessage) async {
    try {
      // Check if the message is empty
      if (userMessage.trim().isEmpty) {
        return "I didn't catch that. Could you please repeat?";
      }

      // Process through conversation graph to get context
      final graphResult =
          await _conversationGraph.processUserInput(userMessage);

      debugPrint(
          '[DEBUG] Graph analysis complete. State: ${graphResult['state'] ?? 'unknown'}');

      // Check cache for existing response
      if (_responseCache.containsKey(userMessage)) {
        debugPrint('[DEBUG] Cache hit! Using cached response');
        return _responseCache[userMessage]!;
      }

      // Build the request payload
      final systemPrompt = _buildSystemPrompt(graphResult);
      final payload = {
        'message': userMessage,
        'system_prompt': systemPrompt,
      };

      // Make the API call
      try {
        debugPrint('[DEBUG] Preparing to call API endpoint: /ai/response');

        // Log API endpoint being used
        debugPrint(
            '[DEBUG] Using API URL: https://ai-therapist-backend-fuukqlcsha-uc.a.run.app/ai/response');

        final response = await _apiClient.post('/ai/response', body: payload);

        if (response != null && response.containsKey('response')) {
          debugPrint('[DEBUG] API call successful. Response received.');

          // Process insights and save to memory in background
          _processInsightsAndSaveMemory(userMessage, response, graphResult);

          // Cache the response for future use
          _responseCache[userMessage] = response['response'];

          // Limit cache size to avoid memory issues
          if (_responseCache.length > 100) {
            // Remove oldest entries when cache gets too large
            final oldestKey = _responseCache.keys.first;
            _responseCache.remove(oldestKey);
          }

          return response['response'];
        } else {
          debugPrint(
              '[DEBUG] Invalid response format. Response was: $response');
          debugPrint(
              '[DEBUG] Response keys: ${response?.keys.toList() ?? "null"}');
          debugPrint(
              '[DEBUG] Response type: ${response?.runtimeType ?? "null"}');
        }
      } catch (e, stackTrace) {
        debugPrint('[DEBUG] API Error: $e');
        debugPrint('[DEBUG] Error type: ${e.runtimeType}');
        debugPrint('[DEBUG] Stack Trace: $stackTrace');

        // More detailed error reporting
        if (e is SocketException) {
          debugPrint(
              '[DEBUG] Network error: ${e.message}. Address: ${e.address}, Port: ${e.port}');
        } else if (e is TimeoutException) {
          debugPrint('[DEBUG] Request timed out');
        } else if (e is ApiException) {
          debugPrint(
              '[DEBUG] API Exception status code: ${e.statusCode}, message: ${e.message}');
        } else if (e is FormatException) {
          debugPrint(
              '[DEBUG] Format exception (likely JSON parsing error): ${e.message}');
        } else if (e is HttpException) {
          debugPrint('[DEBUG] HTTP exception: ${e.message}');
        }

        debugPrint(
            '[DEBUG] Falling back to template-based response inside CATCH');
        return "Fallback due to API Error: ${e.runtimeType} - ${e.toString()}";
      }

      // Generate fallback response in background if API call failed or response was invalid
      debugPrint(
          '[DEBUG] Generating fallback response for message: "${userMessage.substring(0, userMessage.length > 20 ? 20 : userMessage.length)}..." OUTSIDE CATCH');
      debugPrint(
          '[DEBUG] API call didn\'t throw but didn\'t return valid response');

      final fallbackResponse = await compute(_generateFallbackResponse,
          {'message': userMessage, 'templates': _responseTemplates});

      // Cache fallback response too
      _responseCache[userMessage] = fallbackResponse;

      return fallbackResponse;
    } catch (e, stackTrace) {
      debugPrint('[DEBUG] General error processing message: $e');
      debugPrint('[DEBUG] Error type: ${e.runtimeType}');
      debugPrint('[DEBUG] Outer Stack Trace: $stackTrace');
      return "Fallback due to General Error: ${e.runtimeType} - ${e.toString()}";
    }
  }

  // Build system prompt based on graph analysis results
  String _buildSystemPrompt(Map<String, dynamic> graphResult) {
    String prompt = _systemPrompt;

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

  // Background method to get memory context
  static Future<String> _getMemoryContextBackground(
      MemoryService memoryService) async {
    try {
      return await memoryService.getMemoryContext();
    } catch (e) {
      print('Error getting memory context in background: $e');
      return '';
    }
  }

  // Background method to process user input through graph
  static Future<Map<String, dynamic>> _processUserInputBackground(
      Map<String, dynamic> params) async {
    try {
      final graph = params['graph'] as TherapyConversationGraph;
      final userMessage = params['userMessage'] as String;
      return await graph.processUserInput(userMessage);
    } catch (e) {
      print('Error processing user input in background: $e');
      return {};
    }
  }

  // Process insights and save to memory (don't await this to avoid blocking)
  Future<void> _processInsightsAndSaveMemory(String userMessage,
      Map<String, dynamic> response, Map<String, dynamic> graphResult) async {
    try {
      // Extract any insights detected in the response
      if (response.containsKey('insights') && response['insights'] != null) {
        final insights = response['insights'];
        if (insights is List && insights.isNotEmpty) {
          for (final insight in insights) {
            await _memoryService.addInsight(insight, 'ai');
          }
        }
      }

      // Save interaction to memory
      await _memoryService.addInteraction(userMessage, response['response'], {
        'state': graphResult['state'] ?? 'exploration',
        'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
        'topics': graphResult['analysis']?['topics'] ?? [],
      });

      // Extract any detected emotional state
      if (graphResult.containsKey('analysis') &&
          graphResult['analysis'].containsKey('emotion') &&
          graphResult['analysis'].containsKey('emotionIntensity')) {
        await _memoryService.updateEmotionalState(
            graphResult['analysis']['emotion'],
            graphResult['analysis']['emotionIntensity'],
            userMessage.length > 50
                ? userMessage.substring(0, 50) + '...'
                : userMessage);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing insights and saving memory: $e');
      }
    }
  }

  // Generate fallback response in background
  static Future<String> _generateFallbackResponse(
      Map<String, dynamic> params) async {
    final userMessage = params['message'] as String;
    final responseTemplates = params['templates'] as Map<String, List<String>>;

    final lowerMessage = userMessage.toLowerCase();

    // Generate a seed based on the message content for more varied responses
    int seed = 0;
    for (int i = 0; i < userMessage.length; i++) {
      seed += userMessage.codeUnitAt(i);
    }

    // Find matching keywords with better detection
    List<String> matchedKeywords = [];
    for (final keyword in responseTemplates.keys) {
      if (lowerMessage.contains(keyword)) {
        matchedKeywords.add(keyword);
      }
    }

    String response = '';

    // If we found matches, combine elements from multiple templates
    if (matchedKeywords.isNotEmpty) {
      // Get a response from each matched category
      List<String> possibleResponses = [];
      for (final keyword in matchedKeywords) {
        final responses = responseTemplates[keyword]!;
        final randomIndex = (seed + keyword.length) % responses.length;
        possibleResponses.add(responses[randomIndex]);
      }

      // If multiple matches, pick based on seed, otherwise use the single match
      final responseIndex = seed % possibleResponses.length;
      response = possibleResponses[responseIndex];
    } else {
      // For more dynamic responses when no specific keyword is matched
      List<String> defaultResponses = [
        "Thank you for sharing that with me. Can you tell me more about how that makes you feel?",
        "I appreciate you opening up. How long have you been experiencing this?",
        "I'm listening and I'm here to support you. What strategies have you tried so far?",
        "That sounds challenging. Could you elaborate on what aspects are most difficult for you?",
        "I understand. How have these feelings been affecting your daily life and relationships?",
        "I'm curious to know more about when you first noticed this pattern.",
        "That's an important insight. How would you like things to be different?",
        "Thank you for trusting me with this. What would be most helpful for you right now?",
        "I'm wondering how this connects to other areas of your life?",
        "Let's explore this further. What thoughts come up for you when you experience this?"
      ];

      final randomIndex = seed % defaultResponses.length;
      response = defaultResponses[randomIndex];
    }

    return response;
  }

  // End therapy session and generate a summary
  Future<Map<String, dynamic>> endSession(
      List<Map<String, dynamic>> messages) async {
    try {
      if (kDebugMode) {
        print('Making API call to end_session with payload: ${json.encode({
              'messages_count': messages.length,
              'system_prompt_length': _systemPrompt.length
            })}');
      }

      // Make API call to end session and get summary
      try {
        final response = await _apiClient.post('/therapy/end_session',
            body: {'messages': messages, 'system_prompt': _systemPrompt});

        if (response != null) {
          if (kDebugMode) {
            print(
                'Received response from end_session API: ${json.encode(response)}');
          }

          if (kDebugMode) {
            print('Session summary generated successfully');
          }

          return response;
        } else {
          if (kDebugMode) {
            print('Received null response from end_session API');
          }

          // Try fallback summary generation
          return _generateFallbackSummary(messages);
        }
      } catch (apiError) {
        if (kDebugMode) {
          print('API error in endSession: $apiError');
          print('Error type: ${apiError.runtimeType}');

          if (apiError is SocketException) {
            print(
                'Socket exception: ${apiError.message}, address: ${apiError.address}, port: ${apiError.port}');
          } else if (apiError is HttpException) {
            print('HTTP exception: ${apiError.message}');
          } else if (apiError is TimeoutException) {
            print('Timeout exception');
          } else if (apiError is FormatException) {
            print('Format exception: ${apiError.message}');
          }
        }

        // Generate a local fallback summary
        return _generateFallbackSummary(messages);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error ending session: $e');
        print('Error type: ${e.runtimeType}');
      }

      // Return a user-friendly error message
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

  // Generate a fallback summary when the API call fails
  Map<String, dynamic> _generateFallbackSummary(
      List<Map<String, dynamic>> messages) {
    try {
      if (kDebugMode) {
        print('Generating fallback summary for ${messages.length} messages');
      }

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
        'challenges',
        'communication',
        'personal growth'
      ];

      final List<String> detectedTopics = [];
      for (final topic in possibleTopics) {
        if (userMessages
            .any((msg) => msg.toLowerCase().contains(topic.toLowerCase()))) {
          detectedTopics.add(topic);
        }
      }

      final summary = 'Thank you for your session today. ' +
          'We discussed ${detectedTopics.isEmpty ? 'some important topics' : 'topics including ${detectedTopics.take(3).join(', ')}'}, ' +
          'and explored ways to approach these areas in your life. ' +
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
      if (kDebugMode) {
        print('Error generating fallback summary: $e');
      }

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

  // Get the current therapy state
  TherapyState? getCurrentState() {
    return _conversationGraph.currentState;
  }

  // Get available therapeutic tools for the current state
  List<String> getAvailableTools() {
    return _conversationGraph.currentNode.tools;
  }

  // Check the status of all backend services
  Future<Map<String, dynamic>> checkServiceStatus() async {
    try {
      debugPrint('[DEBUG] Checking service status...');
      final apiClient = serviceLocator<ApiClient>();
      final backendUrl = 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';

      try {
        // Make a request to the service status endpoint
        debugPrint('[DEBUG] Making request to ${backendUrl}/llm/status');
        final response = await apiClient.get('/llm/status');

        if (response != null) {
          debugPrint('[DEBUG] Service status response: $response');
          return response as Map<String, dynamic>;
        } else {
          debugPrint('[DEBUG] Got null response from service status endpoint');
          return {
            'error': 'No response received from status endpoint',
            'status': 'offline'
          };
        }
      } catch (e) {
        debugPrint('[DEBUG] Error checking service status: $e');
        debugPrint('[DEBUG] Error type: ${e.runtimeType}');

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
        } else if (e is ApiException) {
          return {
            'error': 'API error: ${e.message}',
            'status': 'error',
            'status_code': e.statusCode,
            'details': e.message
          };
        }

        return {'error': 'Unknown error: ${e.toString()}', 'status': 'error'};
      }
    } catch (e) {
      debugPrint('[DEBUG] General error in checkServiceStatus: $e');
      return {
        'error': 'Error checking service status: ${e.toString()}',
        'status': 'error'
      };
    }
  }

  // Set user preferences in memory
  Future<void> setUserPreference(String key, dynamic value) async {
    await _memoryService.updateUserPreference(key, value);
  }

  // Get therapeutic techniques for current conversation state
  List<String> getCurrentTechniques() {
    return _conversationGraph.currentNode.techniques;
  }

  // Log emotional state explicitly
  Future<void> logEmotionalState(
      String emotion, double intensity, String trigger) async {
    await _memoryService.updateEmotionalState(emotion, intensity, trigger);
  }
}
