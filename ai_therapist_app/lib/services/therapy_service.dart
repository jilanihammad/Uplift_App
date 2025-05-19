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
import 'memory_manager.dart';
import 'message_processor.dart';
import 'audio_generator.dart';
import 'conversation_flow_manager.dart';
import '../services/therapy_graph_service.dart';
import '../services/therapy_conversation_graph.dart';
import '../models/conversation_memory.dart';
import '../data/datasources/remote/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger_util.dart';
import '../config/app_config.dart';

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
class TherapyService {
  // System prompt for the AI therapist
  String _systemPrompt = '';

  // Initialization status
  bool _isInitialized = false;

  // Refactored components for better separation of concerns
  final MessageProcessor _messageProcessor;
  final AudioGenerator _audioGenerator;
  final MemoryManager _memoryManager;
  final ConversationFlowManager _conversationFlowManager;

  // Constructor with injected dependencies
  TherapyService({
    required MessageProcessor messageProcessor,
    required AudioGenerator audioGenerator,
    required MemoryManager memoryManager,
    required ApiClient apiClient,
  })  : _messageProcessor = messageProcessor,
        _audioGenerator = audioGenerator,
        _memoryManager = memoryManager,
        _conversationFlowManager = ConversationFlowManager();

  // Method to initialize the therapy service
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
  bool get isInitialized => _isInitialized;

  // Set the therapist style system prompt
  void setTherapistStyle(String systemPrompt) {
    _systemPrompt = systemPrompt;
  }

  // Set the therapeutic approach
  void setTherapeuticApproach(TherapeuticApproach approach) {
    _conversationFlowManager.setTherapeuticApproach(approach);
  }

  // Process a user message and generate a therapist response with streaming audio
  // This will start playing audio as soon as possible while it's still downloading
  Future<Map<String, dynamic>> processUserMessageWithStreamingAudio(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
  }) async {
    try {
      // Measure performance
      final stopwatch = Stopwatch()..start();

      // Get text response
      final textResponse =
          await processUserMessage(userMessage, history: history);
      final textProcessingTime = stopwatch.elapsedMilliseconds;
      log.i('Text processing took ${textProcessingTime}ms');

      if (textResponse.trim().isEmpty) {
        log.w('Empty text response from processUserMessage');
        onTTSError("AI response was empty.");
        return {
          'text': null,
          'audioPath': null,
        };
      }

      // Generate audio and play it with streaming for faster response
      String? audioPath;
      try {
        audioPath = await _audioGenerator.generateAndStreamAudio(
          textResponse,
          onDone: onTTSPlaybackComplete,
          onError: onTTSError,
        );
      } catch (e) {
        log.w('Warning: Could not generate/stream audio', e);
        onTTSError('Failed to generate/stream audio: ${e.toString()}');
        // audioPath will remain null
      }

      stopwatch.stop();
      log.i(
          'Total message processing with streaming audio took ${stopwatch.elapsedMilliseconds}ms');

      // Return response with audio path if available
      return {
        'text': textResponse,
        'audioPath': audioPath,
      };
    } catch (e) {
      log.e('Error processing user message with streaming audio', e);
      onTTSError('Error processing message: ${e.toString()}');
      return {
        'text':
            "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?",
        'audioPath': null,
      };
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
  Future<String> processUserMessage(String userMessage,
      {List<Map<String, String>>? history}) async {
    try {
      // Check if the message is empty
      if (userMessage.trim().isEmpty) {
        return "I didn't catch that. Could you please repeat?";
      }

      // Process through conversation graph to get context
      final graphResult =
          await _conversationFlowManager.processUserInput(userMessage);

      log.d(
          'Graph analysis complete. State: ${graphResult['state'] ?? 'unknown'}');

      // Get memory context
      final memoryContext = await _memoryManager.getMemoryContext();

      // Process message using the MessageProcessor
      final aiResponse = await _messageProcessor.processMessage(
          userMessage,
          _buildSystemPromptWithContext(
              _systemPrompt, memoryContext, graphResult),
          graphResult);

      // Process response insights and save to memory in background
      final responseMap = {'response': aiResponse};
      _memoryManager.processInsightsAndSaveMemory(
          userMessage, responseMap, graphResult);

      return aiResponse;
    } catch (e, stackTrace) {
      log.e('General error processing message', e, stackTrace);
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
  Future<Map<String, dynamic>> endSession(
      List<Map<String, dynamic>> messages) async {
    try {
      // Use the MessageProcessor to generate the session summary
      return await _messageProcessor.generateSessionSummary(
          messages, _systemPrompt);
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
}
