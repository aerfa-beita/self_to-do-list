import 'dart:async';

import '../models/task.dart';
import 'notification_service.dart';
import 'reminder_settings_service.dart';
import 'task_service.dart';

class ReminderCoordinator {
  ReminderCoordinator(
    this._taskService,
    this._notificationService,
    this._settingsService,
  );

  static const scheduleHorizonDays = 8;

  final TaskService _taskService;
  final NotificationService _notificationService;
  final ReminderSettingsService _settingsService;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _refreshAgain = false;

  void scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 350), refreshNow);
  }

  Future<void> refreshNow() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final results = await Future.wait<Object>([
        _taskService.getActiveTasks(),
        _settingsService.load(),
        _settingsService.loadTaskSnoozes(),
      ]);
      final tasks = results[0] as List<Task>;
      final settings = results[1] as ReminderSettings;
      final storedSnoozes = results[2] as Map<String, TaskSnooze>;
      final activeSnoozes = validTaskSnoozesForTasks(
        tasks,
        storedSnoozes,
        now: DateTime.now(),
      );
      if (activeSnoozes.length != storedSnoozes.length) {
        await _settingsService.saveTaskSnoozes(activeSnoozes);
      }
      await _notificationService.replaceManagedAndroidReminders(
        tasks: tasks,
        settings: settings,
        snoozedUntilByTask: activeSnoozes.map(
          (key, value) => MapEntry(key, value.until),
        ),
        horizonDays: scheduleHorizonDays,
      );
    } finally {
      _refreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        scheduleRefresh();
      }
    }
  }

  static List<DateTime> reviewTimesForDay(
    DateTime day,
    ReminderSettings settings,
  ) {
    final value = settings.normalized();
    if (!value.dailyReviewEnabled) return const [];
    final start = DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: value.startMinutes));
    final end = DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: value.endMinutes));
    final result = <DateTime>[];
    for (
      var current = start;
      !current.isAfter(end);
      current = current.add(Duration(minutes: value.intervalMinutes))
    ) {
      result.add(current);
    }
    return result;
  }

  static List<Task> activeTasksForDay(List<Task> tasks, DateTime day) {
    return tasks.where((task) {
      final due = task.dueDate;
      return !task.isDeleted &&
          !task.isCompleted &&
          due != null &&
          due.year == day.year &&
          due.month == day.month &&
          due.day == day.day;
    }).toList();
  }

  static Map<String, TaskSnooze> validTaskSnoozesForTasks(
    List<Task> tasks,
    Map<String, TaskSnooze> snoozes, {
    required DateTime now,
  }) {
    final tasksBySyncId = {
      for (final task in tasks)
        if (!task.isDeleted && !task.isCompleted) task.syncId: task,
    };
    return {
      for (final entry in snoozes.entries)
        if (tasksBySyncId[entry.key] case final task?)
          if (entry.value.until.isAfter(now) &&
              entry.value.reminderSignature == TaskSnooze.signatureFor(task))
            entry.key: entry.value,
    };
  }

  Future<bool> snoozeTask(Task task, Duration delay) async {
    final until = DateTime.now().add(delay);
    await _settingsService.saveTaskSnooze(task, until);
    final scheduled = await _notificationService.scheduleSnoozedTask(
      task,
      until,
    );
    if (!scheduled) await _settingsService.clearTaskSnooze(task.syncId);
    return scheduled;
  }

  void dispose() {
    _refreshTimer?.cancel();
  }
}
