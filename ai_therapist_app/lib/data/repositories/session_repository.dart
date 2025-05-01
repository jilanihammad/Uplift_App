// lib/data/repositories/session_repository.dart
import '../datasources/remote/api_client.dart';
import '../datasources/local/app_database.dart';
import '../../domain/entities/session.dart';
import '../../data/repositories/message_repository.dart';

class SessionRepository {
  final ApiClient apiClient;
  final AppDatabase appDatabase;

  SessionRepository({
    required this.apiClient,
    required this.appDatabase,
  });

  // Create a new session
  Future<Session> createSession(String title, {String? id}) async {
    // Try to create session on the server
    try {
      final response = await apiClient.post(
        '/sessions',
        body: {
          'title': title,
          'id': id, // Include the ID if provided
        },
      );

      final session = Session.fromJson(response);

      // Save to local database
      await appDatabase.insert('sessions', {
        'id': id ??
            session.id, // Use the provided ID or the one from the response
        'title': session.title,
        'summary': session.summary,
        'created_at': session.createdAt.toIso8601String(),
        'last_modified': session.lastModified.toIso8601String(),
        'is_synced': 1,
      });

      return session;
    } catch (e) {
      // Create local session if API call fails
      final String localId =
          id ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().toIso8601String();

      await appDatabase.insert('sessions', {
        'id': localId,
        'title': title,
        'summary': '',
        'created_at': now,
        'last_modified': now,
        'is_synced': 0,
      });

      return Session(
        id: localId,
        title: title,
        summary: '',
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        isSynced: false,
      );
    }
  }

  // Get all sessions
  Future<List<Session>> getSessions() async {
    try {
      // Try to get sessions from the server
      final response = await apiClient.get('/sessions');
      final List<dynamic> sessionsJson = response;

      final sessions =
          sessionsJson.map((json) => Session.fromJson(json)).toList();

      // Update local database
      for (final session in sessions) {
        await appDatabase.insert('sessions', {
          'id': session.id,
          'title': session.title,
          'summary': session.summary,
          'created_at': session.createdAt.toIso8601String(),
          'last_modified': session.lastModified.toIso8601String(),
          'is_synced': 1,
        });
      }

      return sessions;
    } catch (e) {
      // Get sessions from local database if API call fails
      final results = await appDatabase.query('sessions');

      return results
          .map((data) => Session(
                id: data['id'] as String,
                title: data['title'] as String,
                summary: data['summary'] as String,
                createdAt: DateTime.parse(data['created_at'] as String),
                lastModified: DateTime.parse(data['last_modified'] as String),
                isSynced: (data['is_synced'] as int) == 1,
              ))
          .toList();
    }
  }

