import 'package:flutter/material.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/models/user_progress.dart';
import 'package:ai_therapist_app/models/user_task.dart';
import 'package:ai_therapist_app/services/tasks_service.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class ProgressScreen extends StatefulWidget {
  final IProgressService? progressService;
  final int initialTabIndex;

  const ProgressScreen({
    super.key,
    this.progressService,
    this.initialTabIndex = 0, // Default to 0 (Overview)
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late IProgressService _progressService;
  late UserProgress _progress;
  late TasksService _tasksService;
  List<UserTask> _tasks = [];
  int _realSessionCount = 0;
  int _currentStreak = 0;
  int _longestStreak = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _progressService = widget.progressService ?? DependencyContainer().progress;
    _progress = _progressService.progress;
    _tasksService = TasksService();

    // Set the initial tab based on the provided argument
    _tabController.index = widget.initialTabIndex;

    // Initialize services and load data
    _initServices();

    // Listen for progress changes
    _progressService.progressChanged.addListener(_onProgressChanged);
  }

  Future<void> _initServices() async {
    await _tasksService.init();
    await _loadRealSessionCount();
    if (mounted) {
      setState(() {
        _tasks = _tasksService.tasks;
      });
    }
  }

  Future<void> _loadRealSessionCount() async {
    try {
      final sessionRepository = DependencyContainer().sessionRepository;
      final sessions = await sessionRepository.getSessions();

      // Calculate streaks based on session dates
      _calculateStreaks(sessions);

      if (mounted) {
        setState(() {
          _realSessionCount = sessions.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading session count: $e');
    }
  }

  void _calculateStreaks(List<dynamic> sessions) {
    if (sessions.isEmpty) {
      _currentStreak = 0;
      _longestStreak = 0;
      return;
    }

    // Get unique days with sessions, sorted by date
    final sessionDays = sessions
        .map((session) {
          try {
            // Assuming session has a createdAt or similar field
            final date = session.createdAt ?? DateTime.now();
            return DateTime(date.year, date.month, date.day);
          } catch (e) {
            return DateTime.now();
          }
        })
        .toSet()
        .toList()
      ..sort();

    // Calculate current streak (consecutive days up to today)
    _currentStreak = 0;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    for (int i = sessionDays.length - 1; i >= 0; i--) {
      final daysDiff = todayDay.difference(sessionDays[i]).inDays;
      if (daysDiff == _currentStreak ||
          (daysDiff == _currentStreak + 1 && _currentStreak == 0)) {
        _currentStreak++;
      } else {
        break;
      }
    }

    // Calculate longest streak
    _longestStreak = 0;
    int tempStreak = 1;

    for (int i = 1; i < sessionDays.length; i++) {
      if (sessionDays[i].difference(sessionDays[i - 1]).inDays == 1) {
        tempStreak++;
      } else {
        _longestStreak = math.max(_longestStreak, tempStreak);
        tempStreak = 1;
      }
    }
    _longestStreak = math.max(_longestStreak, tempStreak);
  }

  void _onProgressChanged() {
    if (mounted) {
      setState(() {
        _progress = _progressService.progress;
      });
    }
  }

  Future<void> _toggleTaskCompletion(String taskId, bool isCompleted) async {
    if (isCompleted) {
      await _tasksService.completeTask(taskId);
    } else {
      await _tasksService.uncompleteTask(taskId);
    }
    if (mounted) {
      setState(() {
        _tasks = _tasksService.tasks;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _progressService.progressChanged.removeListener(_onProgressChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Progress'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Mood'),
            Tab(text: 'Tasks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildMoodTab(),
          _buildTasksTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStreakCard(),
          const SizedBox(height: 16),
          _buildStatsCard(),
          const SizedBox(height: 16),
          _buildRecentSessionsCard(),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Streak',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStreakItem(
                  _currentStreak,
                  'Current',
                  Icons.local_fire_department,
                  Colors.orange,
                ),
                _buildStreakItem(
                  _longestStreak,
                  'Longest',
                  Icons.emoji_events,
                  Colors.amber,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakItem(int count, String label, IconData icon, Color color) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: color.withOpacity(0.2),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(icon, color: color, size: 16),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activity Stats',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatRow('Total Sessions', _realSessionCount.toString(),
                Icons.psychology),
            const Divider(),
            _buildStatRow('Mood Entries',
                _progress.moodHistory.length.toString(), Icons.mood),
            const Divider(),
            _buildStatRow('Achievements',
                _progress.achievements.length.toString(), Icons.emoji_events),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessionsCard() {
    final sessionEntries = _progress.sessionHistory.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    final recentSessions = sessionEntries.take(3).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Sessions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (recentSessions.isEmpty)
              const Center(
                child: Text(
                  'No sessions yet',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentSessions.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final session = recentSessions[index];
                  final date = session.key;
                  final duration = session.value;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).primaryColor.withOpacity(0.2),
                      child: Icon(
                        Icons.psychology,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    title: Text(
                      DateFormat.MMMd().format(date),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '$duration minutes',
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodTab() {
    final moodData = _progressService.getMoodDataForLastDays(30);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mood History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (moodData.isEmpty)
                    const Center(
                      heightFactor: 3,
                      child: Text(
                        'No mood data yet',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 200,
                      child: _buildMoodChart(moodData),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildMoodInsightsCard(),
        ],
      ),
    );
  }

  Widget _buildMoodChart(List<MapEntry<DateTime, int>> moodData) {
    // This is a placeholder for a chart widget
    // In a real app, use a charting library like fl_chart
    return Center(
      child: Text('Mood chart would go here (${moodData.length} data points)'),
    );
  }

  Widget _buildMoodInsightsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mood Insights',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInsightItem(
              'You\'ve logged your mood ${_progress.moodHistory.length} times',
              Icons.insert_chart,
              Colors.purple,
            ),
            const SizedBox(height: 8),
            if (_progress.moodHistory.length >= 5)
              _buildInsightItem(
                'Your mood has been improving over the past week',
                Icons.trending_up,
                Colors.green,
              ),
            if (_progress.currentStreak > 0)
              _buildInsightItem(
                'You\'ve logged your mood for ${_progress.currentStreak} days in a row',
                Icons.local_fire_department,
                Colors.orange,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(String text, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTasksTab() {
    // Show pending tasks first, then completed ones
    final pendingTasks = _tasks.where((task) => !task.isCompleted).toList();
    final completedTasks = _tasks.where((task) => task.isCompleted).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'My Tasks',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_tasks.isNotEmpty)
                Text(
                  '${completedTasks.length}/${_tasks.length} completed',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'No Tasks Yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add tasks from your therapy session action items',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Pending tasks
                    if (pendingTasks.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'To Do',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...pendingTasks.map((task) => _buildTaskCard(task)),
                      const SizedBox(height: 16),
                    ],

                    // Completed tasks
                    if (completedTasks.isNotEmpty) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Completed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...completedTasks.map((task) => _buildTaskCard(task)),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(UserTask task) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: task.isCompleted
              ? Colors.green.withOpacity(0.2)
              : Theme.of(context).primaryColor.withOpacity(0.2),
          child: Icon(
            task.isCompleted ? Icons.check_circle : Icons.task_alt,
            color: task.isCompleted
                ? Colors.green
                : Theme.of(context).primaryColor,
          ),
        ),
        title: Text(
          task.text,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted ? Colors.grey[600] : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Added on ${DateFormat.yMMMd().format(task.dateAdded)}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            if (task.isCompleted && task.completedDate != null)
              Text(
                'Completed on ${DateFormat.yMMMd().format(task.completedDate!)}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: Checkbox(
          value: task.isCompleted,
          onChanged: (value) {
            if (value != null) {
              _toggleTaskCompletion(task.id, value);
            }
          },
        ),
      ),
    );
  }
}
