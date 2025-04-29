// lib/screens/home_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';
import 'package:ai_therapist_app/services/progress_service.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';
import 'package:ai_therapist_app/models/user_progress.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';
import 'package:ai_therapist_app/services/user_profile_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Mood _currentMood = Mood.neutral;
  DateTime? _nextSessionDate;
  late ProgressService _progressService;
  late PreferencesService _preferencesService;
  late UserProgress _progress;
  bool _progressInitialized = false;

  @override
  void initState() {
    super.initState();
    _progressService = serviceLocator<ProgressService>();
    _preferencesService = serviceLocator<PreferencesService>();
    _progress = _progressService.progress;

    // Listen for progress changes
    _progressService.progressChanged.addListener(_onProgressChanged);

    _loadUserData();
  }

  void _onProgressChanged() {
    if (mounted) {
      setState(() {
        _progress = _progressService.progress;
      });
    }
  }

  @override
  void dispose() {
    _progressService.progressChanged.removeListener(_onProgressChanged);
    super.dispose();
  }

  Future<void> _loadUserData() async {
    // In a real app, fetch data from API or local storage
    // Simulate data loading
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      // Example data
      _currentMood = Mood.neutral;
      _nextSessionDate = DateTime.now().add(const Duration(days: 2));
      _progressInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Image.asset(
          'assets/images/hs_logo.png',
          height: 40,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to uplift_logo.png if hs_logo.png doesn't exist
            return Image.asset(
              'assets/images/uplift_logo.png',
              height: 60,
              fit: BoxFit.contain,
            );
          },
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting card
              _buildGreetingCard(),

              const SizedBox(height: 24),

              // Next session card moved up to position #2
              if (_nextSessionDate != null) _buildNextSessionCard(),

              const SizedBox(height: 24),

              // Progress tracking
              _buildProgressCard(),

              const SizedBox(height: 24),

              // Quick mood check
              _buildMoodCheckCard(),

              const SizedBox(height: 24),

              // Session actions
              Center(
                child: _buildActionCard(
                  'View Past Sessions',
                  Icons.history,
                  Colors.purple.shade100,
                  Colors.purple,
                  () => context.go('/history'),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/chat'),
        icon: const Icon(Icons.favorite_border),
        label: const Text('Talk Now'),
      ),
    );
  }

  Widget _buildGreetingCard() {
    final hour = DateTime.now().hour;
    String greeting;

    // Get actual user name from UserProfileService
    final userProfileService = serviceLocator<UserProfileService>();
    String userName = userProfileService.profile?.name ?? "there";

    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, $userName!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Image.asset(
                  'assets/images/therapist_avatar.png',
                  height: 100,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.favorite,
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.favorite_border),
              label: const Text('Start Session'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                minimumSize: const Size(0, 0),
              ),
              onPressed: () => context.go('/chat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodCheckCard() {
    // Get today's mood logs count
    final todayLogsCount = _progress.getTodayMoodLogsCount();
    final hasReachedLimit = todayLogsCount >= 3;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: const Text(
                    'How are you feeling right now?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_progress.currentStreak > 0)
                      _buildStreakBadge(_progress.currentStreak),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.insert_chart_outlined),
                      tooltip: 'View Mood History',
                      onPressed: () => context.go(AppRouter.progress),
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],
            ),
            if (hasReachedLimit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "You've already logged your mood 3 times today. Today's logs: ${todayLogsCount}",
                          style: const TextStyle(
                              color: Colors.amber, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMoodOption(Mood.happy, '🙂'),
                _buildMoodOption(Mood.neutral, '😐'),
                _buildMoodOption(Mood.sad, '😢'),
                _buildMoodOption(Mood.anxious, '😰'),
                _buildMoodOption(Mood.angry, '😠'),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: hasReachedLimit
                    ? () {
                        // Show limit reached dialog
                        _showMoodLimitDialog();
                      }
                    : () {
                        // Log mood and update streak
                        _progressService.logMood(_currentMood);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Mood logged successfully')),
                        );
                      },
                child: const Text('Log My Mood'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoodLimitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily Limit Reached'),
        content: const Text(
            "You've already logged your mood 3 times today. Would you like to view your mood history instead?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go(AppRouter.progress);
            },
            child: const Text('View History'),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodOption(Mood mood, String emoji) {
    final isSelected = mood == _currentMood;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMood = mood;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : null,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: Theme.of(context).primaryColor)
              : null,
        ),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color bgColor,
      Color iconColor, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity, // Make it full width
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextSessionCard() {
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Your Next Session',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              dateFormat.format(_nextSessionDate!),
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Reschedule'),
                  onPressed: () {
                    // Show reschedule page
                    _showRescheduleDialog();
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.notifications),
                  label: const Text('Remind Me'),
                  onPressed: () {
                    // Set up a reminder
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reminder set')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRescheduleDialog() {
    DateTime selectedDate =
        _nextSessionDate ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Reschedule Session'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(DateFormat.yMMMd().format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (date != null) {
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
                    if (time != null) {
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
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Save the new session date
                  setState(() {
                    _nextSessionDate = selectedDate;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Session rescheduled successfully'),
                    ),
                  );
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResourcesGrid() {
    return GridView.count(
      crossAxisCount: 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _buildResourceCard(
          'Journaling',
          'Express thoughts',
          Icons.edit_note,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildResourceCard(
      String title, String subtitle, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          context.go('/resources');
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 36,
                color: color,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakBadge(int streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department,
              color: Colors.orange, size: 14),
          const SizedBox(width: 2),
          Text(
            '$streak',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    if (!_progressInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get consistency information from the progress service
    final consistencyRate = _progressService.getConsistencyRate();
    final consistencyStatus = _progressService.getConsistencyStatus();
    final consistencyColor = _progressService.getConsistencyColor();

    // Determine icon based on consistency status
    IconData consistencyIcon;
    if (consistencyStatus == 'Very Consistent') {
      consistencyIcon = Icons.star;
    } else if (consistencyStatus == 'Consistent') {
      consistencyIcon = Icons.check_circle;
    } else {
      consistencyIcon = Icons.timelapse;
    }

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => context.go(AppRouter.progress),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Consistency',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => context.go(AppRouter.progress),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Consistency badge
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: consistencyColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: consistencyColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(consistencyIcon, color: consistencyColor),
                      const SizedBox(width: 8),
                      Text(
                        consistencyStatus,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: consistencyColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                'Based on your activity in the last 7 days (${(_progress.activeDaysLastWeek)} active days)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    '${_progress.sessionsThisWeek}',
                    'Sessions',
                    Icons.favorite_border,
                  ),
                  _buildStatItem(
                    '${_progress.moodLogsThisWeek}',
                    'Mood Logs',
                    Icons.mood,
                  ),
                  _buildStatItem(
                    '${_progress.currentStreak}',
                    'Day Streak',
                    Icons.local_fire_department,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
