import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_therapist_app/services/langchain/custom_langchain.dart';
import 'package:ai_therapist_app/services/groq_service.dart';
import 'package:ai_therapist_app/services/langchain/prompt_templates.dart';
import 'package:ai_therapist_app/di/service_locator.dart';

/// Manages a stateful conversation graph for therapy interactions
class TherapyConversationGraph {
  // Groq service for LLM interactions
  late GroqService _groqService;
  
  // Conversation state
  final Map<String, dynamic> _state = {
    'conversation_history': <Map<String, String>>[],
    'current_phase': 'initial_greeting',
    'identified_topics': <String>[],
    'user_mood': 'neutral',
    'active_issues': <String>[],
    'suggested_exercises': <String>[],
    'therapeutic_approach': 'eclectic',
    'session_counter': 0,
  };
  
  // Graph function compiled by Langgraph
  Function? _runGraph;
  
  // Session is active
  bool _isSessionActive = false;
  
  TherapyConversationGraph() {
    _groqService = serviceLocator<GroqService>();
    _initGraph();
  }
  
  // Getter for session state
  bool get isSessionActive => _isSessionActive;
  
  // Getter for conversation history
  List<Map<String, String>> get conversationHistory => 
      List<Map<String, String>>.from(_state['conversation_history']);
  
  // Getter for current phase
  String get currentPhase => _state['current_phase'] as String;
  
  // Initialize or reset the conversation
  Future<void> initializeSession() async {
    // Reset state
    _state['conversation_history'] = <Map<String, String>>[];
    _state['current_phase'] = 'initial_greeting';
    _state['identified_topics'] = <String>[];
    _state['user_mood'] = 'neutral';
    _state['active_issues'] = <String>[];
    _state['suggested_exercises'] = <String>[];
    _state['therapeutic_approach'] = 'eclectic';
    _state['session_counter'] = (_state['session_counter'] as int) + 1;
    
    // Reset LLM memory
    _groqService.resetConversationMemory();
    
    // Set session as active
    _isSessionActive = true;
    
    if (kDebugMode) {
      print('TherapyConversationGraph: Initialized new session');
      print('TherapyConversationGraph: Session counter: ${_state['session_counter']}');
    }
  }
  
  // End the current session
  void endSession() {
    _isSessionActive = false;
    if (kDebugMode) {
      print('TherapyConversationGraph: Ended session');
    }
  }
  
  // Initialize the graph structure
  void _initGraph() {
    try {
      // Create a new StateGraph
      final graph = StateGraph('therapy_conversation', initialState: _state);
      
      // Define nodes in the graph
      graph.addNode('process_user_input', _processUserInput);
      graph.addNode('detect_topics_and_mood', _detectTopicsAndMood);
      graph.addNode('generate_response', _generateResponse);
      graph.addNode('update_session_state', _updateSessionState);
      
      // Define edges (flow between nodes)
      graph.addEdge('process_user_input', 'detect_topics_and_mood');
      graph.addEdge('detect_topics_and_mood', 'generate_response');
      graph.addEdge('generate_response', 'update_session_state');
      
      // Compile the graph
      _runGraph = graph.compile();
      
      if (kDebugMode) {
        print('TherapyConversationGraph: Successfully initialized conversation graph');
      }
    } catch (e) {
      if (kDebugMode) {
        print('TherapyConversationGraph: Error initializing graph: $e');
      }
      
      // Create a simple fallback function
      _runGraph = (input) {
        return {'response': 'I apologize, but I encountered an error in my conversation flow. How can I help you today?'};
      };
    }
  }
  
