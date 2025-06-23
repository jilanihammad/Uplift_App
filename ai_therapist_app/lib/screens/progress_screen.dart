import 'package:flutter/material.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/services/progress_service.dart';
import 'package:ai_therapist_app/models/user_progress.dart';
import 'package:intl/intl.dart';

class ProgressScreen extends StatefulWidget {
  final IProgressService? progressService;
  
  const ProgressScreen({
    Key? key,
    this.progressService,
  }) : super(key: key);

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late IProgressService _progressService;
  late UserProgress _progress;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _progressService = widget.progressService ?? serviceLocator<ProgressService>();
    _progress = _progressService.progress;
    
    // Listen for progress changes
    _progressService.progressChanged.addListener(_onProgressChanged);
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
                  _progress.currentStreak, 
                  'Current',
                  Icons.local_fire_department,
                  Colors.orange,
                ),
                _buildStreakItem(
                  _progress.longestStreak, 
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
            _buildStatRow('Total Sessions', 
              _progress.sessionHistory.length.toString(),
              Icons.psychology),
            const Divider(),
            _buildStatRow('Mood Entries', 
              _progress.moodHistory.length.toString(),
              Icons.mood),
            const Divider(),
            _buildStatRow('Achievements', 
              _progress.achievements.length.toString(),
              Icons.emoji_events),
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
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
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
    // Using the achievements model for now, but presenting them as tasks
    final tasks = _progress.achievements;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tasks to Complete',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.task_alt, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No Tasks Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tasks will be added after therapy sessions',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                      child: Icon(
                        task.icon,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    title: Text(
                      task.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(task.description),
                        const SizedBox(height: 4),
                        Text(
                          'Added on ${DateFormat.yMMMd().format(task.earnedDate)}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: Checkbox(
                      value: false, // Not completed yet
                      onChanged: (value) {
                        // Mark as complete would go here
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
} 