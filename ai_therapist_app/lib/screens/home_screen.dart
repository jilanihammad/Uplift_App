// lib/screens/home_screen.dart
// import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ai_therapist_app/config/theme.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/models/user_progress.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';
import 'package:flutter/services.dart';
import 'package:ai_therapist_app/services/notification_service.dart';
import 'package:ai_therapist_app/models/session_reminder.dart';
import 'package:ai_therapist_app/utils/feature_flags.dart';

class HomeScreen extends StatefulWidget {
  final IProgressService? progressService;
  final IUserProfileService? userProfileService;
  final ISessionScheduleService? sessionScheduleService;

  const HomeScreen({
    super.key,
    this.progressService,
    this.userProfileService,
    this.sessionScheduleService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Mood _currentMood = Mood.neutral;
  DateTime? _nextSessionDate;
  late IProgressService _progressService;
  late IUserProfileService _userProfileService;
  late ISessionScheduleService _sessionScheduleService;
  late UserProgress _progress;
  bool _progressInitialized = false;

  @override
  void initState() {
    super.initState();
    _progressService = widget.progressService ?? DependencyContainer().progress;
    _userProfileService =
        widget.userProfileService ?? DependencyContainer().userProfile;
    _sessionScheduleService =
        widget.sessionScheduleService ?? DependencyContainer().sessionSchedule;
    _progress = _progressService.progress;

    unawaited(_progressService.init());

    // Listen for progress changes
    _progressService.progressChanged.addListener(_onProgressChanged);

    _loadUserData();

    // Services are automatically initialized through dependency injection
    // No manual initialization needed here - services initialize when first accessed
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
    try {
      await _progressService.syncSessionData();
      if (FeatureFlags.isMoodPersistenceEnabled) {
        await _progressService.syncMoodEntries(force: true);
      }
    } catch (e) {
      debugPrint('Error syncing session data: $e');
    }

    SessionReminder? reminder;
    try {
      reminder = await _sessionScheduleService.loadReminder(forceRefresh: true);
    } catch (e) {
      debugPrint('Error loading session reminder: $e');
      reminder = _sessionScheduleService.currentReminder;
    }

    if (!mounted) return;

    setState(() {
      _currentMood = Mood.neutral;
      _nextSessionDate = reminder?.scheduledTime;
      _progressInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) {
          return;
        }

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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Exit'),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          Future.delayed(const Duration(milliseconds: 100), () {
            // Add any cleanup logic here if needed
          });
          SystemNavigator.pop();
        }
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
              onPressed: () => context.go(AppRouter.settings),
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

                const SizedBox(height: 16),

                // Next session card moved up to position #2
                _buildNextSessionCard(),

                const SizedBox(height: 16),

                // Progress tracking
                _buildProgressCard(),

                const SizedBox(height: 16),

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
        floatingActionButton: null,
      ),
    );
  }

  Widget _buildGreetingCard() {
    final hour = DateTime.now().hour;
    String greeting;

    // Get display name using consistent logic
    String userName = _userProfileService.profile?.displayName ?? "there";

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '$greeting, $userName!',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const Icon(
                  Icons.favorite_border,
                  size: 56,
                  color: Colors.pinkAccent,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.favorite, size: 20),
                label: const Text('Start Session'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  shape: const StadiumBorder(),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => context.go(AppRouter.chat),
              ),
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
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade600, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "You've logged 3 moods today. Logging another will update your most recent mood.",
                          style: TextStyle(
                            color: Colors.blue.shade800,
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
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final success =
                      await _progressService.logMood(_currentMood);

                  if (success) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Mood logged successfully'),
                      ),
                    );

                    final showLocalMessage = _progressService
                            .consumeLastMoodLogWasLocalOnly() ||
                        _progressService.consumePendingMoodSyncError();
                    if (showLocalMessage) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Saved locally; we'll sync when you're online.",
                          ),
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content:
                            Text('Unable to log mood. Please try again.'),
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  backgroundColor:
                      Theme.of(context).primaryColor.withValues(alpha: 0.1),
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
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
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
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
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

  Widget _buildNextSessionCard() {
    final dateFormat = DateFormat.yMMMd().add_jm();
    final hasSession = _nextSessionDate != null;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.calendar_today,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Next Session',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasSession
                          ? dateFormat.format(_nextSessionDate!)
                          : 'No session scheduled yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      hasSession ? Icons.edit_calendar : Icons.add_circle,
                    ),
                    label: Text(hasSession ? 'Reschedule' : 'Schedule'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: _showRescheduleDialog,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Remind Me'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: hasSession
                        ? () async {
                            final now = DateTime.now();
                            if (_nextSessionDate!.isBefore(now)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'The scheduled session is in the past. Please reschedule.',
                                  ),
                                ),
                              );
                              return;
                            }

                            try {
                              await NotificationService().scheduleNotification(
                                id: 1001,
                                title: 'Therapy Session Reminder',
                                body:
                                    'You have a therapy session scheduled now.',
                                scheduledDateTime: _nextSessionDate!,
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reminder set!')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to set reminder: $e'),
                                ),
                              );
                            }
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRescheduleDialog() {
    final hasExistingSchedule = _nextSessionDate != null;
    DateTime selectedDate = hasExistingSchedule
        ? _nextSessionDate!
        : DateTime.now().add(const Duration(hours: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);
    final dialogTitle =
        hasExistingSchedule ? 'Reschedule Session' : 'Schedule Session';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(dialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(DateFormat.yMMMd().format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final now = DateTime.now();
                    final firstDate =
                        DateTime(now.year, now.month, now.day);
                    final defaultLastDate =
                        firstDate.add(const Duration(days: 90));
                    final effectiveLastDate = selectedDate.isAfter(defaultLastDate)
                        ? selectedDate.add(const Duration(days: 30))
                        : defaultLastDate;
                    final effectiveInitialDate = selectedDate.isBefore(firstDate)
                        ? firstDate
                        : selectedDate;

                    final date = await showDatePicker(
                      context: context,
                      initialDate: effectiveInitialDate,
                      firstDate: firstDate,
                      lastDate: effectiveLastDate,
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
                onPressed: () async {
                  Navigator.pop(context);

                  try {
                    final reminder =
                        await _sessionScheduleService.scheduleSession(
                      selectedDate,
                      title: 'Next Therapy Session',
                    );

                    if (!mounted) return;

                    setState(() {
                      _nextSessionDate =
                          reminder?.scheduledTime ?? selectedDate;
                    });

                    final formattedDate = DateFormat.yMMMd().add_jm().format(
                          (_nextSessionDate ?? selectedDate),
                        );

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(hasExistingSchedule
                            ? 'Session rescheduled for $formattedDate'
                            : 'Session scheduled for $formattedDate'),
                      ),
                    );
                  } catch (e) {
                    debugPrint('Error scheduling session reminder: $e');

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'We couldn\'t update the schedule. Please try again.'),
                      ),
                    );
                  }
                },
                child: Text(hasExistingSchedule ? 'Confirm' : 'Schedule'),
              ),
            ],
          );
        },
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
    final consistencyColor = _progressService.getConsistencyColor(context);

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
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: consistencyColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: consistencyColor),
                        ),
                        child: Tooltip(
                          message: consistencyStatus,
                          child: Icon(
                            consistencyIcon,
                            color: consistencyColor,
                            size: 16,
                          ),
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
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
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
                    'Days Logged',
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
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();
    final isLight = theme.brightness == Brightness.light;

    Color resolveColor() {
      if (icon == Icons.favorite) {
        return palette?.accentPrimary ?? theme.colorScheme.secondary;
      }
      if (icon == Icons.mood) {
        return palette?.accentSecondary ?? theme.colorScheme.tertiary;
      }
      if (icon == Icons.local_fire_department) {
        return theme.colorScheme.primary;
      }
      return theme.colorScheme.primary;
    }

    final iconColor = resolveColor();
    final backgroundOpacity = isLight ? 0.14 : 0.22;
    final bgColor = iconColor.withValues(alpha: backgroundOpacity);
    final textColor =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;

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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
