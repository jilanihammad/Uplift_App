// Screen for displaying the summary of a therapy session immediately after it ends

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/therapy_message.dart';
import '../widgets/mood_selector.dart';
import '../services/tasks_service.dart';
import '../di/dependency_container.dart';
import 'widgets/session_summary_card.dart';
import 'widgets/action_items_card.dart';

class SessionSummaryScreen extends StatefulWidget {
  final String sessionId;
  final String summary;
  final List<String> actionItems;
  final List<TherapyMessage> messages;
  final Mood? initialMood;

  const SessionSummaryScreen({
    Key? key,
    required this.sessionId,
    required this.summary,
    required this.actionItems,
    required this.messages,
    this.initialMood,
  }) : super(key: key);

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  late TasksService _tasksService;
  
  @override
  void initState() {
    super.initState();
    _tasksService = TasksService();
    _tasksService.init();
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sessionDuration = widget.messages.isNotEmpty
        ? now.difference(widget.messages.first.timestamp)
        : Duration.zero;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Session Complete'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success indicator
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 48,
                ),
              ),
            ),

            const SizedBox(height: 16),

            Center(
              child: Column(
                children: [
                  Text(
                    'Great Session!',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Duration: ${_formatDuration(sessionDuration)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Session summary
            SessionSummaryCard(summary: widget.summary),

            const SizedBox(height: 32),

            // Action items
            ActionItemsCard(
              actionItems: widget.actionItems,
              sessionId: widget.sessionId,
              onAddToTasks: _addToTasks,
              onRemoveFromTasks: _removeFromTasks,
              isItemAlreadyAdded: (actionItem) => _tasksService.isActionItemAlreadyAdded(widget.sessionId, actionItem),
            ),

            const SizedBox(height: 40),

            // Action buttons
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Schedule Next Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () {
                      _showScheduleDialog(context);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.home),
                    label: const Text('Back to Home'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      side: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      context.go('/home');
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Additional insights or feedback section (if needed)
            if (widget.actionItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue[600],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Remember, small steps lead to big changes. Take your time with these action items.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.blue[700],
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // Keep this method in case it's used elsewhere
  Widget _buildFeedbackButton(String emoji, String label) {
    return Column(
      children: [
        TextButton(
          onPressed: () {
            // Record feedback
          },
          style: TextButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
          ),
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 24),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    int minutes = duration.inMinutes;
    if (minutes < 1) {
      return 'Less than a minute';
    } else if (minutes == 1) {
      return '1 minute';
    } else if (minutes < 60) {
      return '$minutes minutes';
    } else {
      int hours = duration.inHours;
      int remainingMinutes = minutes - (hours * 60);
      if (remainingMinutes == 0) {
        return '$hours hour${hours > 1 ? 's' : ''}';
      } else {
        return '$hours hour${hours > 1 ? 's' : ''} $remainingMinutes min';
      }
    }
  }

  String _formatMood(Mood mood) {
    final moodString = mood.toString().split('.').last;
    return moodString.substring(0, 1).toUpperCase() + moodString.substring(1);
  }

  // Add this new method for scheduling dialog
  void _showScheduleDialog(BuildContext context) {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedTime = TimeOfDay(hour: 10, minute: 0);
    bool setReminder = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Schedule Next Session'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(DateFormat.yMMMEd().format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (date != null && context.mounted) {
                      setState(() {
                        selectedDate = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );
                      });
                    }
                  },
                ),
                ListTile(
                  title: const Text('Time'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (time != null && context.mounted) {
                      setState(() {
                        selectedTime = time;
                        selectedDate = DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Set Reminder'),
                  subtitle: const Text('Receive a notification before session'),
                  value: setReminder,
                  onChanged: (value) {
                    setState(() {
                      setReminder = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Save session and set reminder if needed
                  Navigator.pop(context);

                  // Show confirmation
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Session scheduled for ${DateFormat.yMMMEd().add_jm().format(selectedDate)}' +
                              (setReminder ? ' with reminder' : '')),
                    ),
                  );

                  // Navigate to home screen
                  context.go('/home');
                },
                child: const Text('Schedule'),
              ),
            ],
          );
        },
      ),
    );
  }
}
