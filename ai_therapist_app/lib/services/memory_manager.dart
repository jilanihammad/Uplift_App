import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/conversation_memory.dart';
import '../services/memory_service.dart';
import '../utils/logging_service.dart';
import '../di/initialization_tracker.dart';

/// Handles management of conversation memory and context for therapy sessions
class MemoryManager {
  // The underlying memory service
  final MemoryService _memoryService;

  // Initialization status
  bool _isInitialized = false;

  // Error state tracking
  String? _lastInitError;
  int _initAttempts = 0;
  static const int _maxInitAttempts = 3;

  // Constructor
  MemoryManager({required MemoryService memoryService})
      : _memoryService = memoryService;

  /// Initialize the memory manager
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _initAttempts++;
      logger.debug(
          'Initializing MemoryManager (attempt $_initAttempts of $_maxInitAttempts)');

      // Use initialization tracker for consistent initialization pattern
      final success =
          await initTracker.initializeWithRetry('MemoryManager', () async {
        await _memoryService.initializeIfNeeded();
        _isInitialized = true;
        _lastInitError = null;
      });

      if (success) {
        logger.info('Memory manager initialized successfully');
      } else {
        _isInitialized = false;
        _lastInitError = 'Failed to initialize after multiple attempts';
        logger
            .error('Failed to initialize memory manager after maximum retries');
      }
    } catch (e) {
      _lastInitError = e.toString();
      logger.error('Failed to initialize memory manager', error: e);

      // Allow continued operation with limited functionality even after failed init
      _isInitialized = false;
    }
  }

  /// Check if already initialized
  bool get isInitialized => _isInitialized;

  /// Get the last initialization error
  String? get lastInitError => _lastInitError;

  /// Initialize only if not already initialized
  Future<void> initializeIfNeeded() async {
    if (!_isInitialized && _initAttempts < _maxInitAttempts) {
      await init();
    }
  }

  /// Legacy method for backward compatibility
  Future<void> initializeOnlyIfNeeded() async {
    return initializeIfNeeded();
  }

  /// Get relevant context for the current conversation
  Future<String> getMemoryContext() async {
    try {
      await _safeInitialize();
      return await _memoryService.getCurrentContext();
    } catch (e) {
      logger.error('Error retrieving memory context', error: e);
      return ''; // Return empty context on error
    }
  }

  /// Add interaction between user and AI to memory
  Future<void> addInteraction(String userMessage, String aiResponse,
      Map<String, dynamic> metadata) async {
    try {
      await _safeInitialize();
      await _memoryService.addMemory(userMessage, aiResponse,
          metadata: metadata);
      logger.debug('Interaction added to memory');
    } catch (e) {
      logger.error('Error adding interaction to memory', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Add an insight to memory
  Future<void> addInsight(String insightText, String source) async {
    try {
      await _safeInitialize();
      await _memoryService.addInsight(insightText, source);
      logger.debug('Insight added to memory: $insightText');
    } catch (e) {
      logger.error('Error adding insight to memory', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Update the emotional state in memory
  Future<void> updateEmotionalState(
      String emotion, double intensity, String? trigger) async {
    try {
      await _safeInitialize();
      await _memoryService.recordEmotionalState(emotion, intensity,
          trigger: trigger);
      logger.debug(
          'Emotional state updated: $emotion (${intensity.toStringAsFixed(1)}/10)');
    } catch (e) {
      logger.error('Error updating emotional state', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Update user preferences - this is no longer supported in the new implementation
  Future<void> updateUserPreference(String key, dynamic value) async {
    try {
      await _safeInitialize();
      // Add a fallback implementation using insights
      await _memoryService.addInsight(
          'User preference: $key = $value', 'system');
      logger.debug('User preference saved as insight: $key');
    } catch (e) {
      logger.error('Error saving user preference', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Update therapeutic goals - this is no longer supported in the new implementation
  Future<void> updateTherapeuticGoals(List<String> goals) async {
    try {
      await _safeInitialize();
      // Add a fallback implementation using insights
      await _memoryService.addInsight(
          'Therapeutic goals: ${goals.join(", ")}', 'system');
      logger.debug('Therapeutic goals saved as insight: ${goals.join(", ")}');
    } catch (e) {
      logger.error('Error saving therapeutic goals', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Process insights from a response and save to memory
  Future<void> processInsightsAndSaveMemory(String userMessage,
      Map<String, dynamic> response, Map<String, dynamic> graphResult) async {
    try {
      await _safeInitialize();

      // Extract any insights detected in the response
      if (response.containsKey('insights') && response['insights'] != null) {
        final insights = response['insights'];
        if (insights is List && insights.isNotEmpty) {
          for (final insight in insights) {
            try {
              await addInsight(insight, 'ai');
            } catch (e) {
              logger.warning('Error saving individual insight: $e');
              // Continue with next insight
            }
          }
        }
      }

      // Save interaction to memory
      try {
        await addInteraction(userMessage, response['response'], {
          'state': graphResult['state'] ?? 'exploration',
          'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
          'topics': graphResult['analysis']?['topics'] ?? [],
        });
      } catch (e) {
        logger.warning('Error saving interaction to memory: $e');
      }

      // Extract any detected emotional state
      if (graphResult.containsKey('analysis') &&
          graphResult['analysis'] != null &&
          graphResult['analysis'].containsKey('emotion') &&
          graphResult['analysis'].containsKey('emotionIntensity')) {
        try {
          await updateEmotionalState(
              graphResult['analysis']['emotion'],
              graphResult['analysis']['emotionIntensity'],
              userMessage.length > 50
                  ? userMessage.substring(0, 50) + '...'
                  : userMessage);
        } catch (e) {
          logger.warning('Error updating emotional state: $e');
        }
      }
    } catch (e) {
      logger.error('Error processing insights and saving memory', error: e);
      // Fail gracefully - don't throw
    }
  }

  /// Safely initialize the service, handling errors gracefully
  Future<void> _safeInitialize() async {
    if (_isInitialized) return;

    try {
      if (_initAttempts < _maxInitAttempts) {
        await initializeIfNeeded();
      } else if (_initAttempts == _maxInitAttempts) {
        // One final attempt
        _initAttempts++;
        logger.warning('Making final attempt to initialize MemoryManager');
        await _memoryService.initializeIfNeeded();
        _isInitialized = true;
        logger.info('MemoryManager initialized successfully on final attempt');
      }
    } catch (e) {
      // Log but allow operation to continue
      logger.error('Failed to initialize in _safeInitialize', error: e);
    }
  }

  /// Get memory context in background process
  static Future<String> getMemoryContextBackground(
      MemoryService memoryService) async {
    try {
      return await memoryService.getCurrentContext();
    } catch (e) {
      logger.error('Error getting memory context in background', error: e);
      return '';
    }
  }
}
