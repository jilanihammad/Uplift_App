// lib/services/memory_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation_memory.dart';
import '../di/service_locator.dart';
import '../data/datasources/local/database_provider.dart';
import '../di/initialization_tracker.dart';
import '../utils/logging_service.dart';

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

  // Singleton factory constructor
  factory MemoryService({
    required DatabaseProvider databaseProvider,
  }) {
    _instance ??= MemoryService._internal(databaseProvider);
    return _instance!;
  }

  // Private constructor
  MemoryService._internal(this._databaseProvider);

  // Getter for initialization status
  bool get isInitialized => _isInitialized;

  // Initialize the service on-demand
  Future<void> initializeIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }

  // Initialize the MemoryService
  Future<void> init() async {
    if (_isInitialized) {
      if (kDebugMode) {
        logger.debug('MemoryService already initialized, skipping init()');
      }
      return;
    }

    try {
      // Register with initialization tracker
      await initTracker.initializeWithRetry('MemoryService', () async {
        // Load conversation memories from database
        final memoryRecords = await _databaseProvider.query(
          'conversation_memories',
          orderBy: 'timestamp DESC',
        );

        _conversationMemories.clear();
        for (final record in memoryRecords) {
          try {
            final memory = ConversationMemory.fromJson(record);
            _conversationMemories.add(memory);
          } catch (e) {
            logger.warning('Error parsing conversation memory: $e');
          }
        }

        // Load insights from database
        final insightRecords =
            await _databaseProvider.query('therapy_insights');
        _insights.clear();
        for (final record in insightRecords) {
          try {
            final insight = TherapyInsight.fromJson(record);
            _insights.add(insight);
          } catch (e) {
            logger.warning('Error parsing therapy insight: $e');
          }
        }

        // Load emotional states from database
        final stateRecords = await _databaseProvider.query('emotional_states');
        _emotionalStates.clear();
        for (final record in stateRecords) {
          try {
            final state = EmotionalState.fromJson(record);
            _emotionalStates.add(state);
          } catch (e) {
            logger.warning('Error parsing emotional state: $e');
          }
        }

        _isInitialized = true;
        logger.info('MemoryService initialized successfully');
        logger.debug(
            'Loaded ${_conversationMemories.length} memories, ${_insights.length} insights, and ${_emotionalStates.length} emotional states');
      });
    } catch (e) {
      logger.error('Failed to initialize MemoryService', error: e);
      throw Exception('MemoryService initialization failed: $e');
    }
  }

  /// Adds a new conversation memory pair (user message + AI response)
  Future<void> addMemory(String userMessage, String aiResponse,
      {Map<String, dynamic>? metadata}) async {
    await initializeIfNeeded();

    final memory = ConversationMemory(
      userMessage: userMessage,
      aiResponse: aiResponse,
      metadata: metadata ?? {},
    );

    try {
      _conversationMemories.add(memory);

      // Persist to database
      await _databaseProvider.insert('conversation_memories', memory.toJson());

      logger.debug('Added new conversation memory');
    } catch (e) {
      logger.error('Failed to add conversation memory', error: e);
      rethrow;
    }
  }

  /// Adds a new insight discovered during therapy
  Future<void> addInsight(String insight, String source) async {
    await initializeIfNeeded();

    final therapyInsight = TherapyInsight(
      insight: insight,
      source: source,
    );

    try {
      // Add to in-memory cache
      _insights.add(therapyInsight);

      // Persist to database
      await _databaseProvider.insert(
          'therapy_insights', therapyInsight.toJson());

      logger.debug('Added new therapy insight: $insight');
    } catch (e) {
      logger.error('Failed to add therapy insight', error: e);
      rethrow;
    }
  }

  /// Records the user's emotional state
  Future<void> recordEmotionalState(String emotion, double intensity,
      {String? trigger}) async {
    await initializeIfNeeded();

    final state = EmotionalState(
      emotion: emotion,
      intensity: intensity,
      trigger: trigger,
    );

    try {
      // Add to in-memory cache
      _emotionalStates.add(state);

      // Persist to database
      await _databaseProvider.insert('emotional_states', state.toJson());

      logger
          .debug('Recorded emotional state: $emotion (intensity: $intensity)');
    } catch (e) {
      logger.error('Failed to record emotional state', error: e);
      rethrow;
    }
  }

  /// Gets recent conversation memories up to a certain number
  Future<List<ConversationMemory>> getRecentMemories({int limit = 5}) async {
    await initializeIfNeeded();

    // Sort memories by timestamp (most recent first)
    final sortedMemories = List<ConversationMemory>.from(_conversationMemories)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Return up to limit memories
    return sortedMemories.take(limit).toList();
  }

  /// Gets the current memory context as a string for LLM usage
  Future<String> getCurrentContext({int memoryLimit = 5}) async {
    await initializeIfNeeded();

    final StringBuffer contextBuffer = StringBuffer();

    // Add recent conversation history
    final recentMemories = await getRecentMemories(limit: memoryLimit);
    if (recentMemories.isNotEmpty) {
      contextBuffer.writeln('RECENT CONVERSATION HISTORY:');
      for (final memory in recentMemories) {
        contextBuffer.writeln('User: ${memory.userMessage}');
        contextBuffer.writeln('AI: ${memory.aiResponse}');
        contextBuffer.writeln();
      }
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

    // Add emotional states
    if (_emotionalStates.isNotEmpty) {
      contextBuffer.writeln('EMOTIONAL STATES:');
      // Sort states by recency
      final sortedStates = List<EmotionalState>.from(_emotionalStates)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Add most recent emotional state
      if (sortedStates.isNotEmpty) {
        final state = sortedStates.first;
        contextBuffer.writeln(
            '- Current: ${state.emotion} (intensity: ${state.intensity}/10)');
        if (state.trigger != null) {
          contextBuffer.writeln('  Trigger: ${state.trigger}');
        }
      }

      // Add emotional trends if we have enough data
      if (sortedStates.length > 1) {
        contextBuffer.writeln('- Trends: ');
        // Logic for detecting trends would go here
      }

      contextBuffer.writeln();
    }

    return contextBuffer.toString();
  }

  /// Clears all memory (use with caution)
  Future<void> clearMemory() async {
    await initializeIfNeeded();

    try {
      // Clear in-memory caches
      _conversationMemories.clear();
      _insights.clear();
      _emotionalStates.clear();

      // Clear database tables
      await _databaseProvider.delete('conversation_memories');
      await _databaseProvider.delete('therapy_insights');
      await _databaseProvider.delete('emotional_states');

      logger.info('Memory cleared successfully');
    } catch (e) {
      logger.error('Failed to clear memory', error: e);
      rethrow;
    }
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
}
