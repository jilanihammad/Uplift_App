// Screen for viewing detailed session information including messages and summary from history screen

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get_it/get_it.dart';
import '../domain/entities/session.dart';
import '../data/repositories/session_repository.dart';
import '../data/datasources/local/app_database.dart';
import '../di/service_locator.dart';
import '../models/therapy_message.dart';
import 'dart:convert';

class SessionDetailsScreen extends StatefulWidget {
  final String sessionId;

  const SessionDetailsScreen({
    Key? key,
    required this.sessionId,
  }) : super(key: key);

  @override
  State<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends State<SessionDetailsScreen> {
  bool _isLoading = true;
  Session? _session;
  List<TherapyMessage> _messages = [];
  String? _errorMessage;
  final SessionRepository _sessionRepository =
      serviceLocator<SessionRepository>();

  @override
  void initState() {
    super.initState();
    _loadSession();
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
      print('Error loading session details: $e');

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
      final appDatabase = serviceLocator<AppDatabase>();
      final results = await appDatabase.query(
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
                timestamp: DateTime.parse(data['timestamp'] as String),
                audioUrl: data['audio_url'] as String?,
                sequence: data['sequence'] as int? ?? 0, // Default to 0 if null
              ))
          .toList();
    } catch (e) {
      print('Error loading session messages: $e');
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _session!.title,
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
                  DateFormat('MMMM d, yyyy').format(_session!.createdAt),
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
                  DateFormat('h:mm a').format(_session!.createdAt),
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
            child: Text(_session!.summary),
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

    if (actionItems.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No action items found for this session.'),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: actionItems
              .map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  List<String> _extractActionItems() {
    if (_session == null || _session!.summary.isEmpty) {
      return [];
    }

    final summary = _session!.summary;
    List<String> actionItems = [];

    try {
      // First attempt: Try to parse the summary as JSON
      try {
        final summaryJson = jsonDecode(summary);
        if (summaryJson is Map && summaryJson.containsKey('action_items')) {
          final items = summaryJson['action_items'];
          if (items is List) {
            actionItems = items.map((item) => item.toString()).toList();
          }
        }
      } catch (e) {
        print('Summary is not in JSON format: $e');
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
      print('Error extracting action items: $e');
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

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  bool _isDisposed = false;
}
