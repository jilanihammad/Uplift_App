// lib/di/interfaces/i_session_repository.dart

import '../../domain/entities/session.dart';

/// Interface for session repository operations
/// Provides CRUD operations for therapy sessions
abstract class ISessionRepository {
  /// Create a new session with optional ID
  Future<Session> createSession(String title, {String? id});
  
  /// Get all sessions from local and remote sources
  Future<List<Session>> getSessions();
  
  /// Get a specific session by ID
  Future<Session> getSession(String sessionId);
  
  /// Update session title and optionally sync to remote
  Future<Session> updateSession(
    String sessionId, {
    String? title,
    bool sync = true,
  });
  
  /// Delete a session by ID
  Future<void> deleteSession(String sessionId);
  
  /// Save session with messages and metadata
  Future<Session> saveSession({
    required String sessionId,
    required String title,
    required String summary,
    List<String> actionItems = const [],
    required List<Map<String, dynamic>> messages,
    bool sync = true,
  });
}