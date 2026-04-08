// lib/di/interfaces/i_message_repository.dart
import '../../domain/entities/message.dart';
abstract class IMessageRepository {
  Future<Message> sendMessage(String sessionId, String content);
  Future<bool> sendQueuedMessages(String sessionId);
  Future<Message> getAiResponse(String sessionId, String userMessage);
  Future<List<Message>> getSessionMessages(String sessionId);
}
