import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/models/sub_task.dart';
import 'package:todo_list/repositories/category_repository.dart';
import 'package:todo_list/repositories/subtask_repository.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/screens/full_screen_reminder_screen.dart';
import 'package:todo_list/screens/reminder_settings_screen.dart';
import 'package:todo_list/services/notification_service.dart';
import 'package:todo_list/services/reminder_coordinator.dart';
import 'package:todo_list/services/reminder_settings_service.dart';
import 'package:todo_list/services/task_service.dart';

Future<void> _loadVisualFonts() async {
  final fontBytes = File('assets/fonts/msyh.ttc').readAsBytesSync();
  await (FontLoader(
    'Microsoft YaHei',
  )..addFont(Future.value(ByteData.sublistView(fontBytes)))).load();
  final separator = Platform.pathSeparator;
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  File? iconFont;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File(
      '${flutterRoot.path}${separator}bin${separator}cache${separator}artifacts'
      '${separator}material_fonts${separator}MaterialIcons-Regular.otf',
    );
    if (candidate.existsSync()) {
      iconFont = candidate;
      break;
    }
    flutterRoot = flutterRoot.parent;
  }
  if (iconFont == null) fail('Cannot locate MaterialIcons-Regular.otf');
  final iconBytes = iconFont.readAsBytesSync();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
}