  // Get a specific session
  Future<Session> getSession(String sessionId) async {
    try {
      // Try to get session from the server
      final response = await apiClient.get('/sessions/$sessionId');
      return Session.fromJson(response);
    } catch (e) {
      // Get session from local database if API call fails
      final results = await appDatabase.query(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      if (results.isEmpty) {
        throw Exception('Session not found');
      }

      final data = results.first;
      return Session(
        id: data['id'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        createdAt: DateTime.parse(data['created_at'] as String),
        lastModified: DateTime.parse(data['last_modified'] as String),
        isSynced: (data['is_synced'] as int) == 1,
      );
    }
  }

  // Update a session
  Future<Session> updateSession(
    String sessionId, {
    String? title,
    String? summary,
  }) async {
    final now = DateTime.now();

    try {
      // Try to update on the server
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (summary != null) body['summary'] = summary;

      final response = await apiClient.patch(
        '/sessions/$sessionId',
        body: body,
      );

      final session = Session.fromJson(response);

      // Update local database
      await appDatabase.update(
        'sessions',
        {
          'title': session.title,
          'summary': session.summary,
          'last_modified': session.lastModified.toIso8601String(),
          'is_synced': 1,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      return session;
    } catch (e) {
      // Update locally if API call fails
      final updateData = <String, dynamic>{
        'last_modified': now.toIso8601String(),
        'is_synced': 0,
      };

      if (title != null) updateData['title'] = title;
      if (summary != null) updateData['summary'] = summary;

      await appDatabase.update(
        'sessions',
        updateData,
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      // Get updated session from local database
      final results = await appDatabase.query(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      final data = results.first;
      return Session(
        id: data['id'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        createdAt: DateTime.parse(data['created_at'] as String),
        lastModified: DateTime.parse(data['last_modified'] as String),
        isSynced: false,
      );
    }
  }

  // Delete a session
  Future<void> deleteSession(String sessionId) async {
    try {
      // Try to delete on server
      await apiClient.delete('/sessions/$sessionId');
    } catch (e) {
      // Ignore API errors
    } finally {
      // Always delete from local database
      await appDatabase.delete(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    }
  }

  // Save a completed therapy session
  Future<Session> saveSession({
    required String id,
    required List<dynamic> messages,
    required String summary,
    List<String>? actionItems,
    dynamic initialMood,
    required MessageRepository messageRepository,
  }) async {
    final now = DateTime.now();
    // Use a default title if initialMood is null
    final String title = initialMood != null
        ? 'Session when feeling ${initialMood.toString().split('.').last}'
        : 'Therapy Session';

    try {
      // First, send any queued messages in batch
      await messageRepository.sendQueuedMessages(id);

      // Then, update the session details
      final sessionData = {
        'title': title,
        'summary': summary,
        'action_items': actionItems ?? [],
        'initial_mood': initialMood?.toString(),
      };

      // Try to save to server
      try {
        final response = await apiClient.patch(
          '/sessions/$id',
          body: sessionData,
        );

        // Save messages to local DB
        _saveMessagesToLocalDB(id, messages, now);

        final session = Session.fromJson(response);

        // Update local database
        await appDatabase.update(
          'sessions',
          {
            'id': session.id,
            'title': session.title,
            'summary': session.summary ?? '',
            'last_modified': session.lastModified.toIso8601String(),
            'is_synced': 1,
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        return session;
      } catch (e) {
        print('Error saving session to server: $e');

        // If server fails, save to local DB only
        _saveMessagesToLocalDB(id, messages, now);

        // Update local session
        await appDatabase.update(
          'sessions',
          {
            'title': title,
            'summary': summary,
            'last_modified': now.toIso8601String(),
            'is_synced': 0,
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        // Get updated session from local database
        final results = await appDatabase.query(
          'sessions',
          where: 'id = ?',
          whereArgs: [id],
        );

        if (results.isEmpty) {
          throw Exception('Session not found');
        }

        final data = results.first;
        return Session(
          id: data['id'] as String,
          title: data['title'] as String,
          summary: data['summary'] as String,
          createdAt: DateTime.parse(data['created_at'] as String),
          lastModified: DateTime.parse(data['last_modified'] as String),
          isSynced: false,
        );
      }
    } catch (e) {
      print('Error in saveSession: $e');
      rethrow;
    }
  }

  // Helper method to save messages to local DB
  Future<void> _saveMessagesToLocalDB(
      String sessionId, List<dynamic> messages, DateTime timestamp) async {
    for (final message in messages) {
      try {
        if (message is Map<String, dynamic>) {
          await appDatabase.insert('messages', {
            'id': message['id'] ??
                'msg_${timestamp.millisecondsSinceEpoch}_${messages.indexOf(message)}',
            'session_id': sessionId,
            'content': message['content'] ?? '',
            'is_user': message['isUser'] == true ? 1 : 0,
            'timestamp': message['timestamp'] ?? timestamp.toIso8601String(),
            'audio_url': message['audioUrl'],
          });
        }
      } catch (e) {
        print('Error saving message to local DB: $e');
      }
    }
  }
}
