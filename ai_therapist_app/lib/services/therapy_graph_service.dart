// lib/services/therapy_graph_service.dart
import 'dart:async';
import 'dart:math';
import '../models/conversation_memory.dart';

/// Represents a node in the conversation graph
class TherapyNode {
  final String id;
  final String name;
  final String description;
  final Map<String, dynamic> metadata;

  TherapyNode({
    required this.id,
    required this.name,
    required this.description,
    this.metadata = const {},
  });
}

/// Represents a directed edge in the conversation graph
class TherapyEdge {
  final String sourceId;
  final String targetId;
  final double weight;
  final String? condition;

  TherapyEdge({
    required this.sourceId,
    required this.targetId,
    this.weight = 1.0,
    this.condition,
  });

  /// Check if the edge's condition is met given the conversation state
  bool isConditionMet(Map<String, dynamic> state) {
    if (condition == null || condition!.isEmpty) return true;

    // Simple condition evaluator (can be expanded for more complex logic)
    if (condition == 'has_distress' && state['distress_level'] != null) {
      return (state['distress_level'] as double) > 6.0;
    } else if (condition == 'has_goal' &&
        state['has_therapeutic_goal'] != null) {
      return state['has_therapeutic_goal'] as bool;
    }

    return true;
  }
}

/// Manages the therapy conversation using a graph-based approach,
/// enabling sophisticated conversation flows and state management.
class TherapyGraphService {
  // Graph structure with nodes and edges
  final Map<String, TherapyNode> _nodes = {};
  final List<TherapyEdge> _edges = [];

  // Current session state
  String? _currentNodeId;
  final Map<String, dynamic> _conversationState = {};
  final List<String> _visitedNodes = [];

  // Streaming controller for conversation events
  final _conversationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get conversationStream =>
      _conversationController.stream;

  // Constructor
  TherapyGraphService() {
    _initializeTherapyGraph();
  }

