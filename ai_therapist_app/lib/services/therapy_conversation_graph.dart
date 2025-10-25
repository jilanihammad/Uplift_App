// lib/services/therapy_conversation_graph.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'therapy_graph_service.dart';

/// Enum for therapeutic approaches
enum TherapeuticApproach {
  cbt, // Cognitive Behavioral Therapy
  act, // Acceptance and Commitment Therapy
  supportive, // Supportive Therapy
  psychodynamic, // Psychodynamic Therapy
  dbt, // Dialectical Behavior Therapy
}

/// Represents the current state of the therapy session
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

/// Represents a node in the therapy conversation graph with additional therapy-specific metadata
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

  // Convert to TherapyNode for use with TherapyGraphService
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

/// Manages a therapy conversation using a graph-based approach, bridging between
/// the TherapyService and TherapyGraphService
class TherapyConversationGraph {
  // The underlying graph service
  final TherapyGraphService _graphService = TherapyGraphService();

  // Current therapeutic approach
  TherapeuticApproach _approach = TherapeuticApproach.supportive;
  set approach(TherapeuticApproach approach) => _approach = approach;
  TherapeuticApproach get approach => _approach;

  // Current conversation node
  late TherapyConversationNode _currentNode;
  TherapyConversationNode get currentNode => _currentNode;

  // Current state
  TherapyState? _currentState;
  TherapyState? get currentState => _currentState;

  // Constructor
  TherapyConversationGraph() {
    _initializeGraph();
  }

  /// Initialize the conversation graph
  void _initializeGraph() {
    _currentNode = _getIntakeNode();
    _currentState = TherapyState(
      id: 'intake',
      name: 'Initial Assessment',
    );
  }

  /// Alias for processUserInput to maintain backward compatibility
  /// This method analyzes the user message and returns guidance for response
  Future<Map<String, dynamic>> analyzeMessage(String userMessage) async {
    return processUserInput(userMessage);
  }

  /// Process user input through the graph and return appropriate response guidance
  Future<Map<String, dynamic>> processUserInput(String userInput) async {
    try {
      // Update state with user input
      _graphService.updateState({
        'last_user_input': userInput,
        'input_length': userInput.length,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Analyze user input (sentiment, topics, etc)
      final analysis = await _analyzeUserInput(userInput);
      _graphService.updateState({
        'analysis': analysis,
        'emotion': analysis['emotion'],
        'emotion_intensity': analysis['emotionIntensity'],
        'topics': analysis['topics'],
        'distress_level': analysis['distressLevel'],
      });

      // Check if we need to handle any safety concerns
      if (_shouldTriggerSafety(analysis)) {
        // Override normal flow for safety concerns
        return {
          'prompt': _getSafetyPrompt(analysis),
          'state': 'safety',
          'analysis': analysis,
          'node': 'crisis_support',
        };
      }

      // Move to next appropriate node based on current state and analysis
      final TherapyNode? nextNode = _graphService.moveToNextNode();

      if (nextNode != null) {
        // Update current node and state
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
        // Fallback if no valid node transition
        return {
          'prompt': "Let's explore how you're feeling right now.",
          'state': 'exploration',
          'analysis': analysis,
        };
      }
    } catch (e) {
      debugPrint('Error processing user input through graph: $e');
      return {
        'prompt': "I'm here to listen and support you.",
        'state': 'supportive',
        'error': e.toString(),
      };
    }
  }

  /// Analyze user input for emotion, topics, and other relevant factors
  Future<Map<String, dynamic>> _analyzeUserInput(String userInput) async {
    // This would normally call an API or ML model
    // For now, we'll use a simple heuristic approach

    final String lowercaseInput = userInput.toLowerCase();

    // Emotion detection (very simplified)
    String emotion = 'neutral';
    double emotionIntensity = 5.0;

    // Simple keyword matching for emotions
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

    // Topic detection (very simplified)
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

    // Distress detection
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

    // Cognitive distortions detection
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

  /// Check if safety concerns should override normal flow
  bool _shouldTriggerSafety(Map<String, dynamic> analysis) {
    return analysis['distressLevel'] >= 8.5;
  }

  /// Get a prompt focused on safety concerns
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

  /// Update the current node based on the TherapyNode from the graph service
  void _updateCurrentNode(TherapyNode node) {
    // Convert node to TherapyConversationNode
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

    // Update current state
    _currentState = TherapyState(
      id: node.id,
      name: node.name,
      metadata: node.metadata,
    );
  }

  /// Get the intake assessment node for starting a conversation
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

  /// Create a CBT-focused therapy graph
  static TherapyConversationGraph createCbtGraph() {
    final graph = TherapyConversationGraph();
    graph._approach = TherapeuticApproach.cbt;
    return graph;
  }

  /// Create an ACT-focused therapy graph
  static TherapyConversationGraph createActGraph() {
    final graph = TherapyConversationGraph();
    graph._approach = TherapeuticApproach.act;
    return graph;
  }
}
