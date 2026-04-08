import 'dart:convert';
import '../models/user_task.dart';
import '../data/datasources/local/prefs_manager.dart';
class TasksService {
  static const String _tasksKey = 'user_tasks';
  final PrefsManager _prefsManager;
  List<UserTask> _tasks = [];
  TasksService({PrefsManager? prefsManager})
      : _prefsManager = prefsManager ?? PrefsManager();
  Future<void> init() async {
    await _prefsManager.init();
    await _loadTasks();
  }
  List<UserTask> get tasks => List.unmodifiable(_tasks);
  List<UserTask> get pendingTasks =>
      _tasks.where((task) => !task.isCompleted).toList();
  List<UserTask> get completedTasks =>
      _tasks.where((task) => task.isCompleted).toList();
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
  Future<void> removeTask(String taskId) async {
    _tasks.removeWhere((task) => task.id == taskId);
    await _saveTasks();
  }
  bool isActionItemAlreadyAdded(String sessionId, String actionItemText) {
    return _tasks.any(
        (task) => task.sessionId == sessionId && task.text == actionItemText);
  }
  Future<void> removeTaskByActionItem(
      String sessionId, String actionItemText) async {
    _tasks.removeWhere(
        (task) => task.sessionId == sessionId && task.text == actionItemText);
    await _saveTasks();
  }
  Future<void> _loadTasks() async {
    try {
      final tasksJson = _prefsManager.getString(_tasksKey);
      if (tasksJson != null) {
        final List<dynamic> tasksList = jsonDecode(tasksJson);
        _tasks = tasksList
            .map((taskData) =>
                UserTask.fromJson(taskData as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      _tasks = [];
    }
  }
  Future<void> _saveTasks() async {
    try {
      final tasksJson =
          jsonEncode(_tasks.map((task) => task.toJson()).toList());
      await _prefsManager.setString(_tasksKey, tasksJson);
    } catch (e) {}
  }
}
