// Screen for viewing detailed session information including messages and summary from history screen

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../domain/entities/session.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import '../models/therapy_message.dart';
import '../utils/date_formatter.dart';
import '../services/tasks_service.dart';
import 'widgets/action_items_card.dart';
import 'dart:convert';

class SessionDetailsScreen extends StatefulWidget {
  final String sessionId;
  final ISessionRepository? sessionRepository;
  final IDatabase? database;

  const SessionDetailsScreen({
    Key? key,
    required this.sessionId,
    this.sessionRepository,
    this.database,
  }) : super(key: key);

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
    _sessionRepository = widget.sessionRepository ?? DependencyContainer().sessionRepository;
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
            content: Text('Added to tasks: ${actionItem.length > 50 ? '${actionItem.substring(0, 50)}...' : actionItem}'),
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
            content: Text('Removed from tasks: ${actionItem.length > 50 ? '${actionItem.substring(0, 50)}...' : actionItem}'),
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
      // Load session details
      final session = await _sessionRepository.getSession(widget.sessionId);

      // Load session messages
      final messages = await _loadSessionMessages(widget.sessionId);

      if (!mounted || _isDisposed) return;

      setState(() {
        _session = session;
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading session details: $e');

      if (!mounted || _isDisposed) return;

      setState(() {
        _errorMessage = 'Could not load session details.';
        _isLoading = false;
      });
    }
  }

  Future<List<TherapyMessage>> _loadSessionMessages(String sessionId) async {
    try {
      // This would typically be done through a MessageRepository
      // For now, we'll get them from the local database
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
                timestamp: DateTime.parse(data['timestamp'] as String).toUtc(),
                audioUrl: data['audio_url'] as String?,
                sequence: data['sequence'] as int? ?? 0, // Default to 0 if null
              ))
          .toList();
    } catch (e) {
      debugPrint('Error loading session messages: $e');
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
    // Try to extract action items from the summary
    // The action items might be embedded in the summary text as JSON
    List<String> actionItems = _extractActionItems();

    return ActionItemsCard(
      actionItems: actionItems,
      sessionId: widget.sessionId,
      onAddToTasks: _addToTasks,
      onRemoveFromTasks: _removeFromTasks,
      isItemAlreadyAdded: (actionItem) => _tasksService.isActionItemAlreadyAdded(widget.sessionId, actionItem),
    );
  }

  List<String> _extractActionItems() {
    final session = _session;
    if (session == null) {
      debugPrint('Session is null, returning empty action items');
      return [];
    }

    // First priority: Use stored action items from database
    if (session.actionItems.isNotEmpty) {
      debugPrint('Using stored action items from database: ${session.actionItems.length} items');
      debugPrint('Stored action items: ${session.actionItems.join(", ")}');
      return session.actionItems;
    }

    debugPrint('No stored action items found for session ${session.id}, falling back to summary extraction');

    // Fallback: Extract from summary text (for legacy sessions)
    if (session.summary.isEmpty) {
      return [];
    }
    
    debugPrint('No stored action items found, attempting to extract from summary text (legacy mode)');
    final summary = session.summary;
    List<String> actionItems = [];

    try {
      // First attempt: Try to parse the summary as JSON with enhanced format detection
      if (_isValidJsonFormat(summary)) {
        try {
          final summaryJson = jsonDecode(summary);
          if (summaryJson is Map && summaryJson.containsKey('action_items')) {
            final items = summaryJson['action_items'];
            if (items is List) {
              actionItems = items.map((item) => item.toString()).toList();
              debugPrint('Successfully extracted ${actionItems.length} action items from JSON summary');
            }
          }
        } on FormatException catch (e) {
          debugPrint('FormatException parsing summary as JSON: ${e.message}');
          // Continue to text-based extraction
        } catch (e) {
          debugPrint('Unexpected error parsing summary as JSON: $e');
          // Continue to text-based extraction
        }
      } else {
        debugPrint('Summary format detected as plain text, using text-based action item extraction');
      }

      // Second attempt: Look for action items in the text
      if (actionItems.isEmpty) {
        // Look for patterns like "Action items:" or "Recommended actions:"
        final actionItemRegex = RegExp(
            r'(action items:|recommended actions:|action steps:)(.+?)(?=\n\n|\n[A-Z]|$)',
            caseSensitive: false,
            dotAll: true);

        final match = actionItemRegex.firstMatch(summary);
        if (match != null && match.groupCount >= 2) {
          final actionItemsText = match.group(2)?.trim() ?? '';

          // Split by bullets or numbers
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

      // Third attempt: Use default action items if none found
      if (actionItems.isEmpty) {
        actionItems = [
          'Practice mindfulness regularly',
          'Reflect on the insights from your session',
          'Apply the coping strategies discussed',
          'Focus on your self-care routine'
        ];
      }
    } catch (e) {
      debugPrint('Error extracting action items: $e');
      // Fallback action items
      actionItems = [
        'Practice mindfulness regularly',
        'Reflect on the insights from your session',
        'Apply the coping strategies discussed',
        'Focus on your self-care routine'
      ];
    }

    return actionItems;
  }

  /// Enhanced JSON format validation to reduce false positives
  bool _isValidJsonFormat(String text) {
    final trimmed = text.trim();
    
    // Basic structure check - must start with { and end with }
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return false;
    }
    
    // Must contain at least one colon (key-value pairs)
    if (!trimmed.contains(':')) {
      return false;
    }
    
    // Should have matching braces
    int braceCount = 0;
    for (int i = 0; i < trimmed.length; i++) {
      if (trimmed[i] == '{') braceCount++;
      if (trimmed[i] == '}') braceCount--;
      if (braceCount < 0) return false; // More closing than opening braces
    }
    
    // Final brace count should be zero
    if (braceCount != 0) return false;
    
    // Quick validation for common JSON patterns
    if (trimmed.contains('"') && (trimmed.contains('":') || trimmed.contains('" :'))) {
      return true;
    }
    
    // If it looks like JSON but doesn't have quotes, it might be malformed
    // In this case, we'll let jsonDecode handle it and catch the FormatException
    return true;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