  /// Initialize the graph with therapy conversation nodes and transitions
  void _initializeTherapyGraph() {
    // Create nodes for therapy flow
    _addNode(
      id: 'intake',
      name: 'Intake Assessment',
      description: 'Initial assessment of the user\'s needs and concerns',
      metadata: {
        'prompt_template':
            'Welcome to our therapy session. To help me understand how best to support you today, could you share what brings you here and how you\'ve been feeling lately?',
        'required_information': ['main_concern', 'mood'],
        'max_time': 5,
      },
    );

    _addNode(
      id: 'emotion_exploration',
      name: 'Emotional Exploration',
      description: 'Exploring the user\'s emotions and feelings',
      metadata: {
        'prompt_template':
            'I\'d like to understand more about how you\'re feeling. Can you tell me more about these emotions and when you typically experience them?',
        'techniques': ['reflective_listening', 'emotion_validation'],
        'max_time': 7,
      },
    );

    _addNode(
      id: 'thought_identification',
      name: 'Thought Identification',
      description: 'Helping the user identify thoughts behind emotions',
      metadata: {
        'prompt_template':
            'It sounds like you\'re experiencing {emotion}. What thoughts or beliefs might be connected to this feeling?',
        'techniques': ['socratic_questioning', 'thought_recording'],
        'max_time': 8,
      },
    );

    _addNode(
      id: 'thought_challenging',
      name: 'Thought Challenging',
      description: 'Analyzing and challenging unhelpful thought patterns',
      metadata: {
        'prompt_template':
            "Let's look more closely at the thought \"{identified_thought}\". What evidence supports this thought? Is there any evidence that doesn't support it?",
        'techniques': ['cognitive_restructuring', 'evidence_analysis'],
        'max_time': 10,
      },
    );

    _addNode(
      id: 'values_exploration',
      name: 'Values Exploration',
      description: 'Exploring the user\'s core values and what matters',
      metadata: {
        'prompt_template':
            "I'd like to understand what truly matters to you. What are some values or principles that guide your life?",
        'techniques': ['values_clarification', 'motivational_interviewing'],
        'max_time': 7,
      },
    );

    _addNode(
      id: 'action_planning',
      name: 'Action Planning',
      description: 'Creating specific, actionable steps forward',
      metadata: {
        'prompt_template':
            "Based on what we've discussed, let's identify a specific action you can take this week that aligns with your values.",
        'techniques': ['goal_setting', 'implementation_intentions'],
        'max_time': 6,
      },
    );

    _addNode(
      id: 'coping_skills',
      name: 'Coping Skills Development',
      description: 'Teaching specific coping strategies',
      metadata: {
        'prompt_template':
            "Let's talk about strategies you can use when experiencing {emotion}. Have you tried any techniques that have worked for you before?",
        'techniques': ['breathing_exercises', 'mindfulness', 'defusion'],
        'max_time': 8,
      },
    );

    _addNode(
      id: 'crisis_support',
      name: 'Crisis Support',
      description: 'Providing immediate support for intense distress',
      metadata: {
        'prompt_template':
            "I'm hearing that you're experiencing significant distress right now. Your safety is the priority. Let's focus on helping you through this immediate moment.",
        'techniques': ['grounding', 'crisis_intervention'],
        'max_time': 10,
        'urgent': true,
      },
    );

    _addNode(
      id: 'reflection_integration',
      name: 'Reflection and Integration',
      description: 'Summarizing insights and progress',
      metadata: {
        'prompt_template':
            "Let's summarize the key insights and the specific steps you've committed to. How are you feeling about these next steps?",
        'techniques': ['summarizing', 'feedback_elicitation'],
        'max_time': 5,
      },
    );

    // Create edges (transitions between nodes)
    // From intake to various paths
    _addEdge(sourceId: 'intake', targetId: 'emotion_exploration');
    _addEdge(
        sourceId: 'intake',
        targetId: 'crisis_support',
        condition: 'has_distress');
    _addEdge(sourceId: 'intake', targetId: 'values_exploration');

    // Emotional exploration paths
    _addEdge(
        sourceId: 'emotion_exploration', targetId: 'thought_identification');
    _addEdge(sourceId: 'emotion_exploration', targetId: 'coping_skills');
    _addEdge(
        sourceId: 'emotion_exploration',
        targetId: 'crisis_support',
        condition: 'has_distress');

    // Thought work paths
    _addEdge(
        sourceId: 'thought_identification', targetId: 'thought_challenging');
    _addEdge(sourceId: 'thought_challenging', targetId: 'values_exploration');
    _addEdge(sourceId: 'thought_challenging', targetId: 'action_planning');

    // Values and action paths
    _addEdge(sourceId: 'values_exploration', targetId: 'action_planning');
    _addEdge(
        sourceId: 'values_exploration', targetId: 'thought_identification');
    _addEdge(sourceId: 'coping_skills', targetId: 'action_planning');

    // Paths to reflection/conclusion
    _addEdge(sourceId: 'action_planning', targetId: 'reflection_integration');
    _addEdge(sourceId: 'coping_skills', targetId: 'reflection_integration');
    _addEdge(sourceId: 'crisis_support', targetId: 'coping_skills');

    // Set initial node
    _currentNodeId = 'intake';
  }

  /// Add a node to the therapy graph
  void _addNode({
    required String id,
    required String name,
    required String description,
    Map<String, dynamic> metadata = const {},
  }) {
    _nodes[id] = TherapyNode(
      id: id,
      name: name,
      description: description,
      metadata: metadata,
    );
  }

  /// Add an edge (connection) between nodes
  void _addEdge({
    required String sourceId,
    required String targetId,
    double weight = 1.0,
    String? condition,
  }) {
    _edges.add(TherapyEdge(
      sourceId: sourceId,
      targetId: targetId,
      weight: weight,
      condition: condition,
    ));
  }

  /// Start a new therapy session
  void startSession({Map<String, dynamic>? initialState}) {
    _currentNodeId = 'intake';
    _visitedNodes.clear();
    _conversationState.clear();

    if (initialState != null) {
      _conversationState.addAll(initialState);
    }

    _visitedNodes.add(_currentNodeId!);
    _emitConversationUpdate();
  }

