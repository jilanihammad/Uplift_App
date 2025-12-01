// lib/data/repositories/session_repository.dart
import 'dart:convert';
import '../../domain/entities/session.dart';
import '../../di/interfaces/i_session_repository.dart';
import '../../di/interfaces/i_api_client.dart';
import '../../di/interfaces/i_app_database.dart';
import 'package:flutter/foundation.dart';
import '../../services/user_context_service.dart';
import 'package:ai_therapist_app/utils/date_time_utils.dart';

class SessionRepository implements ISessionRepository {
  final IApiClient apiClient;
  final IAppDatabase appDatabase;
  final UserContextService userContextService;

  SessionRepository({
    required this.apiClient,
    required this.appDatabase,
    required this.userContextService,
  });

  String _requireUserId(String operation) {
    final userId = userContextService.getSignedInUserId(operation: operation);
    if (userId == null || userId.isEmpty) {
      throw const AuthRequiredException(
        'User is not signed in – session operation requires authentication',
      );
    }
    return userId;
  }

  String? _resolveUserId(String operation) {
    final userId = userContextService.getSignedInUserId(operation: operation);
    if (userId == null || userId.isEmpty) {
      return null;
    }
    return userId;
  }

  // Create a new session
  @override
  Future<Session> createSession(String title, {String? id}) async {
    final userId = _requireUserId('SessionRepository.createSession');

    // Check if session with this ID already exists locally
    if (id != null) {
      try {
        final results = await appDatabase.query(
          'sessions',
          where: 'id = ? AND user_id = ?',
          whereArgs: [id, userId],
        );

        if (results.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
                'Session with ID $id already exists, returning existing session');
          }

          final data = results.first;
          return Session(
            id: data['id'] as String,
            title: data['title'] as String,
            summary: data['summary'] as String,
            actionItems: _parseActionItems(data['action_items']),
            createdAt: parseBackendDateTimeToUtc(data['created_at'] as String),
            lastModified:
                parseBackendDateTimeToUtc(data['last_modified'] as String),
            isSynced: (data['is_synced'] as int) == 1,
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error checking for existing session: $e');
        }
        // Continue to create session
      }
    }

