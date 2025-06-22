// lib/di/interfaces/i_therapy_service.dart

import 'dart:async';
import '../../models/therapy_message.dart';
import '../../models/user_profile.dart';

/// Interface for therapy service operations
/// Provides contract for AI therapy functionality
abstract class ITherapyService {
  // Session management
  Future<String> startSession({
    required String userId,
    String? sessionType,
    Map<String, dynamic>? initialContext,
  });
  
  Future<void> endSession(String sessionId);
  Future<void> pauseSession(String sessionId);
  Future<void> resumeSession(String sessionId);
  
  // Message processing
  Future<TherapyMessage> processMessage({
    required String sessionId,
    required String userMessage,
    Map<String, dynamic>? context,
  });
  
  Future<String> generateResponse({
    required String sessionId,
    required String userMessage,
    Map<String, dynamic>? context,
  });
  
  // Context management
  Future<void> updateSessionContext(String sessionId, Map<String, dynamic> context);
  Future<Map<String, dynamic>?> getSessionContext(String sessionId);
  
  // Conversation history
  Future<List<TherapyMessage>> getConversationHistory(String sessionId);
  Future<void> saveMessage(String sessionId, TherapyMessage message);
  
  // Therapy configuration
  Future<void> setTherapyStyle(String sessionId, String therapyStyle);
  Future<void> updateTherapyGoals(String sessionId, List<String> goals);
  
  // User profile integration
  Future<void> updateUserProfile(UserProfile profile);
  Future<UserProfile?> getUserProfile(String userId);
  
  // Session analytics
  Future<Map<String, dynamic>> getSessionSummary(String sessionId);
  Future<List<String>> getActionItems(String sessionId);
  
  // Crisis detection
  Future<bool> detectCrisis(String message);
  Future<Map<String, dynamic>> getCrisisResources();
  
  // Progress tracking
  Future<void> trackMoodChange(String sessionId, String mood);
  Future<Map<String, dynamic>> getProgressMetrics(String userId);
  
  // Audio processing (specific to current implementation)
  Future<Map<String, dynamic>> processUserMessageWithStreamingAudio(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
  });
  
  Future<String> processUserMessage(String userMessage, {
    List<Map<String, String>>? history,
  });
  
  // Initialization and cleanup
  Future<void> init();
  Future<void> initialize();
  void dispose();
  
  // State
  bool get isInitialized;
  String? get currentSessionId;
  
  // Additional methods for backward compatibility
  void setTherapistStyle(String systemPrompt);
  Future<Map<String, dynamic>> endSessionWithMessages(List<Map<String, dynamic>> messages);
}