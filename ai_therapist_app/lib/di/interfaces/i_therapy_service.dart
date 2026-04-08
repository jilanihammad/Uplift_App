// lib/di/interfaces/i_therapy_service.dart
import 'dart:async';
abstract class ITherapyService {
  Future<void> init();
  bool get isInitialized;
  void setTherapistStyle(String systemPrompt);
  Future<String> processUserMessage(
    String userMessage, {
    List<Map<String, String>>? history,
  });
  Future<Map<String, dynamic>> processUserMessageWithStreamingAudio(
    String userMessage,
    List<Map<String, String>> history, {
    required Future<void> Function() onTTSPlaybackComplete,
    required void Function(String) onTTSError,
    void Function(String)? onTTSStart,
  });
  Future<Map<String, dynamic>> endSessionWithMessages(
    List<Map<String, dynamic>> messages, {
    String? sessionTitle,
    int? userId,
  });
}
