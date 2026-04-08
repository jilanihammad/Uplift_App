// Screen for viewing detailed session information including messages and summary from history screen
import 'package:flutter/material.dart';
import '../domain/entities/session.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import '../models/therapy_message.dart';
import '../utils/date_formatter.dart';
import '../utils/date_time_utils.dart';
import '../services/tasks_service.dart';
import 'widgets/action_items_card.dart';
import 'dart:convert';
class SessionDetailsScreen extends StatefulWidget {
  final String sessionId;
  final ISessionRepository? sessionRepository;
  final IDatabase? database;
  const SessionDetailsScreen({
    super.key,
    required this.sessionId,
    this.sessionRepository,
    this.database,
  });
  @override
  State<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}
class _SessionDetailsScreenState extends State<SessionDetailsScreen> {
  bool _isLoading = true;
  bool _isDisposed = false;
  Session? _session;
  List<TherapyMessage> _messages = [];
  String? _errorMessage;
  late ISessionRepository _sessionRepository;
  late IDatabase _database;
  late TasksService _tasksService;
  @override
  void initState() {
    super.initState();
    _sessionRepository =
        widget.sessionRepository ?? DependencyContainer().sessionRepository;
    _database = widget.database ?? DependencyContainer().database;
    _tasksService = TasksService();
    _tasksService.init();
    _loadSession();
  }
  void _addToTasks(String actionItem) async {
    try {
      await _tasksService.addTask(actionItem, widget.sessionId);
      if (mounted) {
        setState(() {}); // Refresh UI to update button state
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Added to tasks: ${actionItem.length > 50 ? '${actionItem.substring(0, 50)}...' : actionItem}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add task'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  void _removeFromTasks(String actionItem) async {
    try {
      await _tasksService.removeTaskByActionItem(widget.sessionId, actionItem);
      if (mounted) {
        setState(() {}); // Refresh UI to update button state
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Removed from tasks: ${actionItem.length > 50 ? '${actionItem.substring(0, 50)}...' : actionItem}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove task'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<void> _loadSession() async {
    if (_isDisposed) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final session = await _sessionRepository.getSession(widget.sessionId);
      final messages = await _loadSessionMessages(widget.sessionId);
      if (!mounted || _isDisposed) return;
      setState(() {
        _session = session;
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _errorMessage = 'Could not load session details.';
        _isLoading = false;
      });
    }
  }
  Future<List<TherapyMessage>> _loadSessionMessages(String sessionId) async {
    try {
      final results = await _database.query(
        'messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy:
            'timestamp ASC', // Consider ordering by sequence ASC as well/instead
      );
      return results
          .map((data) => TherapyMessage(
                id: data['id'] as String,
                content: data['content'] as String,
                isUser: (data['is_user'] as int) == 1,
                timestamp:
                    parseBackendDateTimeToUtc(data['timestamp'] as String),
                audioUrl: data['audio_url'] as String?,
                sequence: data['sequence'] as int? ?? 0, // Default to 0 if null
              ))
          .toList();
    } catch (e) {
      return [];
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 60, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadSession,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : _session == null
                  ? const Center(child: Text('Session not found.'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSessionHeader(),
                          const Divider(height: 32),
                          _buildSummarySection(),
                          const SizedBox(height: 24),
                          _buildConversationSection(),
                        ],
                      ),
                    ),
    );
  }
  Widget _buildSessionHeader() {
    final session = _session;
    if (session == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text(
                  DateFormatter.formatDate(session.createdAt),
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 8),
                Text(
                  DateFormatter.formatTime(session.createdAt),
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildSummarySection() {
    final session = _session;
    if (session == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Session Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(session.summary),
          ),
        ),
      ],
    );
  }
  Widget _buildConversationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recommended Action Items',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildActionItems(),
      ],
    );
  }
  Widget _buildActionItems() {
    List<String> actionItems = _extractActionItems();
    return ActionItemsCard(
      actionItems: actionItems,
      sessionId: widget.sessionId,
      onAddToTasks: _addToTasks,
      onRemoveFromTasks: _removeFromTasks,
      isItemAlreadyAdded: (actionItem) =>
          _tasksService.isActionItemAlreadyAdded(widget.sessionId, actionItem),
    );
  }
  List<String> _extractActionItems() {
    final session = _session;
    if (session == null) {
      return [];
    }
    if (session.actionItems.isNotEmpty) {
      return session.actionItems;
    }
    if (session.summary.isEmpty) {
      return [];
    }
    final summary = session.summary;
    List<String> actionItems = [];
    try {
      if (_isValidJsonFormat(summary)) {
        try {
          final summaryJson = jsonDecode(summary);
          if (summaryJson is Map && summaryJson.containsKey('action_items')) {
            final items = summaryJson['action_items'];
            if (items is List) {
              actionItems = items.map((item) => item.toString()).toList();
            }
          }
        } on FormatException catch (e) {
        } catch (e) {}
      } else {
      }
      if (actionItems.isEmpty) {
        final actionItemRegex = RegExp(
            r'(action items:|recommended actions:|action steps:)(.+?)(?=\n\n|\n[A-Z]|$)',
            caseSensitive: false,
            dotAll: true);
        final match = actionItemRegex.firstMatch(summary);
        if (match != null && match.groupCount >= 2) {
          final actionItemsText = match.group(2)?.trim() ?? '';
          final bulletItems = actionItemsText.split(RegExp(r'\n\s*[-•*]\s*'));
          final numberItems = actionItemsText.split(RegExp(r'\n\s*\d+\.\s*'));
          if (bulletItems.length > 1) {
            actionItems = bulletItems
                .skip(1)
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList();
          } else if (numberItems.length > 1) {
            actionItems = numberItems
                .skip(1)
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList();
          }
        }
      }
      if (actionItems.isEmpty) {
        actionItems = [
          'Practice mindfulness regularly',
          'Reflect on the insights from your session',
          'Apply the coping strategies discussed',
          'Focus on your self-care routine'
        ];
      }
    } catch (e) {
      actionItems = [
        'Practice mindfulness regularly',
        'Reflect on the insights from your session',
        'Apply the coping strategies discussed',
        'Focus on your self-care routine'
      ];
    }
    return actionItems;
  }
  bool _isValidJsonFormat(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return false;
    }
    if (!trimmed.contains(':')) {
      return false;
    }
    int braceCount = 0;
    for (int i = 0; i < trimmed.length; i++) {
      if (trimmed[i] == '{') braceCount++;
      if (trimmed[i] == '}') braceCount--;
      if (braceCount < 0) return false; // More closing than opening braces
    }
    if (braceCount != 0) return false;
    if (trimmed.contains('"') &&
        (trimmed.contains('":') || trimmed.contains('" :'))) {
      return true;
    }
    return true;
  }
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
