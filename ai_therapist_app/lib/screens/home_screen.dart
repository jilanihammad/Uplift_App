// lib/screens/home_screen.dart
// import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/models/user_progress.dart';
import 'package:ai_therapist_app/config/routes.dart';
// TODO: Mood logging - commented out for backwards compatibility
// import 'package:ai_therapist_app/widgets/mood_selector.dart';
import 'package:flutter/services.dart';
import 'package:ai_therapist_app/services/notification_service.dart';
import 'package:ai_therapist_app/services/subscription_manager.dart';
import 'package:ai_therapist_app/models/subscription_tier.dart';
import 'package:ai_therapist_app/screens/subscription_screen.dart';

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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // TODO: Mood logging - commented out for backwards compatibility
  // Mood _currentMood = Mood.neutral;
  DateTime? _nextSessionDate;
  late IProgressService _progressService;
  late IPreferencesService _preferencesService;
  late IUserProfileService _userProfileService;
  late SubscriptionManager _subscriptionManager;
  late UserProgress _progress;
  bool _progressInitialized = false;
  SubscriptionTier _currentTier = SubscriptionTier.none;
  bool _longPressDetected = false;
  late AnimationController _buttonAnimationController;
  late Animation<double> _buttonScaleAnimation;
  late AnimationController _cardAnimationController;
  late List<Animation<double>> _cardAnimations;

  @override
  void initState() {
    super.initState();
    _progressService = widget.progressService ?? DependencyContainer().progress;
    _preferencesService = widget.preferencesService ?? DependencyContainer().preferences;
    _userProfileService = widget.userProfileService ?? DependencyContainer().userProfile;
    _subscriptionManager = DependencyContainer().subscriptionManager;
    _progress = _progressService.progress;

    // Initialize button animation
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _buttonScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(
      parent: _buttonAnimationController,
      curve: Curves.easeInOut,
    ));

    // Initialize card animations
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    // Create staggered animations for 4 cards
    _cardAnimations = List.generate(4, (index) {
      final start = index * 0.15; // 150ms stagger between each card
      final end = start + 0.6; // Each animation takes 600ms
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _cardAnimationController,
        curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOutBack),
      ));
    });

    // Start card animations after initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cardAnimationController.forward();
      }
    });

    // Listen for progress changes
    _progressService.progressChanged.addListener(_onProgressChanged);
    
    // Listen for subscription tier changes
    _subscriptionManager.tierStream.listen(_onTierChanged);
    _currentTier = _subscriptionManager.currentTier;

    _loadUserData();
    _initializeSubscriptionManager();

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

  void _onTierChanged(SubscriptionTier newTier) {
    if (mounted) {
      setState(() {
        _currentTier = newTier;
      });
      debugPrint('HomeScreen: Subscription tier changed to $newTier');
    }
  }

  Future<void> _initializeSubscriptionManager() async {
    try {
      await _subscriptionManager.initialize();
      debugPrint('HomeScreen: SubscriptionManager initialized');
    } catch (e) {
      debugPrint('HomeScreen: Error initializing SubscriptionManager: $e');
    }
  }

  @override
  void dispose() {
    _progressService.progressChanged.removeListener(_onProgressChanged);
    _buttonAnimationController.dispose();
    _cardAnimationController.dispose();
    super.dispose();
  }

  String _getRelativeSessionTime() {
    if (_nextSessionDate == null) return 'Not scheduled';
    
    final now = DateTime.now();
    final sessionDate = _nextSessionDate!;
    final timeFormat = DateFormat('h:mm a');
    
    // Calculate days difference
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);
    final daysDifference = sessionDay.difference(today).inDays;
    
    if (daysDifference == 0) {
      return 'Today · ${timeFormat.format(sessionDate)}';
    } else if (daysDifference == 1) {
      return 'Tomorrow · ${timeFormat.format(sessionDate)}';
    } else if (daysDifference == -1) {
      return 'Yesterday · ${timeFormat.format(sessionDate)}';
    } else if (daysDifference > 1 && daysDifference <= 7) {
      return '${DateFormat('EEEE').format(sessionDate)} · ${timeFormat.format(sessionDate)}';
    } else {
      return '${DateFormat('MMM d').format(sessionDate)} · ${timeFormat.format(sessionDate)}';
    }
  }

  Future<void> _loadUserData() async {
    // In a real app, fetch data from API or local storage
    // Simulate data loading
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Sync session data to ensure consistency card shows real data
    try {
      await _progressService.syncSessionData();
    } catch (e) {
      debugPrint('Error syncing session data: $e');
    }

    if (mounted) {
      setState(() {
        // Example data
        // TODO: Mood logging - commented out for backwards compatibility
        // _currentMood = Mood.neutral;
        _nextSessionDate = DateTime.now().add(const Duration(days: 2));
        _progressInitialized = true;
      });
    }
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
                _buildAnimatedCard(_buildGreetingCard(), 0),

                const SizedBox(height: 16),

                // Next session card moved up to position #2
                if (_nextSessionDate != null) _buildAnimatedCard(_buildNextSessionCard(), 1),

                const SizedBox(height: 16),

                // Progress tracking
                _buildAnimatedCard(_buildProgressCard(), 2),

                const SizedBox(height: 16),

                // TODO: Mood logging - commented out for backwards compatibility
                // Quick mood check
                // _buildAnimatedCard(_buildMoodCheckCard(), 3),

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
        floatingActionButton: _buildAnimatedFloatingActionButton(),
      ),
    );
  }

  Widget _buildAnimatedCard(Widget card, int index) {
    if (index >= _cardAnimations.length) return card;
    
    return AnimatedBuilder(
      animation: _cardAnimations[index],
      builder: (context, child) {
        final animationValue = _cardAnimations[index].value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 50 * (1 - animationValue)),
          child: Opacity(
            opacity: animationValue,
            child: card,
          ),
        );
      },
    );
  }

  Widget _buildGreetingCard() {
    final hour = DateTime.now().hour;
    String greeting;
    String weatherEmoji;

    // Get display name using consistent logic
    String userName = _userProfileService.profile?.displayName ?? "there";

    if (hour < 12) {
      greeting = 'Good Morning';
      weatherEmoji = '🌅'; // Sunrise
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      weatherEmoji = '☀️'; // Sun
    } else {
      greeting = 'Good Evening';
      weatherEmoji = '🌙'; // Moon
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
                        '$greeting $weatherEmoji, $userName!',
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
          ],
        ),
      ),
    );
  }

  // TODO: Mood logging - commented out for backwards compatibility
  // Widget _buildMoodCheckCard() {
  //   // Get today's mood logs count
  //   final todayLogsCount = _progress.getTodayMoodLogsCount();
  //   final hasReachedLimit = todayLogsCount >= 3;

  //   return Card(
  //     elevation: 2,
  //     child: Padding(
  //       padding: const EdgeInsets.all(12),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             mainAxisAlignment: MainAxisAlignment.center,
  //             children: [
  //               if (_progress.currentStreak > 0)
  //                 _buildStreakBadge(_progress.currentStreak),
  //             ],
  //           ),
  //           if (hasReachedLimit)
  //             Padding(
  //               padding: const EdgeInsets.symmetric(vertical: 6.0),
  //               child: Container(
  //                 padding: const EdgeInsets.all(10),
  //                 decoration: BoxDecoration(
  //                   color: Colors.amber.shade100,
  //                   borderRadius: BorderRadius.circular(8),
  //                   border: Border.all(color: Colors.amber),
  //                 ),
  //                 child: Row(
  //                   children: [
  //                     const Icon(Icons.info_outline,
  //                         color: Colors.amber, size: 16),
  //                     const SizedBox(width: 8),
  //                     Expanded(
  //                       child: Text(
  //                         "You've already logged your mood 3 times today. Today's logs: ${todayLogsCount}",
  //                         style: const TextStyle(
  //                           color: Colors.amber,
  //                           fontWeight: FontWeight.bold,
  //                           fontSize: 12,
  //                         ),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           const SizedBox(height: 12),
  //           Row(
  //             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  //             children: [
  //               _buildMoodOption(Mood.happy, '🙂'),
  //               _buildMoodOption(Mood.neutral, '😐'),
  //               _buildMoodOption(Mood.sad, '😢'),
  //               _buildMoodOption(Mood.anxious, '😰'),
  //               _buildMoodOption(Mood.angry, '😠'),
  //             ],
  //           ),
  //           const SizedBox(height: 6),
  //           Center(
  //             child: TextButton(
  //               onPressed: hasReachedLimit
  //                   ? () {
  //                       // Show limit reached dialog
  //                       _showMoodLimitDialog();
  //                     }
  //                   : () {
  //                       // Log mood and update streak
  //                       _progressService.logMood(_currentMood);

  //                       ScaffoldMessenger.of(context).showSnackBar(
  //                         const SnackBar(
  //                             content: Text('Mood logged successfully')),
  //                       );
  //                     },
  //               style: TextButton.styleFrom(
  //                 padding:
  //                     const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  //                 backgroundColor:
  //                     Theme.of(context).primaryColor.withOpacity(0.1),
  //                 shape: RoundedRectangleBorder(
  //                   borderRadius: BorderRadius.circular(30),
  //                 ),
  //               ),
  //               child: const Text('Log My Mood'),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // TODO: Mood logging - commented out for backwards compatibility
  // void _showMoodLimitDialog() {
  //   showDialog(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: const Text('Daily Limit Reached'),
  //       content: const Text(
  //           "You've already logged your mood 3 times today. Would you like to view your mood history instead?"),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('Cancel'),
  //         ),
  //         TextButton(
  //           onPressed: () {
  //             Navigator.pop(context);
  //             context.go(AppRouter.progress);
  //           },
  //           child: const Text('View History'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // TODO: Mood logging - commented out for backwards compatibility
  // Widget _buildMoodOption(Mood mood, String emoji) {
  //   final isSelected = mood == _currentMood;

  //   return GestureDetector(
  //     onTap: () {
  //       setState(() {
  //         _currentMood = mood;
  //       });
  //     },
  //     child: Container(
  //       padding: const EdgeInsets.all(12),
  //       decoration: BoxDecoration(
  //         color: isSelected
  //             ? Theme.of(context).primaryColor.withOpacity(0.1)
  //             : Theme.of(context).colorScheme.surface,
  //         borderRadius: BorderRadius.circular(24),
  //         border: Border.all(
  //           color: isSelected
  //               ? Theme.of(context).primaryColor
  //               : Theme.of(context).colorScheme.outline,
  //           width: isSelected ? 2 : 1,
  //         ),
  //         boxShadow: isSelected
  //             ? [
  //                 BoxShadow(
  //                   color: Theme.of(context).primaryColor.withOpacity(0.2),
  //                   blurRadius: 8,
  //                   offset: const Offset(0, 2),
  //                 )
  //               ]
  //             : null,
  //       ),
  //       child: Text(
  //         emoji,
  //         style: const TextStyle(fontSize: 24),
  //       ),
  //     ),
  //   );
  // }

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
            Row(
              children: [
                // Calendar icon with day abbreviation
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('MMM').format(_nextSessionDate!).toUpperCase(),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      Text(
                        DateFormat('d').format(_nextSessionDate!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      Text(
                        DateFormat('E').format(_nextSessionDate!).toUpperCase(),
                        style: TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Relative time text
                Expanded(
                  child: Text(
                    _getRelativeSessionTime(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
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
          padding: const EdgeInsets.all(12),
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
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
              const SizedBox(height: 12),

              // Stats row or empty state - Updated to exclude mood logs
              _progress.sessionsThisWeek == 0 && _progress.currentStreak == 0
                ? _buildEmptyState()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatItem(
                        '${_progress.sessionsThisWeek}',
                        'Sessions',
                        Icons.favorite,
                      ),
                      // TODO: Mood logging - commented out for backwards compatibility
                      // _buildStatItem(
                      //   '${_progress.moodLogsThisWeek}',
                      //   'Mood Logs',
                      //   Icons.mood,
                      // ),
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

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          // Friendly illustration using emoji
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '🌟',
                style: TextStyle(fontSize: 30),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Let\'s start your first conversation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your journey to better mental health begins here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedFloatingActionButton() {
    return AnimatedBuilder(
      animation: _buttonScaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _buttonScaleAnimation.value,
          child: GestureDetector(
            onLongPress: kDebugMode ? () {
              _longPressDetected = true;
              debugPrint('Developer bypass activated: Long press detected');
              HapticFeedback.mediumImpact();
              _startSession();
            } : null,
            child: FloatingActionButton.extended(
              onPressed: () async {
                _longPressDetected = false; // Reset for normal press
                // Trigger press animation
                await _buttonAnimationController.forward();
                await _buttonAnimationController.reverse();
                
                // Execute action after animation
                _startSession();
              },
              icon: Icon(
                kDebugMode && _currentTier == SubscriptionTier.none 
                    ? Icons.developer_mode 
                    : Icons.favorite
              ),
              label: Text(
                kDebugMode && _currentTier == SubscriptionTier.none
                    ? '${_getSessionButtonText()} (Long press to bypass)'
                    : _getSessionButtonText()
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: _buttonScaleAnimation.value == 1.0 ? 4 : 2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    final numericValue = int.tryParse(value) ?? 0;
    final hasActivity = numericValue > 0;
    
    // Define colors based on activity
    Color iconColor;
    Color bgColor;
    Color activeColor;

    if (icon == Icons.favorite) {
      activeColor = const Color(0xFFFF80AB); // Soft pink
      iconColor = hasActivity ? activeColor : Colors.grey.shade400;
      bgColor = hasActivity ? const Color(0xFFFFEBEE) : Colors.grey.shade100;
    } else if (icon == Icons.mood) {
      activeColor = const Color(0xFF66BB6A); // Soft green
      iconColor = hasActivity ? activeColor : Colors.grey.shade400;
      bgColor = hasActivity ? const Color(0xFFE8F5E9) : Colors.grey.shade100;
    } else if (icon == Icons.local_fire_department) {
      activeColor = const Color(0xFFFF9800); // Soft orange
      iconColor = hasActivity ? activeColor : Colors.grey.shade400;
      bgColor = hasActivity ? const Color(0xFFFFF3E0) : Colors.grey.shade100;
    } else {
      activeColor = Theme.of(context).primaryColor;
      iconColor = hasActivity ? activeColor : Colors.grey.shade400;
      bgColor = hasActivity ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey.shade100;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: hasActivity ? [
                BoxShadow(
                  color: activeColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ] : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                icon,
                key: ValueKey('$icon-$hasActivity'),
                color: iconColor,
                size: hasActivity ? 22 : 20,
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: hasActivity ? Colors.black87 : Colors.grey.shade600,
            ),
            child: Text(value),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: hasActivity 
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)
                : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  /// Get appropriate button text based on subscription tier
  String _getSessionButtonText() {
    switch (_currentTier) {
      case SubscriptionTier.none:
        return 'Start Free Trial';
      case SubscriptionTier.trial:
        return 'Talk Now';
      case SubscriptionTier.basic:
        return 'Start Chat';
      case SubscriptionTier.premium:
        return 'Talk Now';
    }
  }

  /// Start a session based on subscription tier
  void _startSession() {
    // Developer bypass: Long press (3+ seconds) bypasses subscription check
    if (kDebugMode && _longPressDetected) {
      debugPrint('Developer bypass: Accessing chat without subscription');
      context.go('/chat');
      return;
    }
    
    if (_currentTier.allowsChatSessions) {
      // All paid tiers (basic and premium) can access chat
      context.go('/chat');
    } else {
      // Free tier - navigate directly to subscription screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const SubscriptionScreen(),
        ),
      );
    }
  }

}
