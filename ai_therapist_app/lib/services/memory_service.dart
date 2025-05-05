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
import '../utils/database_helper.dart';

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
        // First ensure database provider is initialized
        await _databaseProvider.init();

        // Verify required tables exist, create them if they don't
        await _ensureTablesExist();

        // Load conversation memories from database
        await _loadConversationMemories();

        // Load insights from database
        await _loadInsights();

        // Load emotional states from database
        await _loadEmotionalStates();

        _isInitialized = true;
        logger.info('MemoryService initialized successfully');
        logger.debug(
            'Loaded ${_conversationMemories.length} memories, ${_insights.length} insights, and ${_emotionalStates.length} emotional states');
      });
    } catch (e) {
      logger.error('Failed to initialize MemoryService', error: e);
      _isInitialized = false;
      throw Exception('MemoryService initialization failed: $e');
    }
  }

  /// Ensure all required tables exist in the database
  Future<void> _ensureTablesExist() async {
    try {
      // Get DatabaseOperationManager to prevent database locks
      final dbOpManager = serviceLocator<DatabaseOperationManager>();

      // Check if required tables exist - this should be read-only
      final convMemoriesExists = await dbOpManager.queueOperation<bool>(
        () => _databaseProvider.tableExists('conversation_memories'),
        name: 'check-conversation-memories-exists',
        isReadOnly: true,
      );

      final therapyInsightsExists = await dbOpManager.queueOperation<bool>(
        () => _databaseProvider.tableExists('therapy_insights'),
        name: 'check-therapy-insights-exists',
        isReadOnly: true,
      );

      final emotionalStatesExists = await dbOpManager.queueOperation<bool>(
        () => _databaseProvider.tableExists('emotional_states'),
        name: 'check-emotional-states-exists',
        isReadOnly: true,
      );

      logger.debug(
          'Table check: conversation_memories=[32m$convMemoriesExists[0m, therapy_insights=[32m$therapyInsightsExists[0m, emotional_states=[32m$emotionalStatesExists[0m');

      // If any table is missing, log and throw
      if (!convMemoriesExists ||
          !therapyInsightsExists ||
          !emotionalStatesExists) {
        final missing = [
          if (!convMemoriesExists) 'conversation_memories',
          if (!therapyInsightsExists) 'therapy_insights',
          if (!emotionalStatesExists) 'emotional_states',
        ];
        logger.error(
            'Missing required database tables: [31m${missing.join(', ')}[0m');
        throw Exception(
            'Missing required database tables: ${missing.join(', ')}');
      }
    } catch (e) {
      logger.error('Error checking required tables', error: e);
      throw Exception('Failed to verify required database tables: $e');
    }
  }

  /// Load conversation memories from database with better error handling
  Future<void> _loadConversationMemories() async {
    try {
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
      logger.debug(
          'Loaded ${_conversationMemories.length} conversation memories');
    } catch (e) {
      // Fall back to old table name if needed
      try {
        logger.warning(
            'Failed to load from conversation_memories, trying conversations table');
        final memoryRecords = await _databaseProvider.query(
          'conversations',
          orderBy: 'timestamp DESC',
        );

        _conversationMemories.clear();
        for (final record in memoryRecords) {
          try {
            final memory = ConversationMemory.fromJson(record);
            _conversationMemories.add(memory);
          } catch (e) {
            logger.warning('Error parsing conversation from old table: $e');
          }
        }
        logger.debug(
            'Loaded ${_conversationMemories.length} conversations from legacy table');
      } catch (fallbackError) {
        logger.error('Failed to load conversation memories from either table',
            error: fallbackError);
        // Continue with empty memories rather than crashing
      }
    }
  }

  /// Load insights from database with better error handling
  Future<void> _loadInsights() async {
    try {
      final insightRecords = await _databaseProvider.query('therapy_insights');
      _insights.clear();
      for (final record in insightRecords) {
        try {
          final insight = TherapyInsight.fromJson(record);
          _insights.add(insight);
        } catch (e) {
          logger.warning('Error parsing therapy insight: $e');
        }
      }
      logger.debug('Loaded ${_insights.length} therapy insights');
    } catch (e) {
      // Fall back to old table name if needed
      try {
        logger.warning(
            'Failed to load from therapy_insights, trying insights table');
        final insightRecords = await _databaseProvider.query('insights');
        _insights.clear();
        for (final record in insightRecords) {
          try {
            final insight = TherapyInsight.fromJson(record);
            _insights.add(insight);
          } catch (e) {
            logger.warning('Error parsing insight from old table: $e');
          }
        }
        logger.debug('Loaded ${_insights.length} insights from legacy table');
      } catch (fallbackError) {
        logger.error('Failed to load insights from either table',
            error: fallbackError);
        // Continue with empty insights rather than crashing
      }
    }
  }

  /// Load emotional states from database with better error handling
  Future<void> _loadEmotionalStates() async {
    try {
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
      logger.debug('Loaded ${_emotionalStates.length} emotional states');
    } catch (e) {
      logger.error('Failed to load emotional states', error: e);
      // Continue with empty emotional states rather than crashing
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

      // Convert to database format (snake_case field names)
      final Map<String, dynamic> dbData = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'user_message': userMessage,
        'ai_response': aiResponse,
        'metadata': jsonEncode(metadata ?? {}),
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Persist to database
      try {
        await _databaseProvider.insert('conversation_memories', dbData);
      } catch (e) {
        logger.error(
            'Failed to insert into conversation_memories, trying fallback',
            error: e);
        // Try inserting into the legacy table as fallback
        try {
          await _databaseProvider.insert('conversations', dbData);
          logger.debug('Added memory to legacy conversations table');
        } catch (fallbackError) {
          logger.error('Failed to save memory to any database table',
              error: fallbackError);
          // Already added to in-memory cache, so continue
        }
      }

      logger.debug('Added new conversation memory');
    } catch (e) {
      logger.error('Failed to add conversation memory', error: e);
      // Don't rethrow to prevent app crashes
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
      try {
        await _databaseProvider.insert(
            'therapy_insights', therapyInsight.toJson());
      } catch (e) {
        logger.error('Failed to insert into therapy_insights, trying fallback',
            error: e);
        // Try inserting into the legacy table as fallback
        try {
          await _databaseProvider.insert('insights', therapyInsight.toJson());
          logger.debug('Added insight to legacy insights table');
        } catch (fallbackError) {
          logger.error('Failed to save insight to any database table',
              error: fallbackError);
          // Already added to in-memory cache, so continue
        }
      }

      logger.debug('Added new therapy insight: $insight');
    } catch (e) {
      logger.error('Failed to add therapy insight', error: e);
      // Don't rethrow to prevent app crashes
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
      try {
        await _databaseProvider.insert('emotional_states', state.toJson());
        logger.debug(
            'Recorded emotional state: $emotion (intensity: $intensity)');
      } catch (e) {
        logger.error('Failed to save emotional state to database', error: e);
        // Already added to in-memory cache, so continue
      }
    } catch (e) {
      logger.error('Failed to record emotional state', error: e);
      // Don't rethrow to prevent app crashes
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

      // Clear database tables with error handling
      try {
        await _databaseProvider.delete('conversation_memories');
      } catch (e) {
        logger.warning('Failed to clear conversation_memories table: $e');
        try {
          await _databaseProvider.delete('conversations');
        } catch (e2) {
          logger.warning('Failed to clear conversations table: $e2');
        }
      }

      try {
        await _databaseProvider.delete('therapy_insights');
      } catch (e) {
        logger.warning('Failed to clear therapy_insights table: $e');
        try {
          await _databaseProvider.delete('insights');
        } catch (e2) {
          logger.warning('Failed to clear insights table: $e2');
        }
      }

      try {
        await _databaseProvider.delete('emotional_states');
      } catch (e) {
        logger.warning('Failed to clear emotional_states table: $e');
      }

      logger.info('Memory cleared successfully');
    } catch (e) {
      logger.error('Failed to clear memory', error: e);
      // Don't rethrow to prevent app crashes
    }
  }

  // Helper method to get the minimum of two numbers
  int min(int a, int b) {
    return a < b ? a : b;
  }
}
