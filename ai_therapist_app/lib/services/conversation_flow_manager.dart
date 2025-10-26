import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/therapy_conversation_graph.dart';
import '../utils/logger_util.dart';

/// Manages the flow and state of therapy conversations using a graph-based approach
class ConversationFlowManager {
  // Therapy conversation graph for managing the flow of therapy
  late TherapyConversationGraph _conversationGraph;

  // Therapeutic approach
  TherapeuticApproach _therapeuticApproach = TherapeuticApproach.supportive;

  // Initialization status
  bool _isInitialized = false;

  // Private constructor for singleton pattern
  ConversationFlowManager._() {
    if (kDebugMode) {
      debugPrint('ConversationFlowManager private constructor called');
    }
  }

  // Singleton instance
  static final ConversationFlowManager _instance = ConversationFlowManager._();

  // Factory constructor to return the singleton instance
  factory ConversationFlowManager() {
    if (kDebugMode) {
      debugPrint('Reusing existing ConversationFlowManager instance');
    }
    return _instance;
  }

  /// Initialize the conversation flow manager
  Future<void> init() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('ConversationFlowManager already initialized, skipping init()');
      }
      return;
    }

    try {
      // Initialize conversation graph with default approach
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
      _isInitialized = true;
      log.i('Conversation flow manager initialized with CBT graph');
    } catch (e) {
      log.e('Error initializing conversation flow manager', e);
    }
  }

  /// Initialize only if needed
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Set the therapeutic approach
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

    _conversationGraph.approach = approach;
  
    log.i(
        'Therapeutic approach set to: ${approach.toString().split('.').last}');
  }

  /// Process user input through the therapy graph
  Future<Map<String, dynamic>> processUserInput(String userInput) async {
    try {
      return await _conversationGraph.processUserInput(userInput);
    } catch (e) {
      log.e('Error processing user input through graph', e);
      // Return a basic state object if graph processing fails
      return {
        'state': 'general',
        'analysis': {
          'emotion': 'neutral',
          'emotionIntensity': 5.0,
          'topics': []
        }
      };
    }
  }

  /// Get the current therapy state
  TherapyState? getCurrentState() {
    return _conversationGraph.currentState;
  }

  /// Get the current node in the conversation graph
  TherapyConversationNode getCurrentNode() {
    return _conversationGraph.currentNode;
  }

  /// Get available therapeutic tools for the current state
  List<String> getAvailableTools() {
    return _conversationGraph.currentNode.tools;
  }

  /// Get therapeutic techniques for current conversation state
  List<String> getCurrentTechniques() {
    return _conversationGraph.currentNode.techniques;
  }

  /// Reset the conversation flow
  void resetConversation() {
    // Initialize a new graph with the current approach
    if (_therapeuticApproach == TherapeuticApproach.act) {
      _conversationGraph = TherapyConversationGraph.createActGraph();
    } else if (_therapeuticApproach == TherapeuticApproach.cbt) {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    } else {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    }

    log.i('Conversation flow reset to initial state');
  }

  /// Process user input in background
  static Future<Map<String, dynamic>> processUserInputBackground(
      Map<String, dynamic> params) async {
    try {
      final graph = params['graph'] as TherapyConversationGraph;
      final userMessage = params['userMessage'] as String;
      return await graph.processUserInput(userMessage);
    } catch (e) {
      debugPrint('Error processing user input in background: $e');
      return {};
    }
  }

  /// Get the current therapeutic approach
  TherapeuticApproach getTherapeuticApproach() {
    return _therapeuticApproach;
  }
}