Future<void> _settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reminder payload round-trips task and daily review launches', () {
    final scheduled = DateTime(2026, 9, 17, 9, 30);
    final task = ReminderLaunch(
      kind: ReminderLaunchKind.task,
      notificationId: 10042,
      taskId: 42,
      scheduledFor: scheduled,
    );
    final decodedTask = ReminderLaunch.tryParse(task.encode());
    expect(decodedTask?.kind, ReminderLaunchKind.task);
    expect(decodedTask?.taskId, 42);
    expect(decodedTask?.scheduledFor, scheduled);

    const daily = ReminderLaunch(
      kind: ReminderLaunchKind.dailyReview,
      notificationId: 70001,
    );
    expect(
      ReminderLaunch.tryParse(daily.encode())?.kind,
      ReminderLaunchKind.dailyReview,
    );
    expect(ReminderLaunch.tryParse('not-json'), isNull);
  });

  test('daily review intervals stay inside the configured active window', () {
    final day = DateTime(2026, 9, 17);
    final hourly = ReminderCoordinator.reviewTimesForDay(
      day,
      const ReminderSettings(dailyReviewEnabled: true),
    );
    expect(hourly.length, 15);
    expect(hourly.first, DateTime(2026, 9, 17, 8));
    expect(hourly.last, DateTime(2026, 9, 17, 22));

    final halfHourly = ReminderCoordinator.reviewTimesForDay(
      day,
      const ReminderSettings(
        dailyReviewEnabled: true,
        intervalMinutes: 30,
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      ),
    );
    expect(halfHourly, [
      DateTime(2026, 9, 17, 9),
      DateTime(2026, 9, 17, 9, 30),
      DateTime(2026, 9, 17, 10),
    ]);
  });

  test('daily review includes only unfinished tasks due on that day', () {
    final day = DateTime(2026, 9, 17);
    final tasks = [
      Task(id: 1, title: '今天', dueDate: day),
      Task(id: 2, title: '已完成', dueDate: day, completedAt: day),
      Task(id: 3, title: '明天', dueDate: day.add(const Duration(days: 1))),
      Task(id: 4, title: '收件箱'),
    ];
    expect(
      ReminderCoordinator.activeTasksForDay(tasks, day).map((task) => task.id),
      [1],
    );
  });

  test('task snooze persists and invalidates after reminder changes', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
    addTearDown(db.close);
    final service = ReminderSettingsService(DatabaseProvider());
    final now = DateTime(2026, 9, 17, 9, 30);
    final task = Task(
      id: 7,
      syncId: 'task-snooze-test',
      title: '准备周会演示文稿',
      dueDate: DateTime(2026, 9, 17),
      reminderTime: now,
    );
    final until = now.add(const Duration(minutes: 10));

    await service.saveTaskSnooze(task, until);
    final stored = await service.loadTaskSnoozes();
    expect(stored[task.syncId]?.until, until);
    expect(
      ReminderCoordinator.validTaskSnoozesForTasks(
        [task],
        stored,
        now: now,
      ).keys,
      [task.syncId],
    );

    final edited = task.copyWith(
      reminderTime: now.add(const Duration(hours: 1)),
    );
    expect(
      ReminderCoordinator.validTaskSnoozesForTasks([edited], stored, now: now),
      isEmpty,
    );
    expect(
      ReminderCoordinator.validTaskSnoozesForTasks([task], stored, now: until),
      isEmpty,
    );
  });

  test('Android reminder ringtone is a valid bundled wave resource', () {
    final bytes = File(
      'android/app/src/main/res/raw/stride_reminder.wav',
    ).readAsBytesSync();
    expect(bytes.length, greaterThan(44));
    expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
    expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
  });

  testWidgets('task and daily full-screen reminders fit a mobile viewport', (
    tester,
  ) async {
    await _loadVisualFonts();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late Database db;
    late Task task;
    late TaskService taskService;
    late ReminderSettingsService settingsService;
    final today = DateTime.now();
    await tester.runAsync(() async {
      db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      final repository = TaskRepository(db);
      final id = await repository.insert(
        Task(
          title: '准备周会演示文稿',
          note: '补齐第 3 页数据结论',
          category: '工作',
          taskMode: Task.planNowMode,
          dueDate: DateTime(today.year, today.month, today.day),
          reminderTime: DateTime(2026, 9, 17, 9, 30),
        ),
      );
      task = (await repository.getById(id))!;
      taskService = TaskService(
        repository,
        SubTaskRepository(db),
        CategoryRepository(db),
      );
      await taskService.insertSubTask(
        SubTask(taskId: id, title: '整理数据结论', isDone: true),
      );
      await taskService.insertSubTask(SubTask(taskId: id, title: '补齐演示图表'));
      await repository.insert(
        Task(
          title: '阅读行业周报',
          category: '学习',
          dueDate: DateTime(today.year, today.month, today.day),
        ),
      );
      await repository.insert(
        Task(
          title: '取快递',
          category: '生活',
          dueDate: DateTime(today.year, today.month, today.day),
          reminderTime: DateTime(2026, 9, 17, 18),
        ),
      );
      await repository.insert(
        Task(
          title: '清理收件箱',
          dueDate: DateTime(today.year, today.month, today.day),
        ),
      );
      settingsService = ReminderSettingsService(DatabaseProvider());
      await settingsService.save(
        const ReminderSettings(dailyReviewEnabled: true, intervalMinutes: 60),
      );
    });
    addTearDown(() => tester.runAsync(db.close));
    final coordinator = ReminderCoordinator(
      taskService,
      NotificationService(),
      settingsService,
    );
    addTearDown(coordinator.dispose);

    Widget build(ReminderLaunch launch) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
      ),
      home: FullScreenReminderScreen(
        key: ValueKey(launch.kind),
        launch: launch,
        taskService: taskService,
        notificationService: NotificationService(),
        reminderCoordinator: coordinator,
        settingsService: settingsService,
        onOpenToday: () {},
      ),
    );

    await tester.pumpWidget(
      build(
        ReminderLaunch(
          kind: ReminderLaunchKind.task,
          notificationId: 10000 + task.id!,
          taskId: task.id,
          scheduledFor: DateTime(today.year, today.month, today.day, 9, 30),
        ),
      ),
    );
    await _settleUntil(tester, find.text('完成任务'));
    expect(find.text('准备周会演示文稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FullScreenReminderScreen),
      matchesGoldenFile('goldens/full_screen_task_mobile.png'),
    );

    await tester.pumpWidget(
      build(
        ReminderLaunch(
          kind: ReminderLaunchKind.dailyReview,
          notificationId: 70001,
          scheduledFor: DateTime(today.year, today.month, today.day, 10),
        ),
      ),
    );
    await _settleUntil(tester, find.text('打开今日安排'));
    expect(find.text('今天还有'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(FullScreenReminderScreen),
      matchesGoldenFile('goldens/full_screen_daily_mobile.png'),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
        ),
        home: ReminderSettingsScreen(
          settingsService: settingsService,
          notificationService: NotificationService(),
          reminderCoordinator: coordinator,
          androidPlatform: true,
        ),
      ),
    );
    await _settleUntil(tester, find.text('提醒间隔'));
    expect(find.text('定时提醒今日未完成任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(ReminderSettingsScreen),
      matchesGoldenFile('goldens/reminder_settings_mobile.png'),
    );
  });
}