  /// Get the current node in the conversation
  TherapyNode? getCurrentNode() {
    if (_currentNodeId == null) return null;
    return _nodes[_currentNodeId];
  }

  /// Update the conversation state
  void updateState(Map<String, dynamic> updates) {
    _conversationState.addAll(updates);
    _emitConversationUpdate();
  }

  /// Get the therapy prompts for the current node
  String getTherapyPrompt() {
    final node = getCurrentNode();
    if (node == null) return "How are you feeling today?";

    String promptTemplate = node.metadata['prompt_template'] as String? ??
        "I'd like to understand more about what you're experiencing.";

    // Replace any placeholders with values from the state
    _conversationState.forEach((key, value) {
      if (value is String) {
        promptTemplate = promptTemplate.replaceAll('{$key}', value);
      }
    });

    // Add specific technique guidance based on the node
    return _enhancePromptWithTechniques(promptTemplate, node);
  }

  /// Add therapeutic techniques to the base prompt
  String _enhancePromptWithTechniques(String basePrompt, TherapyNode node) {
    final techniques = node.metadata['techniques'] as List<String>? ?? [];
    final StringBuffer enhancedPrompt = StringBuffer(basePrompt);

    // Append technique-specific guidance for the AI therapist
    // This would not be shown to the user but guides the AI response
    if (techniques.contains('cognitive_restructuring')) {
      enhancedPrompt.write("""

[THERAPEUTIC GUIDANCE: Help explore thoughts behind emotions, examine evidence for and against these thoughts, and develop alternative perspectives.]""");
    } else if (techniques.contains('values_clarification')) {
      enhancedPrompt.write("""

[THERAPEUTIC GUIDANCE: Explore what truly matters to the person across different life domains like relationships, work, personal growth, etc.]""");
    } else if (techniques.contains('goal_setting')) {
      enhancedPrompt.write("""

[THERAPEUTIC GUIDANCE: Help create SMART goals (Specific, Measurable, Achievable, Relevant, Time-bound) that align with their values.]""");
    }

    return enhancedPrompt.toString();
  }

  /// Move to the next appropriate node based on the conversation state
  TherapyNode? moveToNextNode() {
    if (_currentNodeId == null) return null;

    // First check if we need to handle crisis situations
    if (_conversationState['distress_level'] != null &&
        (_conversationState['distress_level'] as double) > 8.0 &&
        _currentNodeId != 'crisis_support') {
      _currentNodeId = 'crisis_support';
      _visitedNodes.add(_currentNodeId!);
      _emitConversationUpdate();
      return getCurrentNode();
    }

    // Find all potential next nodes
    final availableEdges = _edges
        .where((edge) =>
            edge.sourceId == _currentNodeId &&
            edge.isConditionMet(_conversationState))
        .toList();

    if (availableEdges.isEmpty) {
      // No valid transitions, default to reflection
      _currentNodeId = 'reflection_integration';
    } else {
      // Weight edges based on relevance to current state
      final targetNodes = _calculateNodeRelevance(availableEdges);

      // Select next node (weighted random selection)
      final targetNodeId = _weightedRandomSelection(targetNodes);
      _currentNodeId = targetNodeId;
    }

    _visitedNodes.add(_currentNodeId!);
    _emitConversationUpdate();
    return getCurrentNode();
  }

  /// Calculate node relevance based on user state
  Map<String, double> _calculateNodeRelevance(List<TherapyEdge> edges) {
    final Map<String, double> nodeWeights = {};

    for (final edge in edges) {
      double weight = edge.weight;

      // Increase weight for nodes that match current emotional needs
      final targetNode = _nodes[edge.targetId];
      if (targetNode != null) {
        // Increase relevance for emotion-focused nodes when emotions are high
        if (targetNode.id == 'emotion_exploration' &&
            _conversationState['emotion_intensity'] != null &&
            (_conversationState['emotion_intensity'] as double) > 5.0) {
          weight *= 2.0;
        }

        // Increase relevance for thought-focused nodes when cognitive distortions detected
        if ((targetNode.id == 'thought_identification' ||
                targetNode.id == 'thought_challenging') &&
            _conversationState['has_cognitive_distortions'] == true) {
          weight *= 1.5;
        }

        // Prioritize action planning later in the session
        if (targetNode.id == 'action_planning' && _visitedNodes.length > 3) {
          weight *= 1.3;
        }
      }

      // Add weighted node to selection options
      nodeWeights[edge.targetId] = weight;
    }

    return nodeWeights;
  }

