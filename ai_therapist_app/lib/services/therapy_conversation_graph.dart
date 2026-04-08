// lib/services/therapy_conversation_graph.dart
import 'dart:async';
import 'therapy_graph_service.dart';
enum TherapeuticApproach {
  cbt, // Cognitive Behavioral Therapy
  act, // Acceptance and Commitment Therapy
  supportive, // Supportive Therapy
  psychodynamic, // Psychodynamic Therapy
  dbt, // Dialectical Behavior Therapy
}
class TherapyState {
  final String id;
  final String name;
  final Map<String, dynamic> metadata;
  TherapyState({
    required this.id,
    required this.name,
    this.metadata = const {},
  });
}
class TherapyConversationNode {
  final String id;
  final String name;
  final String description;
  final List<String> techniques;
  final List<String> tools;
  final String promptTemplate;
  final Map<String, dynamic> metadata;
  TherapyConversationNode({
    required this.id,
    required this.name,
    required this.description,
    this.techniques = const [],
    this.tools = const [],
    this.promptTemplate = '',
    this.metadata = const {},
  });
  TherapyNode toTherapyNode() {
    return TherapyNode(
      id: id,
      name: name,
      description: description,
      metadata: {
        ...metadata,
        'techniques': techniques,
        'tools': tools,
        'prompt_template': promptTemplate,
      },
    );
  }
}
class TherapyConversationGraph {
  final TherapyGraphService _graphService = TherapyGraphService();
  TherapeuticApproach _approach = TherapeuticApproach.supportive;
  set approach(TherapeuticApproach approach) => _approach = approach;
  TherapeuticApproach get approach => _approach;
  late TherapyConversationNode _currentNode;
  TherapyConversationNode get currentNode => _currentNode;
  TherapyState? _currentState;
  TherapyState? get currentState => _currentState;
  TherapyConversationGraph() {
    _initializeGraph();
  }
  void _initializeGraph() {
    _currentNode = _getIntakeNode();
    _currentState = TherapyState(
      id: 'intake',
      name: 'Initial Assessment',
    );
  }
  Future<Map<String, dynamic>> analyzeMessage(String userMessage) async {
    return processUserInput(userMessage);
  }
  Future<Map<String, dynamic>> processUserInput(String userInput) async {
    try {
      _graphService.updateState({
        'last_user_input': userInput,
        'input_length': userInput.length,
        'timestamp': DateTime.now().toIso8601String(),
      });
      final analysis = await _analyzeUserInput(userInput);
      _graphService.updateState({
        'analysis': analysis,
        'emotion': analysis['emotion'],
        'emotion_intensity': analysis['emotionIntensity'],
        'topics': analysis['topics'],
        'distress_level': analysis['distressLevel'],
      });
      if (_shouldTriggerSafety(analysis)) {
        return {
          'prompt': _getSafetyPrompt(analysis),
          'state': 'safety',
          'analysis': analysis,
          'node': 'crisis_support',
        };
      }
      final TherapyNode? nextNode = _graphService.moveToNextNode();
      if (nextNode != null) {
        _updateCurrentNode(nextNode);
        return {
          'prompt': _graphService.getTherapyPrompt(),
          'state': _currentState!.id,
          'analysis': analysis,
          'node': nextNode.id,
          'techniques': _graphService.getCurrentTechniques(),
          'approach': _graphService.getTherapeuticApproach(),
        };
      } else {
        return {
          'prompt': "Let's explore how you're feeling right now.",
          'state': 'exploration',
          'analysis': analysis,
        };
      }
    } catch (e) {
      return {
        'prompt': "I'm here to listen and support you.",
        'state': 'supportive',
        'error': e.toString(),
      };
    }
  }
  Future<Map<String, dynamic>> _analyzeUserInput(String userInput) async {
    final String lowercaseInput = userInput.toLowerCase();
    String emotion = 'neutral';
    double emotionIntensity = 5.0;
    if (lowercaseInput.contains('sad') ||
        lowercaseInput.contains('depress') ||
        lowercaseInput.contains('unhappy')) {
      emotion = 'sad';
      emotionIntensity = 7.0;
    } else if (lowercaseInput.contains('anxious') ||
        lowercaseInput.contains('worried') ||
        lowercaseInput.contains('stress')) {
      emotion = 'anxious';
      emotionIntensity = 7.5;
    } else if (lowercaseInput.contains('happy') ||
        lowercaseInput.contains('joy') ||
        lowercaseInput.contains('excit')) {
      emotion = 'happy';
      emotionIntensity = 8.0;
    } else if (lowercaseInput.contains('angry') ||
        lowercaseInput.contains('frustrat') ||
        lowercaseInput.contains('upset')) {
      emotion = 'angry';
      emotionIntensity = 7.8;
    }
    List<String> topics = [];
    if (lowercaseInput.contains('work') || lowercaseInput.contains('job')) {
      topics.add('work');
    }
    if (lowercaseInput.contains('family') ||
        lowercaseInput.contains('parent') ||
        lowercaseInput.contains('child')) {
      topics.add('family');
    }
    if (lowercaseInput.contains('relationship') ||
        lowercaseInput.contains('partner') ||
        lowercaseInput.contains('date')) {
      topics.add('relationships');
    }
    if (lowercaseInput.contains('friend') ||
        lowercaseInput.contains('social')) {
      topics.add('social');
    }
    if (lowercaseInput.contains('money') || lowercaseInput.contains('financ')) {
      topics.add('finances');
    }
    double distressLevel = 3.0;
    if (lowercaseInput.contains('suicid') ||
        lowercaseInput.contains('kill myself') ||
        lowercaseInput.contains('end my life')) {
      distressLevel = 9.5;
    } else if (lowercaseInput.contains('hopeless') ||
        lowercaseInput.contains('cannot go on') ||
        lowercaseInput.contains('give up')) {
      distressLevel = 8.0;
    } else if (emotion == 'sad' || emotion == 'anxious' || emotion == 'angry') {
      distressLevel = emotionIntensity * 0.8;
    }
    bool hasCognitiveDistortions = lowercaseInput.contains('always') ||
        lowercaseInput.contains('never') ||
        lowercaseInput.contains('everyone') ||
        lowercaseInput.contains('nobody');
    return {
      'emotion': emotion,
      'emotionIntensity': emotionIntensity,
      'topics': topics,
      'distressLevel': distressLevel,
      'hasCognitiveDistortions': hasCognitiveDistortions,
    };
  }
  bool _shouldTriggerSafety(Map<String, dynamic> analysis) {
    return analysis['distressLevel'] >= 8.5;
  }
  String _getSafetyPrompt(Map<String, dynamic> analysis) {
    return """
I notice that you may be experiencing significant distress right now. Your safety is my top priority.
- Acknowledge the person's pain without minimizing it
- Express genuine concern for their wellbeing
- Ask directly about thoughts of self-harm if indicated
- Provide immediate coping strategies for the crisis moment
- Connect with immediate resources (crisis lines, emergency services) if needed
- Use a warm, calm tone throughout
If there are any indications of immediate danger, guide the person to emergency resources or suggest they contact a trusted person who can be with them right now.
""";
  }
  void _updateCurrentNode(TherapyNode node) {
    _currentNode = TherapyConversationNode(
      id: node.id,
      name: node.name,
      description: node.description,
      techniques: node.metadata['techniques'] as List<String>? ?? [],
      tools: node.metadata['tools'] as List<String>? ?? [],
      promptTemplate: node.metadata['prompt_template'] as String? ?? '',
      metadata: Map<String, dynamic>.from(node.metadata)
        ..remove('techniques')
        ..remove('tools')
        ..remove('prompt_template'),
    );
    _currentState = TherapyState(
      id: node.id,
      name: node.name,
      metadata: node.metadata,
    );
  }
  TherapyConversationNode _getIntakeNode() {
    return TherapyConversationNode(
      id: 'intake',
      name: 'Initial Assessment',
      description: 'Starting point for therapy conversation',
      techniques: ['active_listening', 'open_questions'],
      tools: ['mood_assessment', 'listening'],
      promptTemplate:
          'Welcome to our conversation. What brings you here today?',
    );
  }
  static TherapyConversationGraph createCbtGraph() {
    final graph = TherapyConversationGraph();
    graph._approach = TherapeuticApproach.cbt;
    return graph;
  }
  static TherapyConversationGraph createActGraph() {
    final graph = TherapyConversationGraph();
    graph._approach = TherapeuticApproach.act;
    return graph;
  }
}
