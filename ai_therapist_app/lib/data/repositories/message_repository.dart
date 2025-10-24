// lib/data/repositories/message_repository.dart
import '../../domain/entities/message.dart';
import '../../utils/logging_service.dart';
import '../../di/interfaces/i_message_repository.dart';
import '../../di/interfaces/i_api_client.dart';
import '../../di/interfaces/i_app_database.dart';
import 'dart:collection';

class MessageRepository implements IMessageRepository {
  final IApiClient apiClient;
  final IAppDatabase appDatabase;

  // Queue to hold unsent messages for batching
  final Queue<Map<String, dynamic>> _messageQueue =
      Queue<Map<String, dynamic>>();

  MessageRepository({
    required this.apiClient,
    required this.appDatabase,
  });

  // Send a message
  @override
  Future<Message> sendMessage(String sessionId, String content) async {
    final now = DateTime.now();
    final String localId = 'local_${now.millisecondsSinceEpoch}';

    // Save user message to local database first
    await appDatabase.insert('messages', {
      'id': localId,
      'session_id': sessionId,
      'content': content,
      'is_user': 1,
      'timestamp': now.toIso8601String(),
      'is_synced': 0,
    });

    try {
      // Prepare message data
      final messageData = {
        'content': content,
        'is_user': true,
        'timestamp': now.toIso8601String(),
        'local_id': localId,
      };

      // Add to message queue for batch sending
      _messageQueue.add(messageData);

      // For immediate response, create a local message
      return Message(
        id: localId,
        sessionId: sessionId,
        content: content,
        isUser: true,
        timestamp: now,
        isSynced: false,
      );
    } catch (e) {
      logger.error('Error queueing message: $e');
      // Return local message if error
      return Message(
        id: localId,
        sessionId: sessionId,
        content: content,
        isUser: true,
        timestamp: now,
        isSynced: false,
      );
    }
  }

  // Send all queued messages in a batch
  @override
  Future<bool> sendQueuedMessages(String sessionId) async {
    if (_messageQueue.isEmpty) {
      logger.debug('No messages queued for batch sending');
      return true;
    }

    logger.debug(
        'Sending batch of ${_messageQueue.length} messages for session $sessionId');

    try {
      // Convert queue to list for the API call
      final List<Map<String, dynamic>> messages = List.from(_messageQueue);

      // Send batch request to server
      final response = await apiClient.post(
        '/sessions/$sessionId/messages/batch',
        {'messages': messages},
      );

      // Mark messages as synced in the database
      for (int i = 0; i < messages.length; i++) {
        final message = messages[i];
        final localId = message['local_id'];

        if (response['message_ids'] != null &&
            i < response['message_ids'].length) {
          final serverId = response['message_ids'][i];

          // Update local database with server ID
          await appDatabase.update(
            'messages',
            {
              'id': serverId,
              'is_synced': 1,
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
        }
      }

      // Clear the queue after successful sync
      _messageQueue.clear();
      return true;
    } catch (e) {
      logger.error('Error sending batch messages: $e');
      return false;
    }
  }

  // Get response from AI
  @override
  Future<Message> getAiResponse(String sessionId, String userMessage) async {
    try {
      // Get AI response from server
      final response = await apiClient.post(
        '/api/v1/sessions/$sessionId/ai-response',
        {
          'user_message': userMessage,
        },
      );

      final message = Message.fromJson(response);

      // Save AI response to local database
      await appDatabase.insert('messages', {
        'id': message.id,
        'session_id': sessionId,
        'content': message.content,
        'is_user': 0,
        'timestamp': message.timestamp.toIso8601String(),
        'is_synced': 1,
      });

      return message;
    } catch (e) {
      // Generate a simple local response if API call fails
      final now = DateTime.now();
      final String localId = 'local_ai_${now.millisecondsSinceEpoch}';
      const String fallbackResponse =
          "I'm having trouble connecting to the server. "
          "Can you tell me more about how you're feeling?";

      await appDatabase.insert('messages', {
        'id': localId,
        'session_id': sessionId,
        'content': fallbackResponse,
        'is_user': 0,
        'timestamp': now.toIso8601String(),
        'is_synced': 0,
      });

      return Message(
        id: localId,
        sessionId: sessionId,
        content: fallbackResponse,
        isUser: false,
        timestamp: now,
        isSynced: false,
      );
    }
  }

  // Get messages for a session
  @override
  Future<List<Message>> getSessionMessages(String sessionId) async {
    try {
      // Try to get messages from server
      final response =
          await apiClient.get('/api/v1/sessions/$sessionId/messages');
      final List<dynamic> messagesJson =
          response['data'] ?? response['messages'] ?? response;

      final messages =
          messagesJson.map((json) => Message.fromJson(json)).toList();

      // Update local database
      for (final message in messages) {
        await appDatabase.insert('messages', {
          'id': message.id,
          'session_id': message.sessionId,
          'content': message.content,
          'is_user': message.isUser ? 1 : 0,
          'timestamp': message.timestamp.toIso8601String(),
          'is_synced': 1,
        });
      }

      return messages;
    } catch (e) {
      // Get messages from local database if API call fails
      final results = await appDatabase.query(
        'messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ASC',
      );

      return results
          .map((data) => Message(
                id: data['id'] as String,
                sessionId: data['session_id'] as String,
                content: data['content'] as String,
                isUser: (data['is_user'] as int) == 1,
                timestamp: DateTime.parse(data['timestamp'] as String),
                isSynced: (data['is_synced'] as int) == 1,
              ))
          .toList();
    }
  }
}