  /// Select a node using weighted random selection
  String _weightedRandomSelection(Map<String, double> nodeWeights) {
    double totalWeight =
        nodeWeights.values.fold(0.0, (sum, weight) => sum + weight);
    double selection = Random().nextDouble() * totalWeight;

    double currentSum = 0.0;
    for (final entry in nodeWeights.entries) {
      currentSum += entry.value;
      if (selection <= currentSum) {
        return entry.key;
      }
    }

    // Fallback in case of rounding errors
    return nodeWeights.keys.first;
  }

  /// Emit updated conversation state
  void _emitConversationUpdate() {
    final currentNode = getCurrentNode();
    if (currentNode != null) {
      _conversationController.add({
        'current_node': currentNode.id,
        'node_name': currentNode.name,
        'conversation_state': Map<String, dynamic>.from(_conversationState),
        'visited_nodes': List<String>.from(_visitedNodes),
      });
    }
  }

  /// Get therapy techniques related to the current node
  List<String> getCurrentTechniques() {
    final node = getCurrentNode();
    if (node == null) return [];
    return node.metadata['techniques'] as List<String>? ?? [];
  }

  /// Get the therapeutic approach for the current state
  String getTherapeuticApproach() {
    final node = getCurrentNode();
    if (node == null) return "Supportive listening";

    // Return appropriate therapeutic approach based on node
    switch (node.id) {
      case 'emotion_exploration':
        return "Emotion-focused therapy";
      case 'thought_identification':
      case 'thought_challenging':
        return "Cognitive behavioral therapy";
      case 'values_exploration':
      case 'action_planning':
        return "Acceptance and commitment therapy";
      case 'coping_skills':
        return "Skills training";
      case 'crisis_support':
        return "Crisis intervention";
      default:
        return "Integrative approach";
    }
  }

  /// Generate therapy interventions for the current node
  List<String> generateInterventions() {
    final node = getCurrentNode();
    if (node == null) return ["Open-ended questions to explore feelings"];

    // Return specific interventions based on the current node
    switch (node.id) {
      case 'emotion_exploration':
        return [
          "Reflective listening to validate emotions",
          "Emotion wheel to identify specific feelings",
          "Mindful awareness of physical sensations"
        ];
      case 'thought_identification':
        return [
          "Identify automatic thoughts connected to feelings",
          "Track thought patterns using thought record",
          "Notice cognitive distortions in thinking"
        ];
      case 'thought_challenging':
        return [
          "Examine evidence for and against thoughts",
          "Develop alternative explanations",
          "Rate confidence in thoughts before and after challenging"
        ];
      case 'values_exploration':
        return [
          "Values card sort exercise",
          "Exploring life domains that matter most",
          "Connect current struggles with important values"
        ];
      case 'action_planning':
        return [
          "SMART goal setting aligned with values",
          "Break down actions into manageable steps",
          "Identify potential obstacles and solutions"
        ];
      case 'coping_skills':
        return [
          "Breathing techniques for anxiety reduction",
          "Mindfulness practices for present awareness",
          "Cognitive defusion to create distance from thoughts"
        ];
      case 'crisis_support':
        return [
          "Grounding techniques using five senses",
          "Crisis safety planning",
          "Emotional regulation skills"
        ];
      case 'reflection_integration':
        return [
          "Summarize key insights and progress",
          "Review homework and action steps",
          "Set expectations for continuing practice"
        ];
      default:
        return ["Active listening and validation"];
    }
  }

  /// Close resources when done
  void dispose() {
    _conversationController.close();
  }
}
