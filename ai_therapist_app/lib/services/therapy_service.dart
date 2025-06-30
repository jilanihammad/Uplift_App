import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'voice_service.dart';
import 'memory_service.dart';
import 'memory_manager.dart';
import 'message_processor.dart';
import 'audio_generator.dart';
import 'conversation_flow_manager.dart';
import '../services/therapy_graph_service.dart';
import '../services/therapy_conversation_graph.dart';
import '../models/conversation_memory.dart';
import '../di/interfaces/i_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger_util.dart';
import '../config/app_config.dart';
import 'enhanced_vad_manager.dart';
import '../di/interfaces/i_therapy_service.dart';
import '../models/therapy_message.dart';
import '../models/user_profile.dart';

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

// Enhanced therapy service with refactored responsibilities
class TherapyService implements ITherapyService {
  // System prompt for the AI therapist
  String _systemPrompt = '';

  // Initialization status
  bool _isInitialized = false;

  // Refactored components for better separation of concerns
  final MessageProcessor _messageProcessor;
  final AudioGenerator _audioGenerator;
  final MemoryManager _memoryManager;
  final ConversationFlowManager _conversationFlowManager;

  // Enhanced VAD configuration
  bool _useEnhancedVAD = false; // Default to false for backwards compatibility
  EnhancedVADManager? _enhancedVADManager;

  // Constructor with injected dependencies
  TherapyService({
    required MessageProcessor messageProcessor,
    required AudioGenerator audioGenerator,
    required MemoryManager memoryManager,
    required IApiClient apiClient,
  })  : _messageProcessor = messageProcessor,
        _audioGenerator = audioGenerator,
        _memoryManager = memoryManager,
        _conversationFlowManager = ConversationFlowManager();

  // Method to initialize the therapy service
  @override
  Future<void> init() async {
    if (_isInitialized) return;

    // Initialize all components using their lazy initialization methods
    await _memoryManager.initializeOnlyIfNeeded();
    await _audioGenerator.initializeOnlyIfNeeded();
    await _conversationFlowManager.initializeOnlyIfNeeded();

    _isInitialized = true;
    log.i('Therapy service initialized with all components');
  }

