import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/conversation_memory.dart';
import '../services/memory_service.dart';
import '../utils/logger_util.dart';

/// Handles management of conversation memory and context for therapy sessions
class MemoryManager {
  // The underlying memory service
  final MemoryService _memoryService;

  // Initialization status
  bool _isInitialized = false;

  // Constructor
  MemoryManager({required MemoryService memoryService})
      : _memoryService = memoryService;

  /// Initialize the memory manager
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _memoryService.init();
      _isInitialized = true;
      log.i('Memory manager initialized successfully');
    } catch (e) {
      log.e('Failed to initialize memory manager', e);
    }
  }

  /// Check if already initialized
  bool get isInitialized => _isInitialized;

  /// Initialize only if not already initialized
  Future<void> initializeOnlyIfNeeded() async {
    if (!_isInitialized) {
      await init();
    }
  }

  /// Get relevant context for the current conversation
  Future<String> getMemoryContext() async {
    try {
      return await _memoryService.getMemoryContext();
    } catch (e) {
      log.e('Error retrieving memory context', e);
      return '';
    }
  }

  /// Add interaction between user and AI to memory
  Future<void> addInteraction(String userMessage, String aiResponse,
      Map<String, dynamic> metadata) async {
    try {
      await _memoryService.addInteraction(userMessage, aiResponse, metadata);
      log.d('Interaction added to memory');
    } catch (e) {
      log.e('Error adding interaction to memory', e);
    }
  }

  /// Add an insight to memory
  Future<void> addInsight(String insightText, String source) async {
    try {
      await _memoryService.addInsight(insightText, source);
      log.d('Insight added to memory: $insightText');
    } catch (e) {
      log.e('Error adding insight to memory', e);
    }
  }

  /// Update the emotional state in memory
  Future<void> updateEmotionalState(
      String emotion, double intensity, String? trigger) async {
    try {
      await _memoryService.updateEmotionalState(emotion, intensity, trigger);
      log.d(
          'Emotional state updated: $emotion (${intensity.toStringAsFixed(1)}/10)');
    } catch (e) {
      log.e('Error updating emotional state', e);
    }
  }

  /// Update user preferences
  Future<void> updateUserPreference(String key, dynamic value) async {
    try {
      await _memoryService.updateUserPreference(key, value);
      log.d('User preference updated: $key');
    } catch (e) {
      log.e('Error updating user preference', e);
    }
  }

  /// Update therapeutic goals
  Future<void> updateTherapeuticGoals(List<String> goals) async {
    try {
      await _memoryService.updateTherapeuticGoals(goals);
      log.d('Therapeutic goals updated: ${goals.join(", ")}');
    } catch (e) {
      log.e('Error updating therapeutic goals', e);
    }
  }

  /// Process insights from a response and save to memory
  Future<void> processInsightsAndSaveMemory(String userMessage,
      Map<String, dynamic> response, Map<String, dynamic> graphResult) async {
    try {
      // Extract any insights detected in the response
      if (response.containsKey('insights') && response['insights'] != null) {
        final insights = response['insights'];
        if (insights is List && insights.isNotEmpty) {
          for (final insight in insights) {
            await addInsight(insight, 'ai');
          }
        }
      }

      // Save interaction to memory
      await addInteraction(userMessage, response['response'], {
        'state': graphResult['state'] ?? 'exploration',
        'emotion': graphResult['analysis']?['emotion'] ?? 'neutral',
        'topics': graphResult['analysis']?['topics'] ?? [],
      });

      // Extract any detected emotional state
      if (graphResult.containsKey('analysis') &&
          graphResult['analysis'] != null &&
          graphResult['analysis'].containsKey('emotion') &&
          graphResult['analysis'].containsKey('emotionIntensity')) {
        await updateEmotionalState(
            graphResult['analysis']['emotion'],
            graphResult['analysis']['emotionIntensity'],
            userMessage.length > 50
                ? userMessage.substring(0, 50) + '...'
                : userMessage);
      }
    } catch (e) {
      log.e('Error processing insights and saving memory', e);
    }
  }

  /// Get memory context in background process
  static Future<String> getMemoryContextBackground(
      MemoryService memoryService) async {
    try {
      return await memoryService.getMemoryContext();
    } catch (e) {
      print('Error getting memory context in background: $e');
      return '';
    }
  }
}
