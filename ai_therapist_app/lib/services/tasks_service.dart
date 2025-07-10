import 'dart:convert';
import '../models/user_task.dart';
import '../data/datasources/local/prefs_manager.dart';

class TasksService {
  static const String _tasksKey = 'user_tasks';
  
  final PrefsManager _prefsManager;
  List<UserTask> _tasks = [];

  TasksService({PrefsManager? prefsManager}) 
      : _prefsManager = prefsManager ?? PrefsManager();

  // Initialize the service
  Future<void> init() async {
    await _prefsManager.init();
    await _loadTasks();
  }

  // Get all tasks
  List<UserTask> get tasks => List.unmodifiable(_tasks);

  // Get pending tasks only
  List<UserTask> get pendingTasks => _tasks.where((task) => !task.isCompleted).toList();

  // Get completed tasks only
  List<UserTask> get completedTasks => _tasks.where((task) => task.isCompleted).toList();

  // Add a new task
  Future<void> addTask(String text, String sessionId) async {
    final task = UserTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      sessionId: sessionId,
      dateAdded: DateTime.now(),
    );
    
    _tasks.add(task);
    await _saveTasks();
  }

  // Mark a task as completed
  Future<void> completeTask(String taskId) async {
    final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex != -1) {
      _tasks[taskIndex] = _tasks[taskIndex].copyWith(
        isCompleted: true,
        completedDate: DateTime.now(),
      );
      await _saveTasks();
    }
  }

  // Mark a task as not completed (un-complete)
  Future<void> uncompleteTask(String taskId) async {
    final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex != -1) {
      _tasks[taskIndex] = _tasks[taskIndex].copyWith(
        isCompleted: false,
        completedDate: null,
      );
      await _saveTasks();
    }
  }

  // Remove a task
  Future<void> removeTask(String taskId) async {
    _tasks.removeWhere((task) => task.id == taskId);
    await _saveTasks();
  }

  // Check if a specific action item from a session is already added as a task
  bool isActionItemAlreadyAdded(String sessionId, String actionItemText) {
    return _tasks.any((task) => 
        task.sessionId == sessionId && task.text == actionItemText);
  }

  // Remove a task by action item text and session ID
  Future<void> removeTaskByActionItem(String sessionId, String actionItemText) async {
    _tasks.removeWhere((task) => 
        task.sessionId == sessionId && task.text == actionItemText);
    await _saveTasks();
  }

  // Load tasks from storage
  Future<void> _loadTasks() async {
    try {
      final tasksJson = _prefsManager.getString(_tasksKey);
      if (tasksJson != null) {
        final List<dynamic> tasksList = jsonDecode(tasksJson);
        _tasks = tasksList
            .map((taskData) => UserTask.fromJson(taskData as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('Error loading tasks: $e');
      _tasks = [];
    }
  }

  // Save tasks to storage
  Future<void> _saveTasks() async {
    try {
      final tasksJson = jsonEncode(_tasks.map((task) => task.toJson()).toList());
      await _prefsManager.setString(_tasksKey, tasksJson);
    } catch (e) {
      print('Error saving tasks: $e');
    }
  }
}