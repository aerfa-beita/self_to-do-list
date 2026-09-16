import 'dart:async';
import 'dart:io' show Platform, Process, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

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

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Completer<void>? _initCompleter;
  final Map<int, Timer> _timers = {};
  final ValueNotifier<NotificationStatus> status = ValueNotifier(
    const NotificationStatus(NotificationPermissionState.unknown, '提醒权限尚未检查'),
  );

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
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(initSettings);
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

  /// Android：是否已加入电池优化白名单（小米等 ROM 后台拦截提醒时需要）
  /// flutter_local_notifications 18.x 无此 API，走原生 MethodChannel（MainActivity.kt）
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

  /// Android：弹系统框申请加入电池优化白名单（仅 Android，其他平台 no-op）
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _batteryChannel.invokeMethod<bool>('requestIgnore');
    } catch (error) {
      debugPrint('[notification] 电池优化授权失败: $error');
    }
  }

  /// Windows：注册系统任务计划（app 关闭/重启后仍触发）
  Future<void> _schtasksCreate(
    int id,
    String title,
    String body,
    DateTime time,
  ) async {
    if (_toastScriptPath == null) return;
    // 检查脚本文件是否存在
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

  Future<bool> scheduleReminder({
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
        );
      }
      return false;
    }

    if (Platform.isWindows) {
      final delay = scheduledTime.difference(DateTime.now());
      if (delay.inMilliseconds <= 0) return false;
      // 1. 注册系统任务（关机/关闭app后仍触发）
      await _schtasksCreate(id, title, body, scheduledTime);
      // 2. app内Timer（精确 + 处理重复逻辑）
      _timers[id] = Timer(delay, () {
        _timers.remove(id);
        // app内已处理通知，删除系统任务避免双弹
        _schtasksDelete(id);
        final list = List<({String title, String body})>.from(
          pendingNotification.value,
        );
        list.add((title: title, body: body));
        pendingNotification.value = list;
        // 重复提醒
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
            );
          }
        }
      });
      return true;
    } else {
      try {
        if (!await requestPermissions()) return false;
        final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            '提醒',
            channelDescription: '任务到期提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        );
        // 精确闹钟：Doze/后台下准点触发；无精确闹钟权限时降级非精确，不抛错
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
          tzTime,
          details,
          androidScheduleMode: canExact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.wallClockTime,
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
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _plugin.cancelAll();
  }
}
