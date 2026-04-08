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
  @override
  Future<Session> createSession(String title, {String? id}) async {
    final userId = _requireUserId('SessionRepository.createSession');
    if (id != null) {
      try {
        final results = await appDatabase.query(
          'sessions',
          where: 'id = ? AND user_id = ?',
          whereArgs: [id, userId],
        );
        if (results.isNotEmpty) {
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
      } catch (e) {}
    }
    try {
      final response = await apiClient.post(
        '/sessions',
        {
          'title': title,
          'id': id, // Include the ID if provided
        },
      );
      final session = Session.fromJson(response);
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
  @override
  Future<List<Session>> getSessions() async {
    final userId = _resolveUserId('SessionRepository.getSessions');
    if (userId == null) {
      return const <Session>[];
    }
    try {
      final response = await apiClient.get('/sessions');
      final List<dynamic> sessionsJson =
          response['data'] ?? response['sessions'] ?? response;
      final sessions =
          sessionsJson.map((json) => Session.fromJson(json)).toList();
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
      // CRITICAL FIX: Merge with local-only sessions (not yet on server)
      final localResults = await appDatabase.query(
        'sessions',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final allSessions = localResults
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
      return allSessions;
    } catch (e) {
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
  @override
  Future<Session> getSession(String sessionId) async {
    final userId = _requireUserId('SessionRepository.getSession');
    try {
      final response = await apiClient.get('/sessions/$sessionId');
      final session = Session.fromJson(response);
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
  @override
  Future<Session> updateSession(
    String sessionId, {
    String? title,
    bool sync = true,
  }) async {
    final userId = _requireUserId('SessionRepository.updateSession');
    final now = DateTime.now();
    try {
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      final response = await apiClient.put(
        '/sessions/$sessionId',
        body,
      );
      final session = Session.fromJson(response);
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
  @override
  Future<void> deleteSession(String sessionId) async {
    final userId = _resolveUserId('SessionRepository.deleteSession');
    if (userId == null) {
      return;
    }
    try {
      await apiClient.delete('/sessions/$sessionId');
    } catch (e) {
    } finally {
      await appDatabase.delete(
        'sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );
    }
  }
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
    try {
      await appDatabase.transaction((txn) async {
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
        }
        await _saveMessagesToLocalDBTxn(txn, sessionId, userId, messages, now);
      });
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
      rethrow;
    }
  }
  List<String> _parseActionItems(dynamic actionItemsData) {
    if (actionItemsData == null) return [];
    try {
      if (actionItemsData is String) {
        if (actionItemsData.isEmpty) return [];
        final decoded = jsonDecode(actionItemsData);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
        return [actionItemsData];
      } else if (actionItemsData is List) {
        return actionItemsData.map((item) => item.toString()).toList();
      }
    } catch (e) {}
    return [];
  }
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
        rethrow; // Fail the transaction if any message insert fails
      }
    }
  }
}
