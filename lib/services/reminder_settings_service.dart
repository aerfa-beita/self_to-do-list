import 'dart:convert';

import '../database/database.dart';
import '../models/task.dart';

class TaskSnooze {
  const TaskSnooze({required this.until, required this.reminderSignature});

  final DateTime until;
  final String reminderSignature;

  Map<String, dynamic> toJson() => {
    'until': until.toIso8601String(),
    'reminder_signature': reminderSignature,
  };

  static TaskSnooze? tryParse(Object? value) {
    if (value is! Map) return null;
    final until = DateTime.tryParse(value['until']?.toString() ?? '');
    final signature = value['reminder_signature']?.toString();
    if (until == null || signature == null || signature.isEmpty) return null;
    return TaskSnooze(until: until, reminderSignature: signature);
  }

  static String signatureFor(Task task) => [
    task.dueDate?.toIso8601String() ?? '',
    task.reminderTime?.toIso8601String() ?? '',
    task.repeatType ?? '',
  ].join('|');
}

class ReminderSettings {
  static const allowedIntervals = <int>[30, 60, 120];
  static const defaultStartMinutes = 8 * 60;
  static const defaultEndMinutes = 22 * 60;

  const ReminderSettings({
    this.dailyReviewEnabled = false,
    this.intervalMinutes = 60,
    this.startMinutes = defaultStartMinutes,
    this.endMinutes = defaultEndMinutes,
  });

  final bool dailyReviewEnabled;
  final int intervalMinutes;
  final int startMinutes;
  final int endMinutes;

  ReminderSettings copyWith({
    bool? dailyReviewEnabled,
    int? intervalMinutes,
    int? startMinutes,
    int? endMinutes,
  }) {
    return ReminderSettings(
      dailyReviewEnabled: dailyReviewEnabled ?? this.dailyReviewEnabled,
      intervalMinutes: allowedIntervals.contains(intervalMinutes)
          ? intervalMinutes!
          : this.intervalMinutes,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
    ).normalized();
  }

  ReminderSettings normalized() {
    final safeInterval = allowedIntervals.contains(intervalMinutes)
        ? intervalMinutes
        : 60;
    final safeStart = startMinutes.clamp(0, 23 * 60 + 59).toInt();
    final safeEnd = endMinutes.clamp(1, 24 * 60 - 1).toInt();
    if (safeEnd <= safeStart) {
      return ReminderSettings(
        dailyReviewEnabled: dailyReviewEnabled,
        intervalMinutes: safeInterval,
      );
    }
    return ReminderSettings(
      dailyReviewEnabled: dailyReviewEnabled,
      intervalMinutes: safeInterval,
      startMinutes: safeStart,
      endMinutes: safeEnd,
    );
  }

  String formatMinutes(int value) {
    final hour = value ~/ 60;
    final minute = value % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  String get intervalLabel => switch (intervalMinutes) {
    30 => '30 分钟',
    120 => '2 小时',
    _ => '1 小时',
  };
}

class ReminderSettingsService {
  ReminderSettingsService(this._database);

  static const _enabledKey = 'daily_review_enabled';
  static const _intervalKey = 'daily_review_interval_minutes';
  static const _startKey = 'daily_review_start_minutes';
  static const _endKey = 'daily_review_end_minutes';
  static const _taskSnoozesKey = 'task_snoozes';

  final DatabaseProvider _database;

  Future<ReminderSettings> load() async {
    final values = await Future.wait([
      _database.getSetting(_enabledKey),
      _database.getSetting(_intervalKey),
      _database.getSetting(_startKey),
      _database.getSetting(_endKey),
    ]);
    return ReminderSettings(
      dailyReviewEnabled: values[0] == 'true',
      intervalMinutes: int.tryParse(values[1] ?? '') ?? 60,
      startMinutes:
          int.tryParse(values[2] ?? '') ?? ReminderSettings.defaultStartMinutes,
      endMinutes:
          int.tryParse(values[3] ?? '') ?? ReminderSettings.defaultEndMinutes,
    ).normalized();
  }

  Future<void> save(ReminderSettings settings) async {
    final value = settings.normalized();
    await Future.wait([
      _database.setSetting(
        _enabledKey,
        value.dailyReviewEnabled ? 'true' : 'false',
      ),
      _database.setSetting(_intervalKey, value.intervalMinutes.toString()),
      _database.setSetting(_startKey, value.startMinutes.toString()),
      _database.setSetting(_endKey, value.endMinutes.toString()),
    ]);
  }

  Future<Map<String, TaskSnooze>> loadTaskSnoozes() async {
    final raw = await _database.getSetting(_taskSnoozesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, TaskSnooze>{};
      for (final entry in decoded.entries) {
        final snooze = TaskSnooze.tryParse(entry.value);
        if (snooze != null) result[entry.key.toString()] = snooze;
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<void> saveTaskSnooze(Task task, DateTime until) async {
    final snoozes = await loadTaskSnoozes();
    snoozes[task.syncId] = TaskSnooze(
      until: until,
      reminderSignature: TaskSnooze.signatureFor(task),
    );
    await saveTaskSnoozes(snoozes);
  }

  Future<void> clearTaskSnooze(String taskSyncId) async {
    final snoozes = await loadTaskSnoozes();
    if (snoozes.remove(taskSyncId) != null) {
      await saveTaskSnoozes(snoozes);
    }
  }

  Future<void> saveTaskSnoozes(Map<String, TaskSnooze> snoozes) =>
      _database.setSetting(
        _taskSnoozesKey,
        jsonEncode(snoozes.map((key, value) => MapEntry(key, value.toJson()))),
      );
}
