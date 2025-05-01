// lib/services/memory_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation_memory.dart';
import '../di/service_locator.dart';
import '../data/datasources/local/database_provider.dart';

/// Service for managing memory in therapy conversations.
/// Implements LangChain-like memory capabilities for maintaining context across conversations.
class MemoryService {
  // Singleton instance
  static MemoryService? _instance;

  // Initialization flag
  bool _isInitialized = false;

  // In-memory cache of conversation memories
  final List<ConversationMemory> _conversationMemories = [];

  // In-memory cache of insights
  final List<TherapyInsight> _insights = [];

  // In-memory cache of emotional states
  final List<EmotionalState> _emotionalStates = [];

  // User preferences
  final Map<String, dynamic> _userPreferences = {};

  // Maximum context length for LLM
  static const int _maxContextLength = 4000;

  // Database provider for persistence
  final DatabaseProvider _databaseProvider;

  // Factory constructor to enforce singleton pattern
  factory MemoryService({required DatabaseProvider databaseProvider}) {
    // Return existing instance if already created
    if (_instance != null) {
      if (kDebugMode) {
        print('Reusing existing MemoryService instance');
      }
      return _instance!;
    }

    // Create new instance if first time
    _instance = MemoryService._internal(databaseProvider: databaseProvider);
    return _instance!;
  }

  // Private constructor for singleton pattern
  MemoryService._internal({required DatabaseProvider databaseProvider})
      : _databaseProvider = databaseProvider {
    if (kDebugMode) {
      print('MemoryService initialized with constructor injection');
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize only if needed - prevents redundant initializations
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }

  /// Initialize the memory service by loading memories from persistence
  Future<void> init() async {
    // Skip if already initialized
    if (_isInitialized) {
      if (kDebugMode) {
        print('MemoryService already initialized, skipping init()');
      }
      return;
    }

    try {
      // Load memories from database
      final memories = await _loadMemoriesFromDatabase();
      _conversationMemories.clear();
      _conversationMemories.addAll(memories);

      // Load insights from database
      final insights = await _loadInsightsFromDatabase();
      _insights.clear();
      _insights.addAll(insights);

      // Load emotional states from database
      final states = await _loadEmotionalStatesFromDatabase();
      _emotionalStates.clear();
      _emotionalStates.addAll(states);

      // Load user preferences
      await _loadUserPreferences();

      _isInitialized = true;

      if (kDebugMode) {
        print('Memory service initialized with:');
        print('- ${_conversationMemories.length} conversation memories');
        print('- ${_insights.length} insights');
        print('- ${_emotionalStates.length} emotional states');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize memory service: $e');
      }
    }
  }

  /// Add a user-AI interaction to memory
  Future<void> addInteraction(String userMessage, String aiResponse,
      Map<String, dynamic> metadata) async {
    final memory = ConversationMemory(
      userMessage: userMessage,
      aiResponse: aiResponse,
      metadata: metadata,
    );

    // Add to in-memory cache
    _conversationMemories.add(memory);

    // Persist to database
    try {
      await _saveMemoryToDatabase(memory);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save memory: $e');
      }
    }
  }

