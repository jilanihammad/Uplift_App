// lib/di/interfaces/i_message_repository.dart

import '../../domain/entities/message.dart';

/// Interface for message repository operations
/// Provides contract for message management in therapy sessions
/// 
/// This interface defines all message-related operations including
/// sending messages, batch operations, AI responses, and message retrieval.
abstract class IMessageRepository {
  
  // Message Sending Operations
  
  /// Send a message in a therapy session
  /// 
  /// [sessionId] - ID of the therapy session
  /// [content] - Message content to send
  /// Returns a [Message] object representing the sent message
  /// 
  /// The message is saved locally first and then queued for server synchronization.
  /// Returns immediately with local message for better UX.
  Future<Message> sendMessage(String sessionId, String content);
  
  /// Send all queued messages in a batch
  /// 
  /// [sessionId] - ID of the therapy session
  /// Returns true if batch send was successful, false otherwise
  /// 
  /// This method processes all messages that have been queued for sending
  /// and synchronizes them with the server in a single batch operation.
  Future<bool> sendQueuedMessages(String sessionId);
  
  // AI Response Operations
  
  /// Get AI response for a user message
  /// 
  /// [sessionId] - ID of the therapy session
  /// [userMessage] - The user message to respond to
  /// Returns a [Message] object containing the AI response
  /// 
  /// Sends the user message to the AI service and returns the generated response.
  /// Falls back to a local response if the AI service is unavailable.
  Future<Message> getAiResponse(String sessionId, String userMessage);
  
  // Message Retrieval Operations
  
  /// Get all messages for a therapy session
  /// 
  /// [sessionId] - ID of the therapy session
  /// Returns a list of [Message] objects ordered by timestamp
  /// 
  /// Attempts to fetch messages from the server first, then falls back
  /// to local database if server is unavailable. Messages are synchronized
  /// with the local database after successful server retrieval.
  Future<List<Message>> getSessionMessages(String sessionId);
}