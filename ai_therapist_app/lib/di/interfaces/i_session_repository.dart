// lib/di/interfaces/i_session_repository.dart
import '../../domain/entities/session.dart';
abstract class ISessionRepository {
  Future<Session> createSession(String title, {String? id});
  Future<List<Session>> getSessions();
  Future<Session> getSession(String sessionId);
  Future<Session> updateSession(
    String sessionId, {
    String? title,
    bool sync = true,
  });
  Future<void> deleteSession(String sessionId);
  Future<Session> saveSession({
    required String sessionId,
    required String title,
    required String summary,
    List<String> actionItems = const [],
    required List<Map<String, dynamic>> messages,
    bool sync = true,
  });
}
