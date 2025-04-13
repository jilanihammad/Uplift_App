import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get_it/get_it.dart';
import '../domain/entities/session.dart';
import '../data/repositories/session_repository.dart';
import '../data/datasources/local/app_database.dart';
import '../di/service_locator.dart';
import '../models/therapy_message.dart';

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
  final SessionRepository _sessionRepository = serviceLocator<SessionRepository>();
  
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
        orderBy: 'timestamp ASC',
      );
      
      return results.map((data) => TherapyMessage(
        id: data['id'] as String,
        content: data['content'] as String,
        isUser: (data['is_user'] as int) == 1,
        timestamp: DateTime.parse(data['timestamp'] as String),
        audioUrl: data['audio_url'] as String?,
      )).toList();
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
                    const Icon(Icons.error_outline, size: 60, color: Colors.red),
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
          'Conversation',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _messages.isEmpty
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No messages found for this session.'),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
      ],
    );
  }
  
  Widget _buildMessageBubble(TherapyMessage message) {
    final isUser = message.isUser;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) 
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.psychology, color: Colors.white),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser 
                        ? Theme.of(context).primaryColor 
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Color.fromRGBO(0, 0, 0, 0.1),
                      ),
                    ],
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('h:mm a').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) 
            const CircleAvatar(
              child: Icon(Icons.person),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
  
  bool _isDisposed = false;
} 