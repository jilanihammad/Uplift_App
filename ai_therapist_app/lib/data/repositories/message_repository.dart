// lib/data/repositories/message_repository.dart
import '../datasources/remote/api_client.dart';
import '../datasources/local/app_database.dart';
import '../../domain/entities/message.dart';

class MessageRepository {
  final ApiClient apiClient;
  final AppDatabase appDatabase;
  
  MessageRepository({
    required this.apiClient,
    required this.appDatabase,
  });
  
  // Send a message
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
      // Send message to server
      final response = await apiClient.post(
        '/api/v1/sessions/$sessionId/messages',
        body: {
          'content': content,
        },
      );
      
      final message = Message.fromJson(response);
      
      // Update local database with server ID
      await appDatabase.update(
        'messages',
        {
          'id': message.id,
          'is_synced': 1,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );
      
      return message;
    } catch (e) {
      // Return local message if API call fails
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
  
  // Get response from AI
  Future<Message> getAiResponse(String sessionId, String userMessage) async {
    try {
      // Get AI response from server
      final response = await apiClient.post(
        '/api/v1/sessions/$sessionId/ai-response',
        body: {
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
      final String fallbackResponse = "I'm having trouble connecting to the server. "
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
  Future<List<Message>> getSessionMessages(String sessionId) async {
    try {
      // Try to get messages from server
      final response = await apiClient.get('/api/v1/sessions/$sessionId/messages');
      final List<dynamic> messagesJson = response;
      
      final messages = messagesJson
          .map((json) => Message.fromJson(json))
          .toList();
      
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
      
      return results.map((data) => Message(
        id: data['id'] as String,
        sessionId: data['session_id'] as String,
        content: data['content'] as String,
        isUser: (data['is_user'] as int) == 1,
        timestamp: DateTime.parse(data['timestamp'] as String),
        isSynced: (data['is_synced'] as int) == 1,
      )).toList();
    }
  }
}