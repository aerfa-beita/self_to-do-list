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
import 'package:todo_list/widgets/todo_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GlobalKey<TodoScreenState>? screenKey;

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
    screenKey = GlobalKey<TodoScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: TodoScreen(
          key: screenKey,
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
    await settle(tester, find.byKey(const Key('arrangement-week-list')));
    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.stage);
    await tester.pump();
    await settle(tester, find.byKey(const Key('arrangement-desktop')));
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

    expect(find.text('现在 · 1'), findsOneWidget);
    expect(find.byKey(const Key('arrangement-done')), findsNothing);

    // 勾选完成 → 从列消失、计入收件箱共用已完成
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester, find.text('现在 · 0'));
    expect(find.text('现在 · 0'), findsOneWidget);
    expect(find.text('已完成 · 1'), findsNothing);

    // 阶段已完成只出现在阶段来源的已完成视图
    await settle(tester, find.text('已完成'));
    await tester.tap(find.text('已完成'));
    await tester.pump();
    await settle(tester, find.text('安排任务A'));
    expect(find.text('安排任务A'), findsOneWidget);
    final completedItem = find.ancestor(
      of: find.text('安排任务A'),
      matching: find.byType(TaskItem),
    );
    tester.widget<TaskItem>(completedItem).onComplete?.call();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.stage);
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
    expect(find.text('接下来 · 1'), findsOneWidget);

    // 行菜单 → 删除 → 确认
    await tester.tap(find.byTooltip('任务操作').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    tester
        .widget<PopupMenuItem<String>>(
          find.byKey(const Key('arrangement-delete-action')),
        )
        .onTap
        ?.call();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('删除任务'), findsOneWidget);
    // 精确点对话框内的删除按钮；先推完对话框退出动画（showDialog 的
    // Future 要等动画结束才返回，_softDelete 才会继续执行）
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('删除')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester, find.text('接下来 · 0'));

    expect(find.text('待删除任务'), findsNothing);

    // 数据库里是软删除，taskMode 保留
    final deleted = (await tester.runAsync(
      () async => (await TaskRepository(
        db,
      ).getDeleted()).firstWhere((t) => t.title == '待删除任务'),
    ))!;
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.deletedScope, Task.actionScopeStage);
    expect(deleted.taskMode, Task.planNextMode);
  });

  testWidgets('stage footer quick add only asks for a title', (tester) async {
    final db = (await tester.runAsync(makeDb))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);
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
      await repository.insert(Task(title: '收件箱未完成'));
      await repository.insert(Task(title: '已安排未完成', dueDate: DateTime.now()));
      await repository.insert(
        Task(
          title: '收件箱已完成',
          completedAt: DateTime.now(),
          completedScope: Task.actionScopeInbox,
        ),
      );
      await repository.insert(
        Task(
          title: '收件箱最近删除',
          deletedAt: DateTime.now(),
          deletedScope: Task.actionScopeInbox,
        ),
      );
      await repository.insert(
        Task(
          title: '阶段已完成',
          taskMode: Task.planNowMode,
          completedAt: DateTime.now(),
          completedScope: Task.actionScopeStage,
        ),
      );
      await repository.insert(
        Task(
          title: '阶段最近删除',
          taskMode: Task.planNextMode,
          deletedAt: DateTime.now(),
          deletedScope: Task.actionScopeStage,
        ),
      );
      await repository.insert(
        Task(
          title: '本周已完成',
          dueDate: DateTime.now(),
          completedAt: DateTime.now(),
          completedScope: Task.actionScopeWeek,
        ),
      );
      await repository.insert(
        Task(
          title: '本周最近删除',
          dueDate: DateTime.now(),
          deletedAt: DateTime.now(),
          deletedScope: Task.actionScopeWeek,
        ),
      );
      return database;
    }))!;
    addTearDown(() => tester.runAsync(db.close));

    await pumpScreen(tester, db);
    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.inbox);
    await tester.pump();
    expect(find.text('收件箱未完成'), findsOneWidget);
    expect(find.text('已安排未完成'), findsNothing);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('最近删除'), findsOneWidget);
    expect(find.text('收件箱已完成'), findsNothing);
    expect(find.text('收件箱最近删除'), findsNothing);

    await tester.tap(find.text('已安排'));
    await settle(tester, find.text('已安排未完成'));
    expect(find.text('已安排未完成'), findsOneWidget);
    expect(find.text('收件箱未完成'), findsNothing);
    final arrangedCard = tester.widget<TaskItem>(
      find.ancestor(of: find.text('已安排未完成'), matching: find.byType(TaskItem)),
    );
    expect(arrangedCard.managementOnly, isTrue);

    await tester.tap(find.text('已完成'));
    await settle(tester, find.text('收件箱已完成'));
    expect(find.text('收件箱已完成'), findsOneWidget);
    expect(find.text('收件箱最近删除'), findsNothing);

    await tester.tap(find.text('最近删除'));
    await settle(tester, find.text('收件箱最近删除'));
    expect(find.text('收件箱已完成'), findsNothing);
    expect(find.text('收件箱最近删除'), findsOneWidget);

    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.stage);
    await tester.pump();
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('最近删除'), findsOneWidget);
    expect(find.text('收件箱已完成'), findsNothing);
    expect(find.text('收件箱最近删除'), findsNothing);

    await tester.tap(find.text('已完成'));
    await settle(tester, find.text('阶段已完成'));
    expect(find.text('阶段已完成'), findsOneWidget);
    expect(find.text('本周已完成'), findsNothing);
    expect(find.text('收件箱已完成'), findsNothing);

    await tester.tap(find.text('最近删除'));
    await settle(tester, find.text('阶段最近删除'));
    expect(find.text('阶段最近删除'), findsOneWidget);
    expect(find.text('本周最近删除'), findsNothing);

    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.week);
    await tester.pump();
    await tester.tap(find.text('已完成'));
    await settle(tester, find.text('本周已完成'));
    expect(find.text('本周已完成'), findsOneWidget);
    expect(find.text('阶段已完成'), findsNothing);

    await tester.tap(find.text('最近删除'));
    await settle(tester, find.text('本周最近删除'));
    expect(find.text('本周最近删除'), findsOneWidget);
    expect(find.text('阶段最近删除'), findsNothing);
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
    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.inbox);
    await tester.pump();
    expect(find.text('切换分组任务'), findsOneWidget);

    // 收件箱右键任务 → 移到阶段 → 稍后
    // 注：TodoScreen 的小精灵有循环动画，pumpAndSettle 永不静止，用定长 pump
    await tester.tap(find.text('切换分组任务'), buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('移到阶段'), findsOneWidget);
    expect(find.text('移到本周'), findsOneWidget);
    await tester.tap(find.text('移到阶段'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('稍后'));
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

    // 切到阶段：任务在“稍后”列
    screenKey!.currentState!.setPrimaryPage(TodoPrimaryPage.stage);
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
