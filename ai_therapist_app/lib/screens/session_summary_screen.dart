import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../models/therapy_message.dart';
import '../widgets/mood_selector.dart';
import 'widgets/session_summary_card.dart';
import 'widgets/action_items_card.dart';

class SessionSummaryScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sessionDuration = messages.isNotEmpty
        ? now.difference(messages.first.timestamp)
        : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Summary'),
        automaticallyImplyLeading: false,
        actions: [
          // Removed share button as requested
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session summary
            const SizedBox(height: 8),
            SessionSummaryCard(summary: summary),

            const SizedBox(height: 24),

            // Action items
            const Text(
              'Recommended Action Items',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ActionItemsCard(actionItems: actionItems),

            const SizedBox(height: 32),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Schedule Next'),
                  onPressed: () {
                    // Show calendar dialog for scheduling next session
                    _showScheduleDialog(context);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.home),
                  label: const Text('Back to Home'),
                  onPressed: () {
                    // Navigate back to home
                    context.go('/home');
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),
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
