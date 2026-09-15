import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/repositories/category_repository.dart';
import 'package:todo_list/repositories/memo_category_repository.dart';
import 'package:todo_list/repositories/memo_repository.dart';
import 'package:todo_list/repositories/subtask_repository.dart';
import 'package:todo_list/repositories/task_memo_repository.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/screens/todo_screen.dart';
import 'package:todo_list/services/memo_service.dart';
import 'package:todo_list/services/notification_service.dart';
import 'package:todo_list/services/task_memo_service.dart';
import 'package:todo_list/services/task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 轮询等待：真实异步（SQLite/schtasks）跑在 runAsync 里，直到目标出现或超时
  Future<void> settle(
    WidgetTester tester,
    Finder until, {
    int tries = 40,
  }) async {
    for (var i = 0; i < tries; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (until.evaluate().isNotEmpty) return;
    }
  }

  Future<Database> makeDb() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    return DatabaseProvider().openAtPath(inMemoryDatabasePath);
  }

  Future<void> pumpScreen(WidgetTester tester, Database db) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final taskService = TaskService(
      TaskRepository(db),
      SubTaskRepository(db),
      CategoryRepository(db),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TodoScreen(
          taskService: taskService,
          notificationService: NotificationService(),
          taskMemoService: TaskMemoService(
            TaskRepository(db),
            TaskMemoRepository(db),
            SubTaskRepository(db),
            MemoService(MemoRepository(db), MemoCategoryRepository(db)),
          ),
        ),
      ),
    );
    await settle(tester, find.text('安排'));
  }

  testWidgets('completing an arranged task moves it to done section and '
      'unchecking restores it', (tester) async {
    final db = (await tester.runAsync(() async {
      final db = await makeDb();
      await TaskRepository(
        db,
      ).insert(Task(title: '安排任务A', taskMode: Task.planNowMode));
      return db;
    }))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);

    // 切到安排 > 阶段视图
    await tester.tap(find.text('安排').first);
    await tester.pump();
    expect(find.text('现在 · 1'), findsOneWidget);
    expect(find.byKey(const Key('arrangement-done')), findsNothing);

    // 勾选完成 → 从列消失、计入收件箱共用已完成
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester, find.text('现在 · 0'));
    expect(find.text('现在 · 0'), findsOneWidget);
    expect(find.text('已完成 · 1'), findsNothing);

    // 切回列表的收件箱，展开已完成后取消勾选
    await tester.tap(find.text('列表').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester, find.text('已完成'));
    await tester.tap(find.text('已完成'));
    await tester.pump();
    await settle(tester, find.text('安排任务A'));
    expect(find.text('安排任务A'), findsOneWidget);
    await tester.tap(find.byTooltip('已完成'));
    await tester.tap(find.text('安排').first);
    await settle(tester, find.text('现在 · 1'));
    expect(find.byKey(const Key('arrangement-done')), findsNothing);
    final restored = (await tester.runAsync(
      () async => (await TaskRepository(
        db,
      ).getActive()).firstWhere((t) => t.title == '安排任务A'),
    ))!;
    expect(restored.taskMode, Task.planNowMode);
    expect(restored.isCompleted, isFalse);
  });

  testWidgets('deleting an arranged task soft-deletes it with taskMode kept', (
    tester,
  ) async {
    final db = (await tester.runAsync(() async {
      final db = await makeDb();
      await TaskRepository(
        db,
      ).insert(Task(title: '待删除任务', taskMode: Task.planNextMode));
      return db;
    }))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);
    await tester.tap(find.text('安排').first);
    await tester.pump();
    expect(find.text('接下来 · 1'), findsOneWidget);

    // 行菜单 → 删除 → 确认
    await tester.tap(find.byTooltip('任务操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除任务'), findsOneWidget);
    // 精确点对话框内的删除按钮；先推完对话框退出动画（showDialog 的
    // Future 要等动画结束才返回，_softDelete 才会继续执行）
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pumpAndSettle();
    await settle(tester, find.text('接下来 · 0'));

    expect(find.text('待删除任务'), findsNothing);

    // 数据库里是软删除，taskMode 保留
    final deleted = (await tester.runAsync(
      () async => (await TaskRepository(
        db,
      ).getDeleted()).firstWhere((t) => t.title == '待删除任务'),
    ))!;
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.taskMode, Task.planNextMode);
  });

  testWidgets('stage footer quick add only asks for a title', (tester) async {
    final db = (await tester.runAsync(makeDb))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);
    await tester.tap(find.text('安排').first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('arrangement-add-plan_now')));
    await tester.pump();

    expect(find.text('添加到「现在」'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('日期'), findsNothing);
    expect(find.text('提醒'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('arrangement-quick-add-input')),
      '快速加入现在',
    );
    await tester.tap(find.byKey(const Key('arrangement-quick-add-submit')));
    await settle(tester, find.text('快速加入现在'));

    final saved = (await tester.runAsync(
      () async => (await TaskRepository(db).getActive()).single,
    ))!;
    expect(saved.taskMode, Task.planNowMode);
    expect(saved.dueDate, isNull);
  });

  testWidgets('smart views separate inbox, completed and recently deleted', (
    tester,
  ) async {
    final db = (await tester.runAsync(() async {
      final database = await makeDb();
      final repository = TaskRepository(database);
      await repository.insert(
        Task(
          title: '收件箱已完成',
          taskMode: Task.planNowMode,
          completedAt: DateTime.now(),
        ),
      );
      await repository.insert(
        Task(
          title: '收件箱最近删除',
          taskMode: Task.planLaterMode,
          deletedAt: DateTime.now(),
        ),
      );
      return database;
    }))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('最近删除'), findsOneWidget);
    expect(find.text('收件箱已完成'), findsNothing);
    expect(find.text('收件箱最近删除'), findsNothing);

    await tester.tap(find.text('已完成'));
    await settle(tester, find.text('收件箱已完成'));
    expect(find.text('收件箱已完成'), findsOneWidget);
    expect(find.text('收件箱最近删除'), findsNothing);

    await tester.tap(find.text('最近删除'));
    await settle(tester, find.text('收件箱最近删除'));
    expect(find.text('收件箱已完成'), findsNothing);
    expect(find.text('收件箱最近删除'), findsOneWidget);

    await tester.tap(find.text('安排').first);
    await tester.pump();
    expect(find.text('已完成'), findsNothing);
    expect(find.text('最近删除'), findsNothing);
    expect(find.text('收件箱已完成'), findsNothing);
    expect(find.text('收件箱最近删除'), findsNothing);
  });

  testWidgets('context menu moves a normal task to later stage and detail '
      'shows read-only stage chip', (tester) async {
    final db = (await tester.runAsync(() async {
      final db = await makeDb();
      await TaskRepository(
        db,
      ).insert(Task(title: '切换分组任务', taskMode: Task.normalMode));
      return db;
    }))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);
    expect(find.text('切换分组任务'), findsOneWidget);

    // 列表视图右键任务 → 菜单直接三选分组
    // 注：TodoScreen 的小精灵有循环动画，pumpAndSettle 永不静止，用定长 pump
    await tester.tap(find.text('切换分组任务'), buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('移到：现在'), findsOneWidget);
    expect(find.text('移到：接下来'), findsOneWidget);
    expect(find.text('移到：稍后'), findsOneWidget);

    await tester.tap(find.text('移到：稍后'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    final updated = (await tester.runAsync(
      () async => (await TaskRepository(
        db,
      ).getActive()).firstWhere((t) => t.title == '切换分组任务'),
    ))!;
    expect(updated.taskMode, Task.planLaterMode);

    // 切到安排 > 阶段视图：任务在"稍后"列
    await tester.tap(find.text('安排').first);
    await tester.pump();
    expect(find.text('稍后 · 1'), findsOneWidget);

    // 点任务进详情页：AppBar 只读分组 Chip 显示"稍后"
    await tester.tap(find.text('切换分组任务'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('稍后'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, find.text('稍后 · 1'));
  });
}
