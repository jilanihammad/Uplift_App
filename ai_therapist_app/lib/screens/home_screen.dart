// lib/screens/home_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/models/user_progress.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';
import 'package:ai_therapist_app/services/memory_manager.dart';
import 'package:ai_therapist_app/services/audio_generator.dart';
import 'package:flutter/services.dart';
import 'package:ai_therapist_app/services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  final IProgressService? progressService;
  final IPreferencesService? preferencesService;
  final IUserProfileService? userProfileService;
  
  const HomeScreen({
    Key? key,
    this.progressService,
    this.preferencesService,
    this.userProfileService,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Mood _currentMood = Mood.neutral;
  DateTime? _nextSessionDate;
  late IProgressService _progressService;
  late IPreferencesService _preferencesService;
  late IUserProfileService _userProfileService;
  late UserProgress _progress;
  bool _progressInitialized = false;

  @override
  void initState() {
    super.initState();
    _progressService = widget.progressService ?? DependencyContainer().progress;
    _preferencesService = widget.preferencesService ?? DependencyContainer().preferences;
    _userProfileService = widget.userProfileService ?? DependencyContainer().userProfile;
    _progress = _progressService.progress;

    // Listen for progress changes
    _progressService.progressChanged.addListener(_onProgressChanged);

    _loadUserData();

    // Defer heavy initializations to after navigation
    Future.microtask(() async {
      final container = DependencyContainer();
      if (container.isRegistered<MemoryManager>()) {
        final memoryManager = container.get<MemoryManager>();
        await memoryManager.initializeOnlyIfNeeded();
      }
      if (container.isRegistered<AudioGenerator>()) {
        final audioGenerator = container.get<AudioGenerator>();
        await audioGenerator.initializeOnlyIfNeeded();
      }
      // Add any other heavy service initializations here
    });
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
    return WillPopScope(
      onWillPop: () async {
        // If already on home, show exit confirmation
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Are you sure you want to exit the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          // End all initializations and exit the app
          // Use SystemNavigator.pop() for Android
          // Optionally, clean up services here if needed
          Future.delayed(const Duration(milliseconds: 100), () {
            // Add any cleanup logic here if needed
          });
          // Import 'package:flutter/services.dart' at the top
          SystemNavigator.pop();
          return true;
        }
        // Don't exit
        return false;
      },
      child: Scaffold(
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

                // Remove the "View Past Sessions" section and spacing
                // const SizedBox(height: 24),
                // Center(
                //   child: _buildActionCard(
                //     'View Past Sessions',
                //     Icons.history,
                //     Colors.purple.shade100,
                //     Colors.purple,
                //     () => context.go('/history'),
                //   ),
                // ),
                // const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go('/chat'),
          icon: const Icon(Icons.favorite),
          label: const Text('Talk Now'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildGreetingCard() {
    final hour = DateTime.now().hour;
    String greeting;

    // Get display name using consistent logic
    String userName = _userProfileService.profile?.displayName ?? "there";

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
        padding: const EdgeInsets.all(18),
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
                          fontSize: 20,
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
                      Icons.favorite_outline,
                      size: 80,
                      color: Colors.pinkAccent,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.favorite),
              label: const Text('Start Session'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_progress.currentStreak > 0)
                  _buildStreakBadge(_progress.currentStreak),
              ],
            ),
            if (hasReachedLimit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "You've already logged your mood 3 times today. Today's logs: ${todayLogsCount}",
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 6),
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
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  backgroundColor:
                      Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
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
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    // Show reschedule page
                    _showRescheduleDialog();
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.notifications),
                  label: const Text('Remind Me'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () async {
                    print('Remind Me button pressed');
                    if (_nextSessionDate == null) {
                      print('No session scheduled to remind!');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('No session scheduled to remind!')),
                      );
                      return;
                    }
                    try {
                      print(
                          'Scheduling notification for: \\${_nextSessionDate}');
                      await NotificationService().scheduleNotification(
                        id: 1001, // Use a fixed or unique ID
                        title: 'Therapy Session Reminder',
                        body: 'You have a therapy session scheduled now.',
                        scheduledDateTime: _nextSessionDate!,
                      );
                      print('Notification scheduled successfully');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reminder set!')),
                      );
                    } catch (e, stack) {
                      print('Error scheduling notification: \\${e.toString()}');
                      print(stack);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Failed to set reminder: \\${e.toString()}')),
                      );
                    }
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
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
                  Row(
                    children: [
                      const Text(
                        'Consistency',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Consistency badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: consistencyColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: consistencyColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(consistencyIcon,
                                color: consistencyColor, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              consistencyStatus,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: consistencyColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () => context.go(AppRouter.progress),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    '${_progress.sessionsThisWeek}',
                    'Sessions',
                    Icons.favorite,
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
    // Define the soft colors for each icon
    Color iconColor;
    Color bgColor;

    if (icon == Icons.favorite) {
      // Soft pink for heart icon
      iconColor = const Color(0xFFFF80AB);
      bgColor = const Color(0xFFFFEBEE);
    } else if (icon == Icons.mood) {
      // Soft green for smiley icon
      iconColor = const Color(0xFF66BB6A);
      bgColor = const Color(0xFFE8F5E9);
    } else if (icon == Icons.local_fire_department) {
      // Soft orange for fire icon
      iconColor = const Color(0xFFFF9800);
      bgColor = const Color(0xFFFFF3E0);
    } else {
      // Default colors for any other icons
      iconColor = Theme.of(context).primaryColor;
      bgColor = Theme.of(context).primaryColor.withOpacity(0.1);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: iconColor,
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
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
