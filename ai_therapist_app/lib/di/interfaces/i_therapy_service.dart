// lib/di/interfaces/i_therapy_service.dart
import 'dart:async';
import '../../models/therapy_message.dart';
import '../../models/user_profile.dart';
abstract class ITherapyService {
  Future<String> startSession({
    required String userId,
    String? sessionType,
    Map<String, dynamic>? initialContext,
  });
  Future<void> endSession(String sessionId);
  Future<void> pauseSession(String sessionId);
  Future<void> resumeSession(String sessionId);
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
  Future<void> updateSessionContext(
      String sessionId, Map<String, dynamic> context);
  Future<Map<String, dynamic>?> getSessionContext(String sessionId);
  Future<List<TherapyMessage>> getConversationHistory(String sessionId);
  Future<void> saveMessage(String sessionId, TherapyMessage message);
  Future<void> setTherapyStyle(String sessionId, String therapyStyle);
  Future<void> updateTherapyGoals(String sessionId, List<String> goals);
  Future<void> updateUserProfile(UserProfile profile);
  Future<UserProfile?> getUserProfile(String userId);
  Future<Map<String, dynamic>> getSessionSummary(String sessionId);
  Future<List<String>> getActionItems(String sessionId);
  Future<bool> detectCrisis(String message);
  Future<Map<String, dynamic>> getCrisisResources();
  Future<void> trackMoodChange(String sessionId, String mood);
  Future<Map<String, dynamic>> getProgressMetrics(String userId);
  Future<Map<String, dynamic>> processUserMessageWithStreamingAudio(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
    void Function(String)? onTTSStart,
  });
  Future<String> processUserMessage(
    String userMessage, {
    List<Map<String, String>>? history,
  });
  Future<void> init();
  Future<void> initialize();
  void dispose();
  bool get isInitialized;
  String? get currentSessionId;
  void setTherapistStyle(String systemPrompt);
  Future<Map<String, dynamic>> endSessionWithMessages(
    List<Map<String, dynamic>> messages, {
    String? sessionTitle,
    int? userId,
  });
}
