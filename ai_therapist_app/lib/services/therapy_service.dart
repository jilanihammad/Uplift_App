import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:async';
import '../di/service_locator.dart';
import 'voice_service.dart';
import 'memory_service.dart';
import '../services/therapy_graph_service.dart';
import '../services/therapy_conversation_graph.dart';
import '../models/conversation_memory.dart';
import '../data/datasources/remote/api_client.dart';

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
      messages: (json['messages'] as List).map((m) => TherapyServiceMessage.fromJson(m)).toList(),
      initialMood: json['initialMood'] != null ? 
          TherapyMood.values.firstWhere((e) => e.toString().split('.').last == json['initialMood']) : null,
      finalMood: json['finalMood'] != null ? 
          TherapyMood.values.firstWhere((e) => e.toString().split('.').last == json['finalMood']) : null,
      summary: json['summary'],
      actionItems: json['actionItems'] != null ? List<String>.from(json['actionItems']) : null,
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
  final VoiceService _voiceService = serviceLocator<VoiceService>();
  
  // Memory service for maintaining context
  final MemoryService _memoryService = serviceLocator<MemoryService>();
  
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
      print('Therapeutic approach set to: ${approach.toString().split('.').last}');
    }
  }
  
  // Process a user message and generate a therapist response with audio
  Future<Map<String, dynamic>> processUserMessageWithAudio(String userMessage) async {
    bool voiceServiceAvailable = true;
    
    try {
      // Check if voice service is initialized
      try {
        await _voiceService.initialize();
      } catch (e) {
        if (kDebugMode) {
          print('Voice service not available: $e');
        }
        voiceServiceAvailable = false;
      }
      
      // Get text response
      final textResponse = await processUserMessage(userMessage);
      
      // Only attempt audio generation if voice service is available
      if (voiceServiceAvailable) {
        try {
          // Generate audio for the response
          final audioPath = await _voiceService.generateAudio(textResponse, isAiSpeaking: true);
          
          return {
            'text': textResponse,
            'audioPath': audioPath,
          };
        } catch (e) {
          if (kDebugMode) {
            print('Warning: Could not generate audio: $e');
          }
        }
      }
      
      // Return text-only response if audio generation failed or voice service is unavailable
      return {
        'text': textResponse,
        'audioPath': null,
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error processing user message with audio: $e');
      }
      
      return {
        'text': "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?",
        'audioPath': null,
      };
    }
  }
  
  // Process a user message and generate a therapist response
  Future<String> processUserMessage(String userMessage) async {
    try {
      // Step 1: Retrieve memory context for the conversation
      final memoryContext = await _memoryService.getMemoryContext();
      
      // Step 2: Process user input through the conversation graph
      Map<String, dynamic> graphResult = await _conversationGraph.processUserInput(userMessage);
      
      // Step 3: Update the system prompt with graph-derived prompt if available
      String effectiveSystemPrompt = _systemPrompt;
      if (graphResult.containsKey('prompt') && graphResult['prompt'] != null) {
        // Combine the base system prompt with the graph-specific prompt
        effectiveSystemPrompt = '$_systemPrompt\n\n${graphResult['prompt']}';
      }
      
      // Step 4: Add memory context to the system prompt
      if (memoryContext.isNotEmpty) {
        effectiveSystemPrompt = '$effectiveSystemPrompt\n\nRELEVANT CONTEXT FROM PREVIOUS SESSIONS:\n$memoryContext';
      }
      
      // Step 5: Use the API client to make a real API call to an LLM service
      final apiClient = serviceLocator<ApiClient>();
      
      // Prepare the payload for the API with enhanced context
      final payload = {
        'message': userMessage,
        'system_prompt': effectiveSystemPrompt,
        'conversation_state': graphResult['state'] ?? 'exploration',
        'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
        'topics': graphResult['analysis']?['topics'] ?? [],
        'approach': _therapeuticApproach.toString().split('.').last,
      };
      
      // Make the actual API call
      try {
        final response = await apiClient.post('/api/v1/therapy/message', body: payload);
        
        if (response != null && response.containsKey('response')) {
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
          await _memoryService.addInteraction(
            userMessage, 
            response['response'], 
            {
              'state': graphResult['state'] ?? 'exploration',
              'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
              'topics': graphResult['analysis']?['topics'] ?? [],
            }
          );
          
          // Extract any detected emotional state
          if (graphResult.containsKey('analysis') && 
              graphResult['analysis'].containsKey('emotion') && 
              graphResult['analysis'].containsKey('emotionIntensity')) {
            await _memoryService.updateEmotionalState(
              graphResult['analysis']['emotion'],
              graphResult['analysis']['emotionIntensity'],
              userMessage.length > 50 ? userMessage.substring(0, 50) + '...' : userMessage
            );
          }
          
          return response['response'];
        }
      } catch (e) {
        if (kDebugMode) {
          print('API Error: $e');
          print('Falling back to template-based response');
        }
        // Fall back to template-based response if the API call fails
      }
      
      // Fall back to the template-based approach as before
      final lowerMessage = userMessage.toLowerCase();
      
      // Generate a seed based on the message content for more varied responses
      int seed = 0;
      for (int i = 0; i < userMessage.length; i++) {
        seed += userMessage.codeUnitAt(i);
      }
      
      // Find matching keywords with better detection
      List<String> matchedKeywords = [];
      for (final keyword in _responseTemplates.keys) {
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
          final responses = _responseTemplates[keyword]!;
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
        
        // Use the seed to select a response, making it seem more dynamic
        final randomIndex = seed % defaultResponses.length;
        response = defaultResponses[randomIndex];
      }
      
      // Save the interaction to memory even for template responses
      await _memoryService.addInteraction(
        userMessage,
        response,
        {
          'state': graphResult['state'] ?? 'exploration',
          'fromTemplate': true,
        }
      );
      
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('Error processing user message: $e');
      }
      return "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?";
    }
  }
  
  // End a therapy session and generate a summary
  Future<Map<String, dynamic>> endSession(List<Map<String, dynamic>> messages) async {
    try {
      if (kDebugMode) {
        print('Ending therapy session with ${messages.length} messages');
      }
      
      // Retrieve memory context for enhanced summary generation
      final memoryContext = await _memoryService.getMemoryContext();
      
      // Use the API client to make a real API call
      final apiClient = serviceLocator<ApiClient>();
      
      // Clean up messages to ensure they're properly formatted for the API
      final cleanedMessages = messages.map((msg) => {
        'content': msg['content'] ?? '',
        'isUser': msg['isUser'] ?? false,
        'timestamp': msg['timestamp'] ?? DateTime.now().toIso8601String(),
      }).toList();
      
      // Prepare the payload for the API with enhanced context
      final payload = {
        'messages': cleanedMessages,
        'system_prompt': _systemPrompt,
        'memory_context': memoryContext,
        'therapeutic_approach': _therapeuticApproach.toString().split('.').last,
        'visited_nodes': _conversationGraph.currentState?.metadata['visited_nodes'] ?? [],
      };
      
      if (kDebugMode) {
        print('Making API call to end_session with payload: ${jsonEncode(payload)}');
      }
      
      // Make the actual API call
      try {
        final response = await apiClient.post('/api/v1/therapy/end_session', body: payload);
        
        if (kDebugMode) {
          print('Received response from end_session API: $response');
        }
        
        if (response != null) {
          // Extract therapeutic goals if available
          if (response.containsKey('goals') && response['goals'] is List) {
            await _memoryService.updateTherapeuticGoals(List<String>.from(response['goals']));
          }
          
          // Save significant insights
          if (response.containsKey('insights') && response['insights'] is List) {
            for (final insight in response['insights']) {
              await _memoryService.addInsight(insight, 'session_summary');
            }
          }
          
          return {
            'summary': response['summary'] ?? "Session summary not available.",
            'actionItems': response.containsKey('action_items') && response['action_items'] is List
                ? List<String>.from(response['action_items'])
                : [],
            'insights': response.containsKey('insights') && response['insights'] is List
                ? List<String>.from(response['insights'])
                : []
          };
        } else {
          throw Exception("API response was null or invalid");
        }
      } catch (e) {
        if (kDebugMode) {
          print('API Error in endSession: $e');
          
          // For debugging in Chrome, try a direct HTTP call to see the response
          try {
            final backendUrl = kDebugMode 
                ? 'http://localhost:8000' 
                : 'https://api-fuukqlcsha-uc.a.run.app';
            
            print('Attempting direct HTTP call to: $backendUrl/api/v1/therapy/end_session');
            
            final response = await http.post(
              Uri.parse('$backendUrl/api/v1/therapy/end_session'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            );
            
            print('Direct HTTP call status code: ${response.statusCode}');
            print('Direct HTTP call response: ${response.body}');
            
            if (response.statusCode >= 200 && response.statusCode < 300) {
              // If direct call succeeds, try to use its response
              final responseBody = jsonDecode(response.body);
              return {
                'summary': responseBody['summary'] ?? "Session summary generated via direct API call.",
                'actionItems': responseBody.containsKey('action_items') && responseBody['action_items'] is List
                    ? List<String>.from(responseBody['action_items'])
                    : [],
                'insights': responseBody.containsKey('insights') && responseBody['insights'] is List
                    ? List<String>.from(responseBody['insights'])
                    : []
              };
            }
          } catch (httpError) {
            print('Direct HTTP call error: $httpError');
          }
          
          print('Falling back to template-based summary');
        }
        // Fall back to template if API call fails
      }
      
      // Fallback if API call fails
      return {
        'summary': "In this session, we discussed various aspects of your current challenges and explored potential coping strategies.",
        'actionItems': [
          "Practice deep breathing for 5 minutes when feeling anxious",
          "Keep a mood journal to track emotional patterns",
          "Schedule one self-care activity this week"
        ],
        'insights': [
          "You've been making progress in recognizing your triggers",
          "Your self-awareness is a significant strength",
          "Small consistent steps can lead to meaningful change"
        ]
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error ending session: $e');
      }
      return {
        'summary': "Session summary not available.",
        'actionItems': [],
        'insights': []
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
  
  // Set user preferences in memory
  Future<void> setUserPreference(String key, dynamic value) async {
    await _memoryService.updateUserPreference(key, value);
  }
  
  // Get therapeutic techniques for current conversation state
  List<String> getCurrentTechniques() {
    return _conversationGraph.currentNode.techniques;
  }
  
  // Log emotional state explicitly
  Future<void> logEmotionalState(String emotion, double intensity, String trigger) async {
    await _memoryService.updateEmotionalState(emotion, intensity, trigger);
  }
}