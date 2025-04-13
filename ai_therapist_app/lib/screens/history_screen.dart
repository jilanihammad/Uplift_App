// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../services/therapy_service.dart';
import '../di/service_locator.dart';
import '../data/repositories/session_repository.dart';
import '../domain/entities/session.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<Session> _sessions = [];
  final SessionRepository _sessionRepository = serviceLocator<SessionRepository>();
  String? _errorMessage;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    // Cancel any pending operations
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadSessions() async {
    if (_isDisposed) return; // Don't load if already disposed
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // Load real sessions from repository
      final loadedSessions = await _sessionRepository.getSessions();
      
      if (!mounted || _isDisposed) return; // Check mounted state
      
      setState(() {
        _sessions = loadedSessions;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading sessions: $e');
      
      if (!mounted || _isDisposed) return; // Check mounted state
      
      setState(() {
        _errorMessage = 'Failed to load sessions: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
            tooltip: 'Refresh sessions',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              color: Colors.amber.shade100,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.amber.shade900),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.history, size: 80, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No Session History',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Your therapy sessions will appear here'),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                context.go('/chat');
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Start a new session'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          return SessionHistoryTile(session: session);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class SessionHistoryTile extends StatelessWidget {
  final Session session;

  const SessionHistoryTile({
    Key? key,
    required this.session,
  }) : super(key: key);

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy - h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          session.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_formatDate(session.createdAt)),
            const SizedBox(height: 8),
            Text(session.summary),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.arrow_forward_ios),
          onPressed: () {
            // Navigate to session details using GoRouter
            context.push('/sessions/${session.id}');
          },
        ),
        onTap: () {
          // Navigate to session details using GoRouter
          context.push('/sessions/${session.id}');
        },
      ),
    );
  }
}