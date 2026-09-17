import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';
import 'reminder_settings_service.dart';

enum NotificationPermissionState {
  unknown,
  granted,
  denied,
  unavailable,
  error,
}

class NotificationStatus {
  const NotificationStatus(this.state, this.message);

  final NotificationPermissionState state;
  final String message;

  bool get canNotify =>
      state == NotificationPermissionState.granted ||
      state == NotificationPermissionState.unavailable;
}

enum ReminderLaunchKind { task, dailyReview }

class ReminderLaunch {
  const ReminderLaunch({
    required this.kind,
    required this.notificationId,
    this.taskId,
    this.scheduledFor,
  });

  final ReminderLaunchKind kind;
  final int notificationId;
  final int? taskId;
  final DateTime? scheduledFor;

  String encode() => jsonEncode({
    'kind': kind == ReminderLaunchKind.task ? 'task' : 'daily_review',
    'notification_id': notificationId,
    'task_id': taskId,
    'scheduled_for': scheduledFor?.toIso8601String(),
  });

  static ReminderLaunch? tryParse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, dynamic>) return null;
      final kind = switch (value['kind']) {
        'task' => ReminderLaunchKind.task,
        'daily_review' => ReminderLaunchKind.dailyReview,
        _ => null,
      };
      final notificationId = (value['notification_id'] as num?)?.toInt();
      if (kind == null || notificationId == null) return null;
      return ReminderLaunch(
        kind: kind,
        notificationId: notificationId,
        taskId: (value['task_id'] as num?)?.toInt(),
        scheduledFor: DateTime.tryParse(
          value['scheduled_for'] as String? ?? '',
        ),
      );
    } on FormatException {
      return null;
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const _fullScreenIntentChannel = MethodChannel(
    'stride/full_screen_intent',
  );
  static const _taskReminderOffset = 10000;
  static const _fullScreenChannelId =
      'stride_full_screen_reminders_with_sound_v2';
  static const _fullScreenSound = RawResourceAndroidNotificationSound(
    'stride_reminder',
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Completer<void>? _initCompleter;
  final Map<int, Timer> _timers = {};
  final ValueNotifier<NotificationStatus> status = ValueNotifier(
    const NotificationStatus(NotificationPermissionState.unknown, '提醒权限尚未检查'),
  );

  /// Windows：Timer 触发后把通知数据放这里，UI 层读取并弹窗。
  final ValueNotifier<List<({String title, String body})>> pendingNotification =
      ValueNotifier([]);

  /// Android：全屏通知或通知点击后交给根页面展示对应提醒界面。
  final ValueNotifier<ReminderLaunch?> launchedReminder = ValueNotifier(null);

  String? _toastScriptPath;

  Future<void> init() async {
    if (_initialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    _initCompleter = Completer<void>();

    try {
      tz_data.initializeTimeZones();
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _acceptPayload(launchDetails?.notificationResponse?.payload);
      }
      await requestPermissions();
    } catch (error) {
      status.value = NotificationStatus(
        NotificationPermissionState.error,
        '提醒初始化失败：$error',
      );
      debugPrint('[notification] 初始化失败: $error');
    }

    if (Platform.isWindows) {
      final exeDir = Platform.resolvedExecutable;
      _toastScriptPath =
          '${exeDir.substring(0, exeDir.lastIndexOf('\\'))}\\data\\flutter_assets\\assets\\scripts\\show_toast.ps1';
    }

    _initialized = true;
    _initCompleter!.complete();
  }

  void _handleNotificationResponse(NotificationResponse response) {
    _acceptPayload(response.payload);
  }

  void _acceptPayload(String? payload) {
    final launch = ReminderLaunch.tryParse(payload);
    if (launch != null) launchedReminder.value = launch;
  }

  ReminderLaunch? consumeLaunchedReminder() {
    final value = launchedReminder.value;
    launchedReminder.value = null;
    return value;
  }

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      status.value = const NotificationStatus(
        NotificationPermissionState.unavailable,
        '当前平台不需要 Android 通知权限',
      );
      return true;
    }
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      final allowed = granted ?? true;
      status.value = NotificationStatus(
        allowed
            ? NotificationPermissionState.granted
            : NotificationPermissionState.denied,
        allowed ? '提醒权限已开启' : '通知权限未开启，请在系统设置中允许通知',
      );
      return allowed;
    } catch (error) {
      status.value = NotificationStatus(
        NotificationPermissionState.error,
        '提醒权限检查失败：$error',
      );
      debugPrint('[notification] 权限检查失败: $error');
      return false;
    }
  }

  static const _batteryChannel = MethodChannel(
    'todo_list/battery_optimization',
  );

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _batteryChannel.invokeMethod<bool>('isIgnoring') ?? true;
    } catch (error) {
      debugPrint('[notification] 电池优化检测失败: $error');
      return true;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _batteryChannel.invokeMethod<bool>('requestIgnore');
    } catch (error) {
      debugPrint('[notification] 电池优化授权失败: $error');
    }
  }

  Future<bool> canUseFullScreenIntent() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _fullScreenIntentChannel.invokeMethod<bool>('canUse') ??
          false;
    } catch (error) {
      debugPrint('[notification] 全屏提醒权限检测失败: $error');
      return false;
    }
  }

  Future<bool> requestFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestFullScreenIntentPermission() ?? false;
    } catch (error) {
      debugPrint('[notification] 全屏提醒权限申请失败: $error');
      return false;
    }
  }

  Future<void> _schtasksCreate(
    int id,
    String title,
    String body,
    DateTime time,
  ) async {
    if (_toastScriptPath == null) return;
    final scriptFile = File(_toastScriptPath!);
    if (!await scriptFile.exists()) {
      debugPrint('[schtasks] 脚本不存在: $_toastScriptPath');
      return;
    }
    final date =
        '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final safeTitle = title.replaceAll('"', "'");
    final safeBody = body.replaceAll('"', "'");
    try {
      final psCmd =
          'powershell -WindowStyle Hidden -File "$_toastScriptPath" -Title "$safeTitle" -Body "$safeBody"';
      final result = await Process.run('schtasks', [
        '/create',
        '/tn',
        'TodoList_$id',
        '/tr',
        psCmd,
        '/sc',
        'once',
        '/sd',
        date,
        '/st',
        hhmm,
        '/f',
      ]);
      if (result.exitCode != 0) {
        debugPrint(
          '[schtasks] 创建失败 (exit ${result.exitCode}): ${result.stderr}',
        );
      }
    } catch (error) {
      debugPrint('[schtasks] 异常: $error');
    }
  }

  Future<void> _schtasksDelete(int id) async {
    try {
      await Process.run('schtasks', ['/delete', '/tn', 'TodoList_$id', '/f']);
    } catch (_) {}
  }

  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? repeatType,
    bool fullScreen = false,
    int? taskId,
  }) async {
    if (!_initialized) await init();
    await cancelReminder(id);

    if (scheduledTime.isBefore(DateTime.now())) {
      if (repeatType != null) {
        DateTime next = scheduledTime;
        while (next.isBefore(DateTime.now())) {
          switch (repeatType) {
            case 'daily':
              next = next.add(const Duration(days: 1));
              break;
            case 'weekly':
              next = next.add(const Duration(days: 7));
              break;
            case 'monthly':
              next = DateTime(
                next.year,
                next.month + 1,
                next.day,
                next.hour,
                next.minute,
              );
              break;
            default:
              return false;
          }
        }
        return scheduleReminder(
          id: id,
          title: title,
          body: body,
          scheduledTime: next,
          repeatType: repeatType,
          fullScreen: fullScreen,
          taskId: taskId,
        );
      }
      return false;
    }

    if (Platform.isWindows) {
      final delay = scheduledTime.difference(DateTime.now());
      if (delay.inMilliseconds <= 0) return false;
      await _schtasksCreate(id, title, body, scheduledTime);
      _timers[id] = Timer(delay, () {
        _timers.remove(id);
        _schtasksDelete(id);
        final list = List<({String title, String body})>.from(
          pendingNotification.value,
        );
        list.add((title: title, body: body));
        pendingNotification.value = list;
        if (repeatType != null) {
          DateTime next = scheduledTime;
          switch (repeatType) {
            case 'daily':
              next = scheduledTime.add(const Duration(days: 1));
              break;
            case 'weekly':
              next = scheduledTime.add(const Duration(days: 7));
              break;
            case 'monthly':
              next = DateTime(
                scheduledTime.year,
                scheduledTime.month + 1,
                scheduledTime.day,
                scheduledTime.hour,
                scheduledTime.minute,
              );
              break;
          }
          if (next.isAfter(DateTime.now())) {
            scheduleReminder(
              id: id,
              title: title,
              body: body,
              scheduledTime: next,
              repeatType: repeatType,
              fullScreen: fullScreen,
              taskId: taskId,
            );
          }
        }
      });
      return true;
    }

    try {
      if (!await requestPermissions()) return false;
      final launch = fullScreen && taskId != null
          ? ReminderLaunch(
              kind: ReminderLaunchKind.task,
              notificationId: id,
              taskId: taskId,
              scheduledFor: scheduledTime,
            )
          : null;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          fullScreen ? _fullScreenChannelId : 'reminders',
          fullScreen ? '全屏任务提醒' : '提醒',
          channelDescription: fullScreen ? '任务到点与今日任务巡检' : '任务到期提醒',
          importance: fullScreen ? Importance.max : Importance.high,
          priority: Priority.high,
          category: fullScreen ? AndroidNotificationCategory.alarm : null,
          fullScreenIntent: fullScreen,
          visibility: fullScreen
              ? NotificationVisibility.public
              : NotificationVisibility.private,
          audioAttributesUsage: fullScreen
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          playSound: true,
          sound: fullScreen ? _fullScreenSound : null,
        ),
      );
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canExact =
          await androidImpl?.canScheduleExactNotifications() ?? true;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        androidScheduleMode: canExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        payload: launch?.encode(),
      );
      status.value = const NotificationStatus(
        NotificationPermissionState.granted,
        '提醒已安排',
      );
      return true;
    } catch (error) {
      status.value = NotificationStatus(
        NotificationPermissionState.error,
        '提醒安排失败：$error',
      );
      debugPrint('[notification] 安排提醒失败: $error');
      return false;
    }
  }

  Future<void> replaceManagedAndroidReminders({
    required List<Task> tasks,
    required ReminderSettings settings,
    Map<String, DateTime> snoozedUntilByTask = const {},
    int horizonDays = 8,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_initialized) await init();
    await _cancelManagedAndroidReminders();
    if (!await requestPermissions()) return;

    final now = DateTime.now();
    final active = tasks
        .where((task) => !task.isDeleted && !task.isCompleted)
        .toList(growable: false);

    for (final task in active) {
      final due = task.dueDate;
      final reminder = task.reminderTime;
      final taskId = task.id;
      if (taskId == null) continue;
      final snoozedUntil = snoozedUntilByTask[task.syncId];
      if (snoozedUntil != null) {
        await scheduleReminder(
          id: taskId + _taskReminderOffset,
          title: '任务时间到了',
          body: task.title,
          scheduledTime: snoozedUntil,
          fullScreen: true,
          taskId: taskId,
        );
        continue;
      }
      if (due == null || reminder == null) continue;
      await scheduleReminder(
        id: taskId + _taskReminderOffset,
        title: '任务时间到了',
        body: task.title,
        scheduledTime: DateTime(
          due.year,
          due.month,
          due.day,
          reminder.hour,
          reminder.minute,
        ),
        repeatType: task.repeatType,
        fullScreen: true,
        taskId: taskId,
      );
    }

    final normalized = settings.normalized();
    if (!normalized.dailyReviewEnabled) return;
    final firstDay = DateTime(now.year, now.month, now.day);
    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final day = firstDay.add(Duration(days: dayOffset));
      final dayTasks = active
          .where((task) => _sameDay(task.dueDate, day))
          .toList(growable: false);
      if (dayTasks.isEmpty) continue;
      final exactTaskTimes = dayTasks
          .where((task) => task.reminderTime != null)
          .map(
            (task) => DateTime(
              day.year,
              day.month,
              day.day,
              task.reminderTime!.hour,
              task.reminderTime!.minute,
            ),
          )
          .toList(growable: false);
      final times = _reviewTimesForDay(day, normalized);
      for (var slot = 0; slot < times.length; slot++) {
        final time = times[slot];
        if (!time.isAfter(now)) continue;
        final overlapsTask = exactTaskTimes.any(
          (taskTime) =>
              taskTime.difference(time).abs() < const Duration(minutes: 2),
        );
        if (overlapsTask) continue;
        await _scheduleDailyReview(
          id: _dailyReviewId(day, slot),
          scheduledTime: time,
          taskCount: dayTasks.length,
        );
      }
    }
  }

  Future<void> _cancelManagedAndroidReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (ReminderLaunch.tryParse(request.payload) != null) {
        await _plugin.cancel(request.id);
      }
    }
  }

  Future<void> _scheduleDailyReview({
    required int id,
    required DateTime scheduledTime,
    required int taskCount,
  }) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final canExact = await android?.canScheduleExactNotifications() ?? true;
    final launch = ReminderLaunch(
      kind: ReminderLaunchKind.dailyReview,
      notificationId: id,
      scheduledFor: scheduledTime,
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _fullScreenChannelId,
        '全屏任务提醒',
        channelDescription: '任务到点与今日任务巡检',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        playSound: true,
        sound: _fullScreenSound,
      ),
    );
    await _plugin.zonedSchedule(
      id,
      '今日任务巡检',
      '今天还有 $taskCount 件未完成任务',
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
      payload: launch.encode(),
    );
  }

  Future<bool> scheduleSnoozedTask(Task task, DateTime scheduledTime) {
    final taskId = task.id;
    if (taskId == null) return Future.value(false);
    return scheduleReminder(
      id: taskId + _taskReminderOffset,
      title: '任务时间到了',
      body: task.title,
      scheduledTime: scheduledTime,
      fullScreen: true,
      taskId: taskId,
    );
  }

  Future<void> cancelTaskReminder(int taskId) =>
      cancelReminder(taskId + _taskReminderOffset);

  static bool _sameDay(DateTime? value, DateTime day) =>
      value != null &&
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  static List<DateTime> _reviewTimesForDay(
    DateTime day,
    ReminderSettings settings,
  ) {
    final result = <DateTime>[];
    final base = DateTime(day.year, day.month, day.day);
    final end = base.add(Duration(minutes: settings.endMinutes));
    for (
      var value = base.add(Duration(minutes: settings.startMinutes));
      !value.isAfter(end);
      value = value.add(Duration(minutes: settings.intervalMinutes))
    ) {
      result.add(value);
    }
    return result;
  }

  static int _dailyReviewId(DateTime day, int slot) =>
      (day.year * 10000 + day.month * 100 + day.day) * 100 + slot;

  Future<void> cancelReminder(int id) async {
    _timers[id]?.cancel();
    _timers.remove(id);
    if (Platform.isWindows) await _schtasksDelete(id);
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _plugin.cancelAll();
  }
}