    // Try to create session on the server
    try {
      final response = await apiClient.post(
        '/sessions',
        {
          'title': title,
          'id': id, // Include the ID if provided
        },
      );

      final session = Session.fromJson(response);

      // Save to local database
      await appDatabase.insert('sessions', {
        'id': id ??
            session.id, // Use the provided ID or the one from the response
        'user_id': userId,
        'title': session.title,
        'summary': session.summary,
        'action_items': jsonEncode(session.actionItems),
        'created_at': session.createdAt.toUtc().toIso8601String(),
        'last_modified': session.lastModified.toUtc().toIso8601String(),
        'is_synced': 1,
      });

      return session;
    } catch (e) {
      debugPrint('Error creating session on server: $e');

      // Create local session if API call fails
      final String localId =
          id ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().toUtc().toIso8601String();

      await appDatabase.insert('sessions', {
        'id': localId,
        'user_id': userId,
        'title': title,
        'summary': '',
        'action_items': jsonEncode([]),
        'created_at': now,
        'last_modified': now,
        'is_synced': 0,
      });

      return Session(
        id: localId,
        title: title,
        summary: '',
        actionItems: [],
        createdAt: DateTime.now().toUtc(),
        lastModified: DateTime.now().toUtc(),
        isSynced: false,
      );
    }
  }

  // Get all sessions
  @override
  Future<List<Session>> getSessions() async {
    final userId = _resolveUserId('SessionRepository.getSessions');
    if (userId == null) {
      return const <Session>[];
    }
    try {
      // Try to get sessions from the server
      debugPrint('Fetching sessions from server');
      final response = await apiClient.get('/sessions');
      debugPrint('Server response for sessions: $response');

      final List<dynamic> sessionsJson =
          response['data'] ?? response['sessions'] ?? response;

      final sessions =
          sessionsJson.map((json) => Session.fromJson(json)).toList();

      // Update local database
      await appDatabase.transaction((txn) async {
        for (final session in sessions) {
          try {
            await txn.insert('sessions', {
              'id': session.id,
              'user_id': userId,
              'title': session.title,
              'summary': session.summary,
              'action_items': jsonEncode(session.actionItems),
              'created_at': session.createdAt.toUtc().toIso8601String(),
              'last_modified': session.lastModified.toUtc().toIso8601String(),
              'is_synced': 1,
            });
          } catch (e) {
            // If the session already exists, update it
            await txn.update(
              'sessions',
              {
                'title': session.title,
                'summary': session.summary,
                'action_items': jsonEncode(session.actionItems),
                'last_modified': session.lastModified.toUtc().toIso8601String(),
                'is_synced': 1,
              },
              where: 'id = ? AND user_id = ?',
              whereArgs: [session.id, userId],
            );
          }
        }
      });

      return sessions;
    } catch (e) {
      debugPrint('Error fetching sessions from server: $e');

      // Get sessions from local database if API call fails
      final results = await appDatabase.query(
        'sessions',
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      return results
          .map((data) => Session(
                id: data['id'] as String,
                title: data['title'] as String,
                summary: data['summary'] as String,
                actionItems: _parseActionItems(data['action_items']),
                createdAt:
                    parseBackendDateTimeToUtc(data['created_at'] as String),
                lastModified:
                    parseBackendDateTimeToUtc(data['last_modified'] as String),
                isSynced: (data['is_synced'] as int) == 1,
              ))
          .toList();
    }
  }

  // Get a specific session
  @override
  Future<Session> getSession(String sessionId) async {
    final userId = _requireUserId('SessionRepository.getSession');
    try {
      // Try to get session from the server first
      debugPrint('Fetching session $sessionId from server');
      final response = await apiClient.get('/sessions/$sessionId');
      debugPrint('Server response for session $sessionId: $response');

      final session = Session.fromJson(response);

      // Update local database with server data
      try {
        await appDatabase.insert('sessions', {
          'id': session.id,
          'user_id': userId,
          'title': session.title,
          'summary': session.summary,
          'action_items': jsonEncode(session.actionItems),
          'created_at': session.createdAt.toUtc().toIso8601String(),
          'last_modified': session.lastModified.toUtc().toIso8601String(),
          'is_synced': 1,
        });
      } catch (e) {
        // If the session already exists, update it
        await appDatabase.update(
          'sessions',
          {
            'title': session.title,
            'summary': session.summary,
            'action_items': jsonEncode(session.actionItems),
            'last_modified': session.lastModified.toUtc().toIso8601String(),
            'is_synced': 1,
          },
          where: 'id = ? AND user_id = ?',
          whereArgs: [session.id, userId],
        );
      }

      return session;
    } catch (e) {
      debugPrint('Error fetching session $sessionId from server: $e');

      // Get session from local database if API call fails
      final results = await appDatabase.query(
        'sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );

      if (results.isEmpty) {
        throw Exception('Session not found');
      }

      final data = results.first;
      return Session(
        id: data['id'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        actionItems: _parseActionItems(data['action_items']),
        createdAt: parseBackendDateTimeToUtc(data['created_at'] as String),
        lastModified: parseBackendDateTimeToUtc(data['last_modified'] as String),
        isSynced: (data['is_synced'] as int) == 1,
      );
    }
  }

  // Update a session
  @override
  Future<Session> updateSession(
    String sessionId, {
    String? title,
    bool sync = true,
  }) async {
    final userId = _requireUserId('SessionRepository.updateSession');
    final now = DateTime.now();

    try {
      // Try to update on the server
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;

      debugPrint('Updating session $sessionId on server with: $body');
      final response = await apiClient.put(
        '/sessions/$sessionId',
        body,
      );
      debugPrint('Server response for updating session $sessionId: $response');

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
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );

      return session;
    } catch (e) {
      debugPrint('Error updating session $sessionId on server: $e');

      // Update locally if API call fails
      final updateData = <String, dynamic>{
        'last_modified': now.toIso8601String(),
        'is_synced': 0,
      };

      if (title != null) updateData['title'] = title;

      await appDatabase.update(
        'sessions',
        updateData,
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );

      // Get updated session from local database
      final results = await appDatabase.query(
        'sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );

      final data = results.first;
      return Session(
        id: data['id'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        actionItems: _parseActionItems(data['action_items']),
        createdAt: parseBackendDateTimeToUtc(data['created_at'] as String),
        lastModified: parseBackendDateTimeToUtc(data['last_modified'] as String),
        isSynced: false,
      );
    }
  }

  // Delete a session
  @override
  Future<void> deleteSession(String sessionId) async {
    final userId = _resolveUserId('SessionRepository.deleteSession');
    if (userId == null) {
      return;
    }
    try {
      // Try to delete on server
      debugPrint('Deleting session $sessionId from server');
      await apiClient.delete('/sessions/$sessionId');
      debugPrint('Successfully deleted session $sessionId from server');
    } catch (e) {
      debugPrint('Error deleting session $sessionId from server: $e');
      // Ignore API errors
    } finally {
      // Always delete from local database
      await appDatabase.delete(
        'sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );
    }
  }

  // Save a completed therapy session
  @override
  Future<Session> saveSession({
    required String sessionId,
    required String title,
    required String summary,
    List<String> actionItems = const [],
    required List<Map<String, dynamic>> messages,
    bool sync = true,
  }) async {
    final userId = _requireUserId('SessionRepository.saveSession');
    final now = DateTime.now();

    debugPrint(
        'Saving session $sessionId with title length: ${title.length}, summary length: ${summary.length}');
    debugPrint(
        'Persisting ${actionItems.length} action items for session $sessionId');

    try {
      // Save to local DB (transactional)
      await appDatabase.transaction((txn) async {
        // Try to update local session
        int updated = await txn.update(
          'sessions',
          {
            'title': title,
            'summary': summary,
            'action_items': jsonEncode(actionItems),
            'last_modified': now.toIso8601String(),
            'is_synced': sync ? 0 : 0, // Mark as not synced for now
          },
          where: 'id = ? AND user_id = ?',
          whereArgs: [sessionId, userId],
        );

        debugPrint(
            'Updated $updated existing sessions with action items for session $sessionId');

        // If no rows were updated, insert the session row
        if (updated == 0) {
          await txn.insert('sessions', {
            'id': sessionId,
            'user_id': userId,
            'title': title,
            'summary': summary,
            'action_items': jsonEncode(actionItems),
            'created_at': now.toIso8601String(),
            'last_modified': now.toIso8601String(),
            'is_synced': 0,
          });
          debugPrint(
              'Inserted new session $sessionId with ${actionItems.length} action items');
        }

        // Save messages to local DB within the same transaction
        await _saveMessagesToLocalDBTxn(txn, sessionId, userId, messages, now);
      });

      // Get updated session from local database
      final results = await appDatabase.query(
        'sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );

      if (results.isEmpty) {
        throw Exception('Session not found');
      }

      final data = results.first;
      final sessionActionItems = _parseActionItems(data['action_items']);
      debugPrint(
          'Returning saved session $sessionId with ${sessionActionItems.length} action items from local database');
      return Session(
        id: data['id'] as String,
        title: data['title'] as String,
        summary: data['summary'] as String,
        actionItems: sessionActionItems,
        createdAt: parseBackendDateTimeToUtc(data['created_at'] as String),
        lastModified: parseBackendDateTimeToUtc(data['last_modified'] as String),
        isSynced: (data['is_synced'] as int) == 1,
      );
    } catch (e) {
      debugPrint('Error in saveSession: $e');
      rethrow;
    }
  }

  // Helper method to parse action items from database
  List<String> _parseActionItems(dynamic actionItemsData) {
    if (actionItemsData == null) return [];

    try {
      if (actionItemsData is String) {
        if (actionItemsData.isEmpty) return [];
        // Try to parse as JSON array
        final decoded = jsonDecode(actionItemsData);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
        // If not a JSON array, treat as single item
        return [actionItemsData];
      } else if (actionItemsData is List) {
        return actionItemsData.map((item) => item.toString()).toList();
      }
    } catch (e) {
      // If parsing fails, return empty list
      if (kDebugMode) {
        debugPrint('Error parsing action items: $e');
      }
    }

    return [];
  }

  // Helper method to save messages to local DB using a transaction
  Future<void> _saveMessagesToLocalDBTxn(dynamic txn, String sessionId,
      String userId, List<dynamic> messages, DateTime timestamp) async {
    for (final message in messages) {
      try {
        if (message is Map<String, dynamic>) {
          await txn.insert('messages', {
            'id': message['id'] ??
                'msg_${timestamp.millisecondsSinceEpoch}_${messages.indexOf(message)}',
            'session_id': sessionId,
            'user_id': userId,
            'content': message['content'] ?? '',
            'is_user': message['isUser'] == true ? 1 : 0,
            'timestamp': message['timestamp'] ?? timestamp.toIso8601String(),
            'audio_url': message['audioUrl'],
          });
        }
      } catch (e) {
        debugPrint('Error saving message to local DB in transaction: $e');
        rethrow; // Fail the transaction if any message insert fails
      }
    }
  }
}
