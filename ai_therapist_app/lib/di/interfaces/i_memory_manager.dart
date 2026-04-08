// lib/di/interfaces/i_memory_manager.dart
import 'dart:async';
abstract class IMemoryManager {
  Future<void> initializeOnlyIfNeeded();
  Future<String> getMemoryContext();
  Future<void> addInteraction(
      String userMessage, String aiResponse, Map<String, dynamic> metadata);
  Future<void> addInsight(String insightText, String source);
  Future<void> updateEmotionalState(
      String emotion, double intensity, String? trigger);
  Future<void> updateUserPreference(String key, dynamic value);
  Future<void> updateTherapeuticGoals(List<String> goals);
  Future<void> processInsightsAndSaveMemory(String userMessage,
      Map<String, dynamic> response, Map<String, dynamic> graphResult);
  Future<String> getAnchorGuidance(
      String userMessage, Map<String, dynamic> graphResult);
}