  // Initialize only if needed
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }

  // Check if initialized
  @override
  bool get isInitialized => _isInitialized;

  // Set the therapist style system prompt
  @override
  void setTherapistStyle(String systemPrompt) {
    _systemPrompt = systemPrompt;
  }

  // Set the therapeutic approach
  void setTherapeuticApproach(TherapeuticApproach approach) {
    _conversationFlowManager.setTherapeuticApproach(approach);
  }

  // Process a user message and generate a therapist response with streaming audio
  // This will start playing audio as soon as possible while it's still downloading
  @override
  Future<Map<String, dynamic>> processUserMessageWithStreamingAudio(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
  }) async {
    try {
      // Measure performance
      final stopwatch = Stopwatch()..start();

      log.d('Starting real-time streaming TTS for user message: "$userMessage"');
      
      // Use streaming approach instead of waiting for complete response
      final result = await _processUserMessageWithRealTimeStreaming(
        userMessage,
        history,
        onTTSPlaybackComplete: onTTSPlaybackComplete,
        onTTSError: onTTSError,
      );

      stopwatch.stop();
      log.i('Total real-time streaming processing took ${stopwatch.elapsedMilliseconds}ms');

      return result;
    } catch (e) {
      log.e('Error processing user message with real-time streaming', e);
      log.i('Falling back to traditional TTS processing...');
      
      // Fallback to traditional processing method
      try {
        final fallbackResult = await _processFallbackTTS(
          userMessage,
          history,
          onTTSPlaybackComplete: onTTSPlaybackComplete,
          onTTSError: onTTSError,
        );
        return fallbackResult;
      } catch (fallbackError) {
        log.e('Fallback processing also failed', fallbackError);
        onTTSError('Error processing message: ${e.toString()}');
        return {
          'text': "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?",
          'audioPath': null,
        };
      }
    }
  }

  // NEW: Real-time streaming method that doesn't wait for complete response
  Future<Map<String, dynamic>> _processUserMessageWithRealTimeStreaming(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
  }) async {
    try {
      log.d('Getting memory context for streaming...');
      // Get memory context
      final memoryContext = await _memoryManager.getMemoryContext();
      
      log.d('Processing user input through conversation graph for streaming...');
      // Process through conversation graph to get context
      final graphResult = await _conversationFlowManager.processUserInput(userMessage);

      // Build system prompt with context
      final systemPrompt = _buildSystemPromptWithContext(_systemPrompt, memoryContext, graphResult);
      
      // Prepare conversation history for WebSocket streaming
      List<Map<String, dynamic>> conversationHistory = [];
      if (history.isNotEmpty) {
        conversationHistory = history.map((msg) => <String, dynamic>{
          'role': msg['isUser'] == 'true' ? 'user' : 'assistant',
          'content': msg['content'] ?? '',
        }).toList();
      }

      log.d('Starting WebSocket streaming to LLM...');
      // Get streaming response from LLM via WebSocket
      final aiResponseStream = _messageProcessor.streamMessage(
        userMessage,
        systemPrompt,
        graphResult,
        history: conversationHistory,
      );

      String fullResponse = '';
      bool ttsStarted = false;
      
      // Create a broadcast stream to share between TTS processing and response collection
      final broadcastStream = aiResponseStream.asBroadcastStream();
      
      // Start TTS processing in parallel
      final ttsProcessingFuture = _audioGenerator.processAIResponseWithStreamingTTS(
        aiResponseStream: broadcastStream,
        useTherapeuticProcessing: true, // Use therapeutic sentence processing
        onTTSStart: () {
          if (!ttsStarted) {
            ttsStarted = true;
            log.i('🎵 TTS streaming started - first audio playing!');
          }
        },
        onTTSComplete: () async {
          log.i('🎵 All TTS streaming completed');
          await onTTSPlaybackComplete();
        },
        onError: (error) {
          log.e('TTS streaming error: $error');
          onTTSError(error);
        },
      );

      // Collect the full response for memory storage and return
      final responseCollectionFuture = () async {
        await for (final event in broadcastStream) {
          if (event['type'] == 'chunk' && event.containsKey('content')) {
            fullResponse += event['content'] as String;
          } else if (event['type'] == 'done') {
            break;
          } else if (event['type'] == 'error') {
            throw Exception('AI streaming error: ${event['detail']}');
          }
        }
      }();

      // Wait for both TTS processing and response collection to complete
      await Future.wait([ttsProcessingFuture, responseCollectionFuture]);
      
      // Save to memory in background after completion
      if (fullResponse.isNotEmpty) {
        final responseMap = {'response': fullResponse};
        _memoryManager.processInsightsAndSaveMemory(
            userMessage, responseMap, graphResult);
      }

      log.i('Real-time streaming completed. Full response length: ${fullResponse.length} characters');

      return {
        'text': fullResponse,
        'audioPath': 'streaming', // Indicate streaming was used
        'streaming': true,
      };
    } catch (e) {
      log.e('Error in real-time streaming processing', e);
      rethrow;
    }
  }

  // Fallback TTS method using traditional approach
  Future<Map<String, dynamic>> _processFallbackTTS(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
  }) async {
    log.i('Using fallback TTS processing (traditional method)');
    
    try {
      // Get complete text response first (traditional approach)
      final textResponse = await processUserMessage(userMessage, history: history);
      
      if (textResponse.trim().isEmpty) {
        log.w('Empty text response from fallback processing');
        onTTSError("AI response was empty.");
        return {
          'text': null,
          'audioPath': null,
        };
      }

      // Generate audio using traditional streaming method
      String? audioPath;
      try {
        audioPath = await _audioGenerator.generateAndStreamAudio(
          textResponse,
          onDone: onTTSPlaybackComplete,
          onError: onTTSError,
        );
      } catch (e) {
        log.w('Warning: Could not generate/stream audio in fallback', e);
        onTTSError('Failed to generate/stream audio: ${e.toString()}');
      }

      return {
        'text': textResponse,
        'audioPath': audioPath,
        'fallback': true, // Indicate fallback was used
      };
    } catch (e) {
      log.e('Error in fallback TTS processing', e);
      rethrow;
    }
  }

  // Process a user message and generate a therapist response with audio
  Future<Map<String, dynamic>> processUserMessageWithAudio(
      String userMessage) async {
    try {
      // Measure performance
      final stopwatch = Stopwatch()..start();

      // Get text response
      final textResponse = await processUserMessage(userMessage);
      final textProcessingTime = stopwatch.elapsedMilliseconds;
      log.i('Text processing took ${textProcessingTime}ms');

      // Generate audio WITHOUT playing it - let the UI layer handle playback
      String? audioPath;
      try {
        // Use the new method with autoPlay=false to avoid double playback
        audioPath = await _audioGenerator
            .generateAndOptionallyPlayAudio(textResponse, autoPlay: false);
      } catch (e) {
        log.w('Warning: Could not generate audio', e);
      }

      stopwatch.stop();
      log.i(
          'Total message processing with audio took ${stopwatch.elapsedMilliseconds}ms');

      // Return response with audio path if available
      return {
        'text': textResponse,
        'audioPath': audioPath,
      };
    } catch (e) {
      log.e('Error processing user message with audio', e);

      return {
        'text':
            "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?",
        'audioPath': null,
      };
    }
  }

  // Process a user message and get AI response
  @override
  Future<String> processUserMessage(String userMessage,
      {List<Map<String, String>>? history}) async {
    try {
      log.d('TherapyService.processUserMessage called with: "$userMessage"');
      
      // Check if the message is empty
      if (userMessage.trim().isEmpty) {
        log.w('Empty user message received');
        return "I didn't catch that. Could you please repeat?";
      }

      log.d('Processing user input through conversation graph...');
      // Process through conversation graph to get context
      final graphResult =
          await _conversationFlowManager.processUserInput(userMessage);

      log.d(
          'Graph analysis complete. State: ${graphResult['state'] ?? 'unknown'}');

      log.d('Getting memory context...');
      // Get memory context
      final memoryContext = await _memoryManager.getMemoryContext();
      log.d('Memory context retrieved: ${memoryContext.length} characters');

      log.d('Processing message through MessageProcessor...');
      // Process message using the MessageProcessor
      final aiResponse = await _messageProcessor.processMessage(
          userMessage,
          _buildSystemPromptWithContext(
              _systemPrompt, memoryContext, graphResult),
          graphResult,
          history: history);

      log.d('AI response received: "${aiResponse.substring(0, aiResponse.length > 50 ? 50 : aiResponse.length)}..."');

      // Process response insights and save to memory in background
      final responseMap = {'response': aiResponse};
      _memoryManager.processInsightsAndSaveMemory(
          userMessage, responseMap, graphResult);

      log.d('TherapyService.processUserMessage completed successfully');
      return aiResponse;
    } catch (e, stackTrace) {
      log.e('General error processing message', e, stackTrace);
      debugPrint('[TherapyService] ERROR in processUserMessage: $e');
      debugPrint('[TherapyService] Stack trace: $stackTrace');
      return "I'm sorry, I'm having trouble understanding. Could you try phrasing that differently?";
    }
  }

  // Build system prompt with context and graph information
  String _buildSystemPromptWithContext(String basePrompt, String memoryContext,
      Map<String, dynamic> graphResult) {
    // Add memory context if available
    String effectiveSystemPrompt = basePrompt;
    if (memoryContext.isNotEmpty) {
      effectiveSystemPrompt =
          '$effectiveSystemPrompt\n\nRELEVANT CONTEXT FROM PREVIOUS SESSIONS:\n$memoryContext';
    }

    // Add graph-specific prompt guidance if available
    if (graphResult.containsKey('prompt') && graphResult['prompt'] != null) {
      effectiveSystemPrompt =
          '$effectiveSystemPrompt\n\n${graphResult['prompt']}';
    }

    // Add state context
    if (graphResult.containsKey('state') && graphResult['state'] != null) {
      effectiveSystemPrompt =
          '$effectiveSystemPrompt\n\nCurrent conversation state: ${graphResult['state']}';
    }

    // Add technique guidance if available
    if (graphResult.containsKey('techniques') &&
        graphResult['techniques'] != null) {
      final techniques = graphResult['techniques'];
      if (techniques is List && techniques.isNotEmpty) {
        effectiveSystemPrompt =
            '$effectiveSystemPrompt\n\nUse these therapeutic techniques: ${techniques.join(', ')}';
      }
    }

    return effectiveSystemPrompt;
  }

  // End therapy session and generate a summary
  @override
  Future<Map<String, dynamic>> endSessionWithMessages(
      List<Map<String, dynamic>> messages, {
      String? sessionTitle,
      int? userId,
    }) async {
    try {
      // Use the MessageProcessor to generate the session summary
      return await _messageProcessor.generateSessionSummary(
          messages, _systemPrompt, 
          sessionTitle: sessionTitle, 
          userId: userId);
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

  // Get the current therapy state
  TherapyState? getCurrentState() {
    return _conversationFlowManager.getCurrentState();
  }

  // Get available therapeutic tools for the current state
  List<String> getAvailableTools() {
    return _conversationFlowManager.getAvailableTools();
  }

  // Check the status of all backend services
  Future<Map<String, dynamic>> checkServiceStatus() async {
    return await _messageProcessor.checkServiceStatus();
  }

  // Set user preferences in memory
  Future<void> setUserPreference(String key, dynamic value) async {
    await _memoryManager.updateUserPreference(key, value);
  }

  // Get therapeutic techniques for current conversation state
  List<String> getCurrentTechniques() {
    return _conversationFlowManager.getCurrentTechniques();
  }

  // Log emotional state explicitly
  Future<void> logEmotionalState(
      String emotion, double intensity, String trigger) async {
    await _memoryManager.updateEmotionalState(emotion, intensity, trigger);
  }

  // ========== ITherapyService interface implementations ==========
  
  @override
  Future<String> startSession({
    required String userId,
    String? sessionType,
    Map<String, dynamic>? initialContext,
  }) async {
    // Create a new session ID
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    // TODO: Implement proper session management
    return sessionId;
  }

  @override
  Future<void> endSession(String sessionId) async {
    // TODO: Implement session end logic
  }

  @override
  Future<void> pauseSession(String sessionId) async {
    // TODO: Implement session pause logic
  }

  @override
  Future<void> resumeSession(String sessionId) async {
    // TODO: Implement session resume logic
  }

  @override
  Future<TherapyMessage> processMessage({
    required String sessionId,
    required String userMessage,
    Map<String, dynamic>? context,
  }) async {
    // TODO: Convert existing processUserMessage to return TherapyMessage
    final response = await processUserMessage(userMessage);
    return TherapyMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: response,
      isUser: false,
      timestamp: DateTime.now(),
      sequence: 0, // TODO: Implement proper sequencing
    );
  }

  @override
  Future<String> generateResponse({
    required String sessionId,
    required String userMessage,
    Map<String, dynamic>? context,
  }) async {
    return await processUserMessage(userMessage);
  }

  @override
  Future<void> updateSessionContext(String sessionId, Map<String, dynamic> context) async {
    // TODO: Implement context management
  }

  @override
  Future<Map<String, dynamic>?> getSessionContext(String sessionId) async {
    // TODO: Implement context retrieval
    return null;
  }

  @override
  Future<List<TherapyMessage>> getConversationHistory(String sessionId) async {
    // TODO: Implement conversation history retrieval
    return [];
  }

  @override
  Future<void> saveMessage(String sessionId, TherapyMessage message) async {
    // TODO: Implement message saving
  }

  @override
  Future<void> setTherapyStyle(String sessionId, String therapyStyle) async {
    // TODO: Implement therapy style setting
  }

  @override
  Future<void> updateTherapyGoals(String sessionId, List<String> goals) async {
    // TODO: Implement therapy goals update
  }

  @override
  Future<void> updateUserProfile(UserProfile profile) async {
    // TODO: Implement user profile update
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    // TODO: Implement user profile retrieval
    return null;
  }

  @override
  Future<Map<String, dynamic>> getSessionSummary(String sessionId) async {
    // TODO: Implement session summary
    return {};
  }

  @override
  Future<List<String>> getActionItems(String sessionId) async {
    // TODO: Implement action items retrieval
    return [];
  }

  @override
  Future<bool> detectCrisis(String message) async {
    // TODO: Implement crisis detection
    return false;
  }

  @override
  Future<Map<String, dynamic>> getCrisisResources() async {
    // TODO: Implement crisis resources
    return {};
  }

  @override
  Future<void> trackMoodChange(String sessionId, String mood) async {
    // TODO: Implement mood tracking
  }

  @override
  Future<Map<String, dynamic>> getProgressMetrics(String userId) async {
    // TODO: Implement progress metrics
    return {};
  }

  @override
  Future<void> initialize() async {
    await init();
  }

  @override
  void dispose() {
    // TODO: Implement cleanup
  }

  @override
  String? get currentSessionId => null; // TODO: Implement current session tracking
}
