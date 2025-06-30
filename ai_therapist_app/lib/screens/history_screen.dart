// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../di/dependency_container.dart';
import '../di/interfaces/interfaces.dart';
import '../domain/entities/session.dart';
import '../utils/date_formatter.dart';

class HistoryScreen extends StatefulWidget {
  final ISessionRepository? sessionRepository;
  
  const HistoryScreen({
    Key? key,
    this.sessionRepository,
  }) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<Session> _sessions = [];
  late ISessionRepository _sessionRepository;
  String? _errorMessage;
  bool _isDisposed = false;

  // Calendar state
  late DateTime _selectedDate;
  late List<DateTime> _weekDates;
  List<Session> _filteredSessions = [];

  @override
  void initState() {
    super.initState();
    _sessionRepository = widget.sessionRepository ?? DependencyContainer().sessionRepository;
    _selectedDate = DateTime.now();
    _generateWeekDates();
    _loadSessions();
  }

  void _generateWeekDates() {
    // Get the current date
    final now = DateTime.now();

    // Calculate days from the start of the week (considering Sunday as first day)
    final DateTime startOfWeek =
        DateTime(now.year, now.month, now.day - now.weekday % 7);

    // Generate 7 days starting from the start of the week
    _weekDates = List.generate(7, (index) {
      return startOfWeek.add(Duration(days: index));
    });
  }

  void _filterSessionsByDate() {
    // Filter sessions for the selected date
    final startOfDay =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    _filteredSessions = _sessions.where((session) {
      return session.createdAt.isAfter(startOfDay) &&
          session.createdAt.isBefore(endOfDay);
    }).toList();
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
        // Sort sessions with newest first (by createdAt date)
        _sessions = loadedSessions
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _isLoading = false;

        // Filter sessions for selected date
        _filterSessionsByDate();
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

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _filterSessionsByDate();
    });
  }

  // Calendar day widget
  Widget _buildDayWidget(DateTime date) {
    final isSelected = date.year == _selectedDate.year &&
        date.month == _selectedDate.month &&
        date.day == _selectedDate.day;

    final isToday = date.year == DateTime.now().year &&
        date.month == DateTime.now().month &&
        date.day == DateTime.now().day;

    // Get the day name and day number
    final dayName =
        DateFormat('EEE').format(date).substring(0, 3); // Sun, Mon, Tue, etc.
    final dayNumber = date.day.toString();

    // Check if the day has any sessions
    final hasSessionsOnDay = _sessions.any((session) {
      return session.createdAt.year == date.year &&
          session.createdAt.month == date.month &&
          session.createdAt.day == date.day;
    });

    return GestureDetector(
      onTap: () => _selectDate(date),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dayName,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Colors.black
                    : isToday
                        ? Colors.black
                        : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? Colors.black
                    : hasSessionsOnDay
                        ? Colors.grey.shade200
                        : Colors.transparent,
                border: isToday && !isSelected
                    ? Border.all(color: Colors.black, width: 1)
                    : null,
              ),
              child: Center(
                child: Text(
                  dayNumber,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isSelected
                        ? Colors.white
                        : isToday
                            ? Colors.black
                            : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Calendar widget
  Widget _buildCalendar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text(
              DateFormat('MMMM yyyy').format(_selectedDate),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _weekDates.map((date) => _buildDayWidget(date)).toList(),
          ),
        ],
      ),
    );
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
          // Calendar widget
          _buildCalendar(),

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

          // Sessions heading
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sessions on ${DateFormat('MMM d').format(_selectedDate)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_filteredSessions.length} sessions',
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.history,
                                size: 80, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              'No Sessions on ${DateFormat('MMM d').format(_selectedDate)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                                'Select another date or start a new session'),
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
                        itemCount: _filteredSessions.length,
                        itemBuilder: (context, index) {
                          final session = _filteredSessions[index];
                          return SessionHistoryTile(
                            session: session,
                            onRename: (newTitle) async {
                              await _renameSession(session, newTitle);
                            },
                            onDelete: () async {
                              await _deleteSession(session);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameSession(Session session, String newTitle) async {
    try {
      await _sessionRepository.updateSession(session.id, title: newTitle);
      await _loadSessions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to rename session: $e')),
      );
    }
  }

  Future<void> _deleteSession(Session session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text(
            'Are you sure you want to delete this session? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _sessionRepository.deleteSession(session.id);
        await _loadSessions();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete session: $e')),
        );
      }
    }
  }
}

class SessionHistoryTile extends StatelessWidget {
  final Session session;
  final Future<void> Function(String newTitle)? onRename;
  final Future<void> Function()? onDelete;

  const SessionHistoryTile({
    Key? key,
    required this.session,
    this.onRename,
    this.onDelete,
  }) : super(key: key);

  String _formatDate(DateTime date) {
    return DateFormatter.formatTime(date);
  }

  void _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: session.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Session Title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != session.title) {
      await onRename?.call(result);
    }
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
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'rename') {
              _showRenameDialog(context);
            } else if (value == 'delete') {
              if (onDelete != null) await onDelete!();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'rename',
              child: Text('Rename'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
        onTap: () {
          // Navigate to session details using GoRouter
          context.push('/sessions/${session.id}');
        },
      ),
    );
  }
}