  /// Add an insight to the memory
  Future<void> addInsight(String insightText, String source) async {
    final insight = TherapyInsight(
      insight: insightText,
      source: source,
    );

    // Add to in-memory cache
    _insights.add(insight);

    // Persist to database
    try {
      await _saveInsightToDatabase(insight);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save insight: $e');
      }
    }
  }

  /// Update the emotional state
  Future<void> updateEmotionalState(
      String emotion, double intensity, String? trigger) async {
    final state = EmotionalState(
      emotion: emotion,
      intensity: intensity,
      trigger: trigger,
    );

    // Add to in-memory cache
    _emotionalStates.add(state);

    // Persist to database
    try {
      await _saveEmotionalStateToDatabase(state);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to save emotional state: $e');
      }
    }
  }

  /// Update therapeutic goals
  Future<void> updateTherapeuticGoals(List<String> goals) async {
    // Update user preferences with goals
    await updateUserPreference('therapeutic_goals', goals);
  }

  /// Update a user preference
  Future<void> updateUserPreference(String key, dynamic value) async {
    _userPreferences[key] = value;
    await _saveUserPreferences();
  }

  /// Get relevant memory context based on recency and relevance
  Future<String> getMemoryContext() async {
    if (_conversationMemories.isEmpty) return '';

    // Sort memories by recency
    final sortedMemories = List<ConversationMemory>.from(_conversationMemories)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Get recent memories, limited by context size
    final recentMemories = sortedMemories.take(10).toList();

    // Format memories as context string
    final StringBuffer contextBuffer = StringBuffer();

    // Add user preferences if available
    if (_userPreferences.isNotEmpty) {
      contextBuffer.writeln('USER PREFERENCES:');
      _userPreferences.forEach((key, value) {
        if (value is List) {
          contextBuffer.writeln('$key: ${value.join(", ")}');
        } else {
          contextBuffer.writeln('$key: $value');
        }
      });
      contextBuffer.writeln();
    }

    // Add key insights
    if (_insights.isNotEmpty) {
      contextBuffer.writeln('KEY INSIGHTS:');
      // Sort insights by recency
      final sortedInsights = List<TherapyInsight>.from(_insights)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Add top insights
      for (int i = 0; i < min(5, sortedInsights.length); i++) {
        final insight = sortedInsights[i];
        contextBuffer.writeln('- ${insight.insight}');
      }
      contextBuffer.writeln();
    }

    // Add emotional patterns
    if (_emotionalStates.isNotEmpty) {
      contextBuffer.writeln('EMOTIONAL PATTERNS:');
      // Sort states by recency
      final sortedStates = List<EmotionalState>.from(_emotionalStates)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Group by emotion and calculate average intensity
      final Map<String, List<EmotionalState>> emotionGroups = {};
      for (final state in sortedStates) {
        if (!emotionGroups.containsKey(state.emotion)) {
          emotionGroups[state.emotion] = [];
        }
        emotionGroups[state.emotion]!.add(state);
      }

      // Add emotion summaries
      emotionGroups.forEach((emotion, states) {
        final avgIntensity =
            states.map((s) => s.intensity).reduce((a, b) => a + b) /
                states.length;
        contextBuffer.writeln(
            '- $emotion: Average intensity ${avgIntensity.toStringAsFixed(1)}/10.0');

        // Add common triggers if available
        final triggers = states
            .where((s) => s.trigger != null)
            .map((s) => s.trigger!)
            .take(2)
            .join(", ");
        if (triggers.isNotEmpty) {
          contextBuffer.writeln('  Common triggers: $triggers');
        }
      });
      contextBuffer.writeln();
    }

    // Add conversation history
    contextBuffer.writeln('RECENT CONVERSATION HISTORY:');
    for (final memory in recentMemories) {
      contextBuffer.writeln('User: ${memory.userMessage}');
      contextBuffer.writeln('AI: ${memory.aiResponse}');
      contextBuffer.writeln();
    }

    // Check if we're exceeding the max context length and truncate if needed
    String context = contextBuffer.toString();
    if (context.length > _maxContextLength) {
      // Keep preferences and insights, truncate conversation history
      final preferencesPart = _userPreferences.isNotEmpty
          ? context.split('RECENT CONVERSATION HISTORY:')[0]
          : '';

      final conversationPart = context.split('RECENT CONVERSATION HISTORY:')[1];

      // Calculate how much of the conversation history we can keep
      final int availableSpace = _maxContextLength - preferencesPart.length;
      final String truncatedConversation =
          conversationPart.length > availableSpace
              ? conversationPart.substring(0, availableSpace) + '...(truncated)'
              : conversationPart;

      context = preferencesPart +
          'RECENT CONVERSATION HISTORY:' +
          truncatedConversation;
    }

    return context;
  }

  // Helper method to get the minimum of two numbers
  int min(int a, int b) {
    return a < b ? a : b;
  }

  // Database operations

  Future<List<ConversationMemory>> _loadMemoriesFromDatabase() async {
    try {
      // This could be implemented using your DatabaseProvider to load from SQLite
      // For now, we'll use SharedPreferences as a simple persistence mechanism
      final prefs = await SharedPreferences.getInstance();
      final List<String>? memoryJsonList =
          prefs.getStringList('conversation_memories');

      if (memoryJsonList == null || memoryJsonList.isEmpty) return [];

      return memoryJsonList
          .map((jsonStr) => ConversationMemory.fromJsonString(jsonStr))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading memories: $e');
      }
      return [];
    }
  }

  Future<void> _saveMemoryToDatabase(ConversationMemory memory) async {
    try {
      // This could be implemented using your DatabaseProvider to save to SQLite
      // For now, we'll use SharedPreferences as a simple persistence mechanism
      final prefs = await SharedPreferences.getInstance();
      List<String> memoryJsonList =
          prefs.getStringList('conversation_memories') ?? [];

      // Add new memory
      memoryJsonList.add(memory.toJsonString());

      // Keep list size manageable
      if (memoryJsonList.length > 100) {
        memoryJsonList = memoryJsonList.sublist(memoryJsonList.length - 100);
      }

      await prefs.setStringList('conversation_memories', memoryJsonList);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving memory: $e');
      }
    }
  }

  Future<List<TherapyInsight>> _loadInsightsFromDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? insightJsonList =
          prefs.getStringList('therapy_insights');

      if (insightJsonList == null || insightJsonList.isEmpty) return [];

      return insightJsonList
          .map((jsonStr) => TherapyInsight.fromJson(json.decode(jsonStr)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading insights: $e');
      }
      return [];
    }
  }

  Future<void> _saveInsightToDatabase(TherapyInsight insight) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> insightJsonList =
          prefs.getStringList('therapy_insights') ?? [];

      // Add new insight
      insightJsonList.add(json.encode(insight.toJson()));

      // Keep list size manageable
      if (insightJsonList.length > 50) {
        insightJsonList = insightJsonList.sublist(insightJsonList.length - 50);
      }

      await prefs.setStringList('therapy_insights', insightJsonList);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving insight: $e');
      }
    }
  }

  Future<List<EmotionalState>> _loadEmotionalStatesFromDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? stateJsonList =
          prefs.getStringList('emotional_states');

      if (stateJsonList == null || stateJsonList.isEmpty) return [];

      return stateJsonList
          .map((jsonStr) => EmotionalState.fromJson(json.decode(jsonStr)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading emotional states: $e');
      }
      return [];
    }
  }

  Future<void> _saveEmotionalStateToDatabase(EmotionalState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> stateJsonList =
          prefs.getStringList('emotional_states') ?? [];

      // Add new state
      stateJsonList.add(json.encode(state.toJson()));

      // Keep list size manageable
      if (stateJsonList.length > 100) {
        stateJsonList = stateJsonList.sublist(stateJsonList.length - 100);
      }

      await prefs.setStringList('emotional_states', stateJsonList);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving emotional state: $e');
      }
    }
  }

  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? prefsJson = prefs.getString('user_preferences');

      if (prefsJson != null && prefsJson.isNotEmpty) {
        final Map<String, dynamic> loadedPrefs = json.decode(prefsJson);
        _userPreferences.clear();
        _userPreferences.addAll(loadedPrefs);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading user preferences: $e');
      }
    }
  }

  Future<void> _saveUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_preferences', json.encode(_userPreferences));
    } catch (e) {
      if (kDebugMode) {
        print('Error saving user preferences: $e');
      }
    }
  }

  // Clear all memory (for testing or user request)
  Future<void> clearAllMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('conversation_memories');
      await prefs.remove('therapy_insights');
      await prefs.remove('emotional_states');

      _conversationMemories.clear();
      _insights.clear();
      _emotionalStates.clear();

      if (kDebugMode) {
        print('All memory cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing memory: $e');
      }
    }
  }
}