  // Process a user message and generate a response
  Future<String> processUserMessage(String userMessage) async {
    if (!_isSessionActive) {
      await initializeSession();
    }
    
    try {
      // Add user message to conversation history
      _state['conversation_history'].add({
        'role': 'user',
        'content': userMessage,
      });
      
      // If graph is not initialized, fall back to direct LLM call
      if (_runGraph == null) {
        if (kDebugMode) {
          print('TherapyConversationGraph: Graph not initialized, falling back to direct LLM call');
        }
        
        final response = await _groqService.generateChatCompletion(
          userMessage: userMessage,
          systemPrompt: TherapyPromptTemplates.formatTherapistPrompt(
            therapistStyle: _state['therapeutic_approach'] as String,
            sessionPhase: _state['current_phase'] as String,
            specificInstructions: 'Respond helpfully to the user\'s message.',
          ),
        );
        
        // Add AI response to conversation history
        _state['conversation_history'].add({
          'role': 'assistant',
          'content': response,
        });
        
        return response;
      }
      
      // Run the conversation graph
      final result = await _runGraph!({'user_message': userMessage}) as Map<String, dynamic>;
      
      // Extract the response
      final response = result['response'] as String? ?? 
          'I apologize, but I encountered an issue processing your message. How can I help you today?';
      
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('TherapyConversationGraph: Error processing message: $e');
      }
      
      // Return a fallback response
      return 'I apologize, but I encountered an error while processing your message. Could you please try again?';
    }
  }
  
  // Process user input node
  Future<Map<String, dynamic>> _processUserInput(Map<String, dynamic> state, Map<String, dynamic> input) async {
    // This is just a pass-through node that could be expanded later
    return state;
  }
  
  // Detect topics and mood from user messages
  Future<Map<String, dynamic>> _detectTopicsAndMood(Map<String, dynamic> state, Map<String, dynamic> input) async {
    // Just a placeholder implementation
    return state;
  }
  
  // Generate a response using the LLM
  Future<Map<String, dynamic>> _generateResponse(Map<String, dynamic> state, Map<String, dynamic> input) async {
    final userMessage = input['user_message'] as String;
    final therapeuticApproach = state['therapeutic_approach'] as String;
    final currentPhase = state['current_phase'] as String;
    
    // Generate a prompt based on the current state
    final systemPrompt = TherapyPromptTemplates.formatTherapistPrompt(
      therapistStyle: therapeuticApproach,
      sessionPhase: currentPhase,
      topic: (state['identified_topics'] as List<dynamic>).isNotEmpty 
          ? (state['identified_topics'] as List<dynamic>).join(', ') 
          : '',
      issues: (state['active_issues'] as List<dynamic>).isNotEmpty 
          ? (state['active_issues'] as List<dynamic>).join(', ') 
          : '',
      mood: state['user_mood'] as String,
      specificInstructions: _getPhaseSpecificInstructions(currentPhase),
    );
    
    // Get response from LLM
    final response = await _groqService.generateChatCompletion(
      userMessage: userMessage,
      systemPrompt: systemPrompt,
    );
    
    // Add response to state
    state['response'] = response;
    
    // Add to conversation history
    (state['conversation_history'] as List<dynamic>).add({
      'role': 'assistant',
      'content': response,
    });
    
    return state;
  }
  
  // Update session state based on the conversation
  Future<Map<String, dynamic>> _updateSessionState(Map<String, dynamic> state, Map<String, dynamic> input) async {
    // Update phase based on simple rule (just an example)
    final currentPhase = state['current_phase'] as String;
    final conversationHistory = state['conversation_history'] as List<dynamic>;
    
    // Very basic phase progression
    if (currentPhase == 'initial_greeting' && conversationHistory.length >= 4) {
      state['current_phase'] = 'exploration';
    } else if (currentPhase == 'exploration' && conversationHistory.length >= 10) {
      state['current_phase'] = 'insight_building';
    } else if (currentPhase == 'insight_building' && conversationHistory.length >= 16) {
      state['current_phase'] = 'action_planning';
    } else if (currentPhase == 'action_planning' && conversationHistory.length >= 20) {
      state['current_phase'] = 'closing';
    }
    
    return state;
  }
  
  // Helper to get phase-specific instructions
  String _getPhaseSpecificInstructions(String phase) {
    switch (phase) {
      case 'initial_greeting':
        return 'Warmly greet the user and establish rapport. Ask open-ended questions to understand their needs.';
      case 'exploration':
        return 'Explore the user\'s situation in greater depth. Use empathetic listening and clarifying questions.';
      case 'insight_building':
        return 'Help the user gain insights into patterns and underlying factors. Offer gentle observations and connections.';
      case 'action_planning':
        return 'Work with the user to develop practical strategies or exercises they can try. Be specific and realistic.';
      case 'closing':
        return 'Summarize key points from the conversation and highlight progress. End on a supportive and encouraging note.';
      default:
        return 'Respond compassionately to the user\'s needs.';
    }
  }
} 