import 'package:intl/intl.dart';
import '../di/interfaces/i_therapy_service.dart';
import '../di/interfaces/i_progress_service.dart';
import '../di/interfaces/i_session_repository.dart';
import '../di/interfaces/i_api_client.dart';
import '../models/therapy_message.dart';
import '../utils/feature_flags.dart';
import '../widgets/mood_selector.dart';
import 'user_context_service.dart';
import '../utils/app_logger.dart';

class SessionFinalizationResult {
  final String sessionId;
  final String summary;
  final List<String> actionItems;
  final List<String> insights;

  SessionFinalizationResult({
    required this.sessionId,
    required this.summary,
    required this.actionItems,
    required this.insights,
  });
}

class SessionFinalizationService {
  final ITherapyService _therapyService;
  final IProgressService _progressService;
  final ISessionRepository _sessionRepository;
  final UserContextService _userContextService;
  final IApiClient _apiClient;

  SessionFinalizationService({
    required ITherapyService therapyService,
    required IProgressService progressService,
    required ISessionRepository sessionRepository,
    required UserContextService userContextService,
    required IApiClient apiClient,
  })  : _therapyService = therapyService,
        _progressService = progressService,
        _sessionRepository = sessionRepository,
        _userContextService = userContextService,
        _apiClient = apiClient;

  Future<SessionFinalizationResult> finalize({
    required String currentSessionId,
    required List<TherapyMessage> messages,
    Mood? initialMood,
  }) async {
    final sessionData = await _generateSessionSummary(messages, initialMood);
    final sessionId = await _saveSession(
      currentSessionId: currentSessionId,
      sessionData: sessionData,
      messages: messages,
    );
    return SessionFinalizationResult(
      sessionId: sessionId,
      summary: sessionData['summary'] as String,
      actionItems: sessionData['action_items'] as List<String>,
      insights: sessionData['insights'] as List<String>,
    );
  }

  Future<Map<String, dynamic>> _generateSessionSummary(
      List<TherapyMessage> messages, Mood? initialMood) async {
    if (initialMood != null) {
      await _progressService.logMood(initialMood);
    }
    final messageList = messages.map((m) => m.toJson()).toList();
    final sessionTitle =
        'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';
    final sessionData = await _therapyService.endSessionWithMessages(
      messageList,
      sessionTitle: sessionTitle,
      userId: 1,
    );
    final actionItemsDynamic = sessionData['action_items'] as List<dynamic>? ??
        sessionData['actionItems'] as List<dynamic>? ??
        ['Take care of yourself', 'Return soon for another session'];
    final insightsDynamic = sessionData['insights'] as List<dynamic>? ?? [];
    return {
      'id': sessionData['id'],
      'summary': sessionData['summary'] as String? ??
          'Thank you for your session today. I hope our conversation was helpful.',
      'action_items':
          actionItemsDynamic.map((item) => item.toString()).toList(),
      'insights': insightsDynamic.map((item) => item.toString()).toList(),
    };
  }

  Future<String> _saveSession({
    required String currentSessionId,
    required Map<String, dynamic> sessionData,
    required List<TherapyMessage> messages,
  }) async {
    final userId = _userContextService.getSignedInUserId(
        operation: 'SessionFinalizationService._saveSession');
    if (userId == null) {
      throw Exception('Cannot save session: User not authenticated');
    }
    final backendSessionId = sessionData['id']?.toString();
    final sessionIdToUse = backendSessionId ?? currentSessionId;
    final sessionTitle =
        'Therapy Session ${DateFormat('MMM d, yyyy').format(DateTime.now())}';
    final actionItemsDynamic =
        sessionData['action_items'] as List<dynamic>? ?? [];
    final actionItems =
        actionItemsDynamic.map((item) => item.toString()).toList();
    final insights = (sessionData['insights'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();

    if (backendSessionId != null) {
      await _sessionRepository.saveSession(
        sessionId: sessionIdToUse,
        title: sessionTitle,
        summary: sessionData['summary'],
        actionItems: actionItems,
        messages: messages.map((m) => m.toJson()).toList(),
      );
    } else {
      try {
        final createdSession = await _sessionRepository.createSession(
          sessionTitle,
          id: currentSessionId,
        );
        if (createdSession.id != currentSessionId) {
          // Use the ID from the backend if different
        }
      } catch (e) {
        AppLogger.w('Failed to create session on backend', e);
      }
      await _sessionRepository.saveSession(
        sessionId: currentSessionId,
        title: sessionTitle,
        summary: sessionData['summary'],
        actionItems: actionItems,
        messages: messages.map((m) => m.toJson()).toList(),
      );
    }

    if (FeatureFlags.isMemoryPersistenceEnabled) {
      await _syncSessionSummaryRemote(
          sessionIdToUse, sessionData, actionItems, insights);
    }
    return sessionIdToUse;
  }

  Future<void> _syncSessionSummaryRemote(
    String sessionId,
    Map<String, dynamic> sessionData,
    List<String> actionItems,
    List<String> insights,
  ) async {
    try {
      final summaryPayload = {
        'session_id': sessionId,
        'summary_json': {
          'summary': sessionData['summary'],
          'action_items': actionItems,
          'insights': insights,
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _apiClient.post('/session_summaries:upsert', summaryPayload);
    } catch (e) {
      AppLogger.w('Failed to sync session summary remotely', e);
    }
  }
}
