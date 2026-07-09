import 'dart:async';
import 'dart:io' show Platform, Process, File;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Completer<void>? _initCompleter;
  final Map<int, Timer> _timers = {};

  /// Windows：Timer 触发后把通知数据放这里，UI 层读取并弹窗
  final ValueNotifier<List<({String title, String body})>> pendingNotification =
      ValueNotifier([]);

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
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(initSettings);
    } catch (_) {}

    if (Platform.isWindows) {
      final exeDir = Platform.resolvedExecutable;
      _toastScriptPath = '${exeDir.substring(0, exeDir.lastIndexOf('\\'))}\\data\\flutter_assets\\assets\\scripts\\show_toast.ps1';
    }

    _initialized = true;
    _initCompleter!.complete();
  }

  /// Windows：注册系统任务计划（app 关闭/重启后仍触发）
  Future<void> _schtasksCreate(int id, String title, String body, DateTime time) async {
    if (_toastScriptPath == null) return;
    // 检查脚本文件是否存在
    final scriptFile = File(_toastScriptPath!);
    if (!await scriptFile.exists()) {
      debugPrint('[schtasks] 脚本不存在: $_toastScriptPath');
      return;
    }
    final date = '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
    final hhmm = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final safeTitle = title.replaceAll('"', "'");
    final safeBody = body.replaceAll('"', "'");
    try {
      final psCmd = 'powershell -WindowStyle Hidden -File "$_toastScriptPath" -Title "$safeTitle" -Body "$safeBody"';
      final result = await Process.run('schtasks', [
        '/create', '/tn', 'TodoList_$id',
        '/tr', psCmd,
        '/sc', 'once', '/sd', date, '/st', hhmm, '/f',
      ]);
      if (result.exitCode != 0) {
        debugPrint('[schtasks] 创建失败 (exit ${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      debugPrint('[schtasks] 异常: $e');
    }
  }

  /// Windows：删除系统任务计划
  Future<void> _schtasksDelete(int id) async {
    try {
      await Process.run('schtasks', ['/delete', '/tn', 'TodoList_$id', '/f']);
    } catch (_) {}
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? repeatType,
  }) async {
    if (!_initialized) await init();

    await cancelReminder(id); // 先清旧任务

    // 重复提醒：如果时间已过，自动跳到下一轮
    if (scheduledTime.isBefore(DateTime.now())) {
      if (repeatType != null) {
        DateTime next = scheduledTime;
        while (next.isBefore(DateTime.now())) {
          switch (repeatType) {
            case 'daily': next = next.add(const Duration(days: 1)); break;
            case 'weekly': next = next.add(const Duration(days: 7)); break;
            case 'monthly': next = DateTime(next.year, next.month + 1, next.day, next.hour, next.minute); break;
            default: return;
          }
        }
        return scheduleReminder(id: id, title: title, body: body, scheduledTime: next, repeatType: repeatType);
      }
      return;
    }

    if (Platform.isWindows) {
      final delay = scheduledTime.difference(DateTime.now());
      if (delay.inMilliseconds <= 0) return;
      // 1. 注册系统任务（关机/关闭app后仍触发）
      await _schtasksCreate(id, title, body, scheduledTime);
      // 2. app内Timer（精确 + 处理重复逻辑）
      _timers[id] = Timer(delay, () {
        _timers.remove(id);
        // app内已处理通知，删除系统任务避免双弹
        _schtasksDelete(id);
        final list = List<({String title, String body})>.from(pendingNotification.value);
        list.add((title: title, body: body));
        pendingNotification.value = list;
        // 重复提醒
        if (repeatType != null) {
          DateTime next = scheduledTime;
          switch (repeatType) {
            case 'daily': next = scheduledTime.add(const Duration(days: 1)); break;
            case 'weekly': next = scheduledTime.add(const Duration(days: 7)); break;
            case 'monthly': next = DateTime(scheduledTime.year, scheduledTime.month + 1, scheduledTime.day, scheduledTime.hour, scheduledTime.minute); break;
          }
          if (next.isAfter(DateTime.now())) {
            scheduleReminder(id: id, title: title, body: body, scheduledTime: next, repeatType: repeatType);
          }
        }
      });
    } else {
      try {
        final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders', '提醒',
            channelDescription: '任务到期提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        );
        await _plugin.zonedSchedule(
          id, title, body, tzTime, details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
        );
      } catch (_) {}
    }
  }

  Future<void> cancelReminder(int id) async {
    _timers[id]?.cancel();
    _timers.remove(id);
    if (Platform.isWindows) {
      await _schtasksDelete(id);
    }
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  void dispose() {
    for (final t in _timers.values) { t.cancel(); }
    _timers.clear();
    _plugin.cancelAll();
  }
}
