import 'dart:async';
import '../services/therapy_conversation_graph.dart';
import '../utils/logger_util.dart';
class ConversationFlowManager {
  late TherapyConversationGraph _conversationGraph;
  TherapeuticApproach _therapeuticApproach = TherapeuticApproach.supportive;
  bool _isInitialized = false;
  ConversationFlowManager._() {
  }
  static final ConversationFlowManager _instance = ConversationFlowManager._();
  factory ConversationFlowManager() {
    return _instance;
  }
  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    try {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
      _isInitialized = true;
      log.i('Conversation flow manager initialized with CBT graph');
    } catch (e) {
      log.e('Error initializing conversation flow manager', e);
    }
  }
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }
  bool get isInitialized => _isInitialized;
  void setTherapeuticApproach(TherapeuticApproach approach) {
    _therapeuticApproach = approach;
    if (approach == TherapeuticApproach.act) {
      _conversationGraph = TherapyConversationGraph.createActGraph();
    } else if (approach == TherapeuticApproach.cbt) {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    } else {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    }
    _conversationGraph.approach = approach;
    log.i(
        'Therapeutic approach set to: ${approach.toString().split('.').last}');
  }
  Future<Map<String, dynamic>> processUserInput(String userInput) async {
    try {
      return await _conversationGraph.processUserInput(userInput);
    } catch (e) {
      log.e('Error processing user input through graph', e);
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
  TherapyState? getCurrentState() {
    return _conversationGraph.currentState;
  }
  TherapyConversationNode getCurrentNode() {
    return _conversationGraph.currentNode;
  }
  List<String> getAvailableTools() {
    return _conversationGraph.currentNode.tools;
  }
  List<String> getCurrentTechniques() {
    return _conversationGraph.currentNode.techniques;
  }
  void resetConversation() {
    if (_therapeuticApproach == TherapeuticApproach.act) {
      _conversationGraph = TherapyConversationGraph.createActGraph();
    } else if (_therapeuticApproach == TherapeuticApproach.cbt) {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    } else {
      _conversationGraph = TherapyConversationGraph.createCbtGraph();
    }
    log.i('Conversation flow reset to initial state');
  }
  static Future<Map<String, dynamic>> processUserInputBackground(
      Map<String, dynamic> params) async {
    try {
      final graph = params['graph'] as TherapyConversationGraph;
      final userMessage = params['userMessage'] as String;
      return await graph.processUserInput(userMessage);
    } catch (e) {
      return {};
    }
  }
  TherapeuticApproach getTherapeuticApproach() {
    return _therapeuticApproach;
  }
}
