// lib/di/interfaces/i_memory_manager.dart

import 'dart:async';

/// Interface for memory management operations
/// Provides contract for conversation memory and context management
abstract class IMemoryManager {
  // Memory operations
  Future<void> storeMemory(
    String sessionId,
    String content, {
    Map<String, dynamic>? metadata,
    List<String>? tags,
  });

  Future<List<Map<String, dynamic>>> retrieveMemories(
    String sessionId, {
    String? query,
    List<String>? tags,
    int limit = 10,
  });

  Future<void> updateMemory(
    String memoryId,
    String content, {
    Map<String, dynamic>? metadata,
  });

  Future<void> deleteMemory(String memoryId);
  Future<void> clearSessionMemories(String sessionId);

  // Context management
  Future<void> updateContext(String sessionId, Map<String, dynamic> context);
  Future<Map<String, dynamic>?> getContext(String sessionId);
  Future<void> clearContext(String sessionId);

  // Conversation history
  Future<void> addToHistory(
    String sessionId,
    String role,
    String content, {
    Map<String, dynamic>? metadata,
  });

  Future<List<Map<String, dynamic>>> getHistory(
    String sessionId, {
    int limit = 50,
    String? fromTimestamp,
  });

  Future<void> summarizeHistory(String sessionId);

  // Memory analytics
  Future<Map<String, dynamic>> getMemoryStats(String sessionId);
  Future<List<String>> extractKeyTopics(String sessionId);
  Future<Map<String, double>> getSentimentAnalysis(String sessionId);

  // Search and retrieval
  Future<List<Map<String, dynamic>>> searchMemories(
    String query, {
    String? sessionId,
    List<String>? tags,
    double threshold = 0.7,
  });

  Future<List<Map<String, dynamic>>> getRelatedMemories(
    String memoryId, {
    int limit = 5,
    double threshold = 0.8,
  });

  // Lifecycle management
  Future<void> initialize();
  Future<void> initializeOnlyIfNeeded();
  void dispose();

  // State
  bool get isInitialized;
  int get memoryCount;
}
