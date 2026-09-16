import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/models/sub_task.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/screens/flow_screen.dart';
import 'package:todo_list/services/task_service.dart';
import 'package:todo_list/repositories/category_repository.dart';
import 'package:todo_list/repositories/subtask_repository.dart';
import 'package:todo_list/widgets/todo_item.dart';

Task _task(
  int id,
  String title, {
  String mode = Task.planNowMode,
  String category = '默认',
  DateTime? completedAt,
  DateTime? dueDate,
  int? sortOrder,
  int? weekSortOrder,
}) {
  return Task(
    id: id,
    title: title,
    taskMode: mode,
    category: category,
    completedAt: completedAt,
    dueDate: dueDate,
    sortOrder: sortOrder ?? 0,
    weekSortOrder: weekSortOrder,
  );
}

Widget _arrangementSubject({
  required Size size,
  double textScale = 1,
  List<Task> now = const [],
  List<Task> next = const [],
  List<Task> later = const [],
  Set<String> collapsed = const {},
  ValueChanged<Set<String>>? onCollapsed,
  List<Task> allUndone = const [],
  List<Task>? allTasks,
  DateTime? today,
  ValueChanged<DateTime>? onAddWeekly,
  ReorderWeeklyTasks? onReorderWeekDay,
  MoveWeeklyTask? onMoveToWeekDay,
  ValueChanged<Task>? onSyncStage,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: TaskArrangementView(
          nowTasks: now,
          nextTasks: next,
          laterTasks: later,
          doneNowTasks: const [],
          doneNextTasks: const [],
          doneLaterTasks: const [],
          unplannedTasks: const [],
          collapsedModes: collapsed,
          onCollapsedModesChanged: onCollapsed,
          onToggleTask: (_) {},
          onOpenTask: (_) {},
          onMoveTask: (_, _) async {},
          onEditTask: (_) {},
          onDeleteTask: (_) {},
          onAddTask: (_) async {},
          allUndoneTasks: allUndone,
          allTasks: allTasks,
          today: today,
          onAddWeeklyTask: onAddWeekly == null
              ? null
              : (date) async => onAddWeekly(date),
          onReorder: (_, _, _) async {},
          onReorderWeekDay: onReorderWeekDay,
          onMoveToWeekDay: onMoveToWeekDay,
          onSyncStage: onSyncStage,
        ),
      ),
    ),
  );
}

Future<Database> _makeDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return DatabaseProvider().openAtPath(inMemoryDatabasePath);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile arrangement stages collapse independently', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Set<String>? saved;
    await tester.pumpWidget(
      _arrangementSubject(
        size: const Size(390, 800),
        now: [_task(1, '现在任务')],
        next: [_task(2, '接下来任务', mode: Task.planNextMode)],
        later: [_task(3, '稍后任务', mode: Task.planLaterMode)],
        onCollapsed: (modes) => saved = modes,
      ),
    );

    expect(find.text('现在任务'), findsOneWidget);
    await tester.tap(find.text('现在 · 1'));
    await tester.pump();
    expect(find.text('现在任务'), findsNothing);
    expect(find.text('同时任务'), findsNWidgets(2));
    expect(find.byKey(const Key('arrangement-add-plan_now')), findsNothing);
    expect(find.byKey(const Key('arrangement-add-plan_next')), findsOneWidget);
    expect(find.byKey(const Key('arrangement-add-plan_later')), findsOneWidget);
    expect(saved, contains(Task.planNowMode));

    await tester.tap(find.text('现在 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('现在任务'), findsOneWidget);
  });

  testWidgets('mobile arrangement has all collapse and expand controls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _arrangementSubject(
        size: const Size(412, 915),
        now: [_task(1, '现在任务')],
        next: [_task(2, '接下来任务', mode: Task.planNextMode)],
        later: [_task(3, '稍后任务', mode: Task.planLaterMode)],
      ),
    );

    expect(find.text('全部收起'), findsOneWidget);
    await tester.tap(find.byKey(const Key('arrangement-toggle-all')));
    await tester.pump();
    expect(find.text('全部展开'), findsOneWidget);
    expect(find.text('现在任务'), findsNothing);
    expect(find.text('接下来任务'), findsNothing);
    expect(find.text('稍后任务'), findsNothing);
    expect(find.text('同时任务'), findsNothing);

    await tester.tap(find.byKey(const Key('arrangement-toggle-all')));
    await tester.pumpAndSettle();
    expect(find.text('全部收起'), findsOneWidget);
    expect(find.text('现在任务'), findsOneWidget);
    expect(find.text('接下来任务'), findsOneWidget);
    expect(find.text('稍后任务'), findsOneWidget);
  });

  testWidgets('desktop ignores mobile collapse state and control', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _arrangementSubject(
        size: const Size(1200, 800),
        collapsed: Task.arrangementModes.toSet(),
        now: [_task(1, '现在任务')],
      ),
    );

    expect(find.byKey(const Key('arrangement-toggle-all')), findsNothing);
    expect(find.text('现在任务'), findsOneWidget);
    expect(find.byKey(const Key('arrangement-desktop')), findsOneWidget);
  });

  testWidgets(
    'compact task card keeps subtasks collapsed and exposes a handle',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(size: Size(360, 800)),
              child: TaskItem(
                task: _task(1, '一个足够长的任务标题，用来验证移动端最多两行显示'),
                doneCount: 1,
                totalCount: 2,
                onTap: () {},
                onDelete: () {},
                onEdit: () {},
                onComplete: () {},
                reorderable: true,
                reorderIndex: 0,
                isExpanded: true,
                subTasks: [SubTask(taskId: 1, title: '不应在卡片中出现')],
              ),
            ),
          ),
        ),
      );

      expect(find.text('子任务 1/2'), findsOneWidget);
      expect(find.text('不应在卡片中出现'), findsNothing);
      expect(find.byType(ReorderableDelayedDragStartListener), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byKey(const Key('task-more-1')), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(
        tester.widget<Dismissible>(find.byType(Dismissible)).direction,
        DismissDirection.endToStart,
      );
      expect(find.byIcon(Icons.expand_less), findsNothing);
    },
  );

  testWidgets('mobile arrangement fits 320dp with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _arrangementSubject(
        size: const Size(320, 800),
        textScale: 1.3,
        today: DateTime(2026, 9, 16),
        now: [_task(1, '一个很长很长的现在任务标题')],
        next: [_task(2, '接下来任务', mode: Task.planNextMode)],
        later: [_task(3, '稍后任务', mode: Task.planLaterMode)],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('全部收起'), findsOneWidget);
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('week-adjust-dates')), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('今天 · 0'), findsNothing);
  });

  testWidgets(
    'week view always shows Monday through Sunday and expands empty days',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final today = DateTime(2026, 9, 16);
      final mondayTask = _task(1, '周一任务', dueDate: DateTime(2026, 9, 14));
      final todayTask = _task(2, '今天任务', dueDate: today);
      DateTime? addDate;
      Task? stageSynced;
      await tester.pumpWidget(
        _arrangementSubject(
          size: const Size(390, 800),
          today: today,
          allUndone: [mondayTask, todayTask],
          onAddWeekly: (date) => addDate = date,
          onSyncStage: (task) => stageSynced = task,
        ),
      );

      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(find.text('周一 9月14日'), findsOneWidget);
      expect(find.text('周三 9月16日'), findsOneWidget);
      expect(find.text('今天 · 1'), findsOneWidget);
      expect(
        find.byKey(const Key('arrangement-compact-summary')),
        findsOneWidget,
      );
      expect(find.text('本周待办'), findsOneWidget);
      expect(find.byTooltip('任务操作'), findsNWidgets(2));
      expect(find.text('周二 9月15日'), findsOneWidget);
      expect(find.text('周四 9月17日'), findsOneWidget);
      expect(find.text('周五 9月18日'), findsOneWidget);
      expect(find.text('周六 9月19日'), findsOneWidget);
      expect(find.textContaining('其余'), findsNothing);
      expect(find.text('周二 9月15日 · 0'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('arrangement-menu-1')));
      await tester.pumpAndSettle();
      expect(find.text('同步阶段'), findsOneWidget);
      expect(find.text('同步今日'), findsNothing);
      await tester.tap(find.text('同步阶段'));
      await tester.pumpAndSettle();
      expect(stageSynced?.id, 1);

      await tester.tap(find.text('周三 9月16日'));
      await tester.pumpAndSettle();
      expect(find.text('今天任务'), findsNothing);
      expect(find.byKey(const Key('week-add-3')), findsNothing);
      await tester.tap(find.text('周三 9月16日'));
      await tester.pumpAndSettle();
      expect(find.text('今天任务'), findsOneWidget);

      await tester.tap(find.text('周二 9月15日'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加到周二'));
      expect(addDate, DateTime(2026, 9, 15));

      await tester.drag(
        find.byKey(const Key('arrangement-week-list')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      expect(find.text('周日 9月20日'), findsOneWidget);
    },
  );

  testWidgets('week hides today completion and keeps past completion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final today = DateTime(2026, 9, 16);
    final tasks = [
      _task(1, '今天未完成', dueDate: today),
      _task(2, '今天已完成', dueDate: today, completedAt: today),
      _task(3, '昨天未完成', dueDate: DateTime(2026, 9, 15)),
      _task(
        4,
        '昨天已完成',
        dueDate: DateTime(2026, 9, 15),
        completedAt: DateTime(2026, 9, 15, 20),
      ),
    ];
    await tester.pumpWidget(
      _arrangementSubject(
        size: const Size(390, 800),
        today: today,
        allUndone: tasks.where((task) => !task.isCompleted).toList(),
        allTasks: tasks,
      ),
    );

    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.text('周三 9月16日'), findsOneWidget);
    expect(find.text('今天 · 1'), findsOneWidget);
    expect(find.text('周二 9月15日'), findsOneWidget);
    expect(find.text('1 待办'), findsOneWidget);
    expect(find.text('今天未完成'), findsOneWidget);
    expect(find.text('今天已完成'), findsNothing);
    expect(find.text('昨天未完成'), findsOneWidget);
    expect(find.text('昨天已完成'), findsOneWidget);
  });

  testWidgets('past day with no unfinished task starts collapsed', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final today = DateTime(2026, 9, 16);
    final completedMonday = _task(
      1,
      '周一已完成',
      dueDate: DateTime(2026, 9, 14),
      completedAt: DateTime(2026, 9, 14, 20),
    );
    await tester.pumpWidget(
      _arrangementSubject(
        size: const Size(390, 800),
        today: today,
        allTasks: [completedMonday],
      ),
    );

    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.text('周一 9月14日'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('周一已完成'), findsNothing);

    await tester.tap(find.text('周一 9月14日'));
    await tester.pumpAndSettle();
    expect(find.text('周一已完成'), findsOneWidget);
  });

  test('settings keep only valid arrangement modes', () async {
    final db = await _makeDb();
    addTearDown(db.close);
    final repository = TaskRepository(db);

    await repository.setArrangementCollapsedModes({
      Task.planLaterMode,
      'invalid',
    });
    expect(await repository.getArrangementCollapsedModes(), {
      Task.planLaterMode,
    });

    await db.insert('settings', {
      'key': TaskRepository.arrangementCollapsedModesKey,
      'value': jsonEncode([Task.planNowMode, 'bad']),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    expect(await repository.getArrangementCollapsedModes(), {Task.planNowMode});

    await db.insert('settings', {
      'key': TaskRepository.arrangementCollapsedModesKey,
      'value': '{broken',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    expect(await repository.getArrangementCollapsedModes(), isEmpty);
  });

  test(
    'arranged completed tasks remain after seven days with subtasks',
    () async {
      final db = await _makeDb();
      addTearDown(db.close);
      final repository = TaskRepository(db);
      final subtaskRepository = SubTaskRepository(db);
      final now = DateTime(2026, 8, 31, 12);
      final expiredId = await repository.insert(
        _task(0, '七天前完成', completedAt: now.subtract(const Duration(days: 8))),
      );
      await subtaskRepository.insert(
        SubTask(taskId: expiredId, title: '需要一起删除', level: 0),
      );
      final recentId = await repository.insert(
        _task(0, '七天内完成', completedAt: now.subtract(const Duration(days: 6))),
      );
      final normalId = await repository.insert(
        _task(
          0,
          '普通列表完成',
          mode: Task.normalMode,
          completedAt: now.subtract(const Duration(days: 8)),
        ),
      );

      expect(await repository.getById(expiredId), isNotNull);
      expect(await subtaskRepository.getRoots(expiredId), hasLength(1));
      expect(await repository.getById(recentId), isNotNull);
      expect(await repository.getById(normalId), isNotNull);
    },
  );

  test(
    'reorder active subset preserves hidden positions and metadata',
    () async {
      final db = await _makeDb();
      addTearDown(db.close);
      final repository = TaskRepository(db);
      final firstId = await repository.insert(_task(0, '可见A'));
      final hiddenId = await repository.insert(
        _task(0, '隐藏分类', category: '工作'),
      );
      final secondId = await repository.insert(_task(0, '可见B'));
      final doneId = await repository.insert(
        _task(0, '隐藏完成', completedAt: DateTime.now()),
      );
      final before = await repository.getActive();
      final hiddenBefore = before.firstWhere((task) => task.id == hiddenId);
      final doneBefore = before.firstWhere((task) => task.id == doneId);

      await repository.reorderActiveSubset([secondId, firstId]);

      final after = await repository.getActive();
      expect(after.map((task) => task.title).toList(), [
        '可见B',
        '隐藏分类',
        '可见A',
        '隐藏完成',
      ]);
      final hiddenAfter = after.firstWhere((task) => task.id == hiddenId);
      final doneAfter = after.firstWhere((task) => task.id == doneId);
      expect(hiddenAfter.revision, hiddenBefore.revision);
      expect(doneAfter.revision, doneBefore.revision);
      expect(after.firstWhere((task) => task.id == firstId).revision, 2);
      expect(after.firstWhere((task) => task.id == secondId).revision, 2);
      expect(
        after.firstWhere((task) => task.id == firstId).updatedAt,
        isNot(before.firstWhere((task) => task.id == firstId).updatedAt),
      );
    },
  );

  test(
    'week ordering is independent and moving a task only changes its date',
    () async {
      final db = await _makeDb();
      addTearDown(db.close);
      final repository = TaskRepository(db);
      final monday = DateTime(2026, 9, 14);
      final tuesday = DateTime(2026, 9, 15);
      final firstId = await repository.insert(
        _task(0, '周内A', dueDate: monday, sortOrder: 10, weekSortOrder: 0),
      );
      final secondId = await repository.insert(
        _task(0, '周内B', dueDate: monday, sortOrder: 20, weekSortOrder: 1),
      );
      final beforeOrder = await repository.getActive();
      final firstListOrder = beforeOrder
          .firstWhere((task) => task.id == firstId)
          .sortOrder;
      final secondListOrder = beforeOrder
          .firstWhere((task) => task.id == secondId)
          .sortOrder;

      await repository.reorderWeekDay(monday, [secondId, firstId]);
      var tasks = await repository.getActive();
      final firstAfterOrder = tasks.firstWhere((task) => task.id == firstId);
      final secondAfterOrder = tasks.firstWhere((task) => task.id == secondId);
      expect(firstAfterOrder.sortOrder, firstListOrder);
      expect(secondAfterOrder.sortOrder, secondListOrder);
      expect(firstAfterOrder.weekSortOrder, 1);
      expect(secondAfterOrder.weekSortOrder, 0);

      await repository.moveToWeekDay(secondAfterOrder, tuesday);
      tasks = await repository.getActive();
      final moved = tasks.firstWhere((task) => task.id == secondId);
      expect(moved.dueDate, tuesday);
      expect(moved.taskMode, Task.planNowMode);
      expect(moved.sortOrder, secondListOrder);
      expect(tasks.where((task) => task.id == secondId), hasLength(1));
    },
  );

  test('old move commands choose a same-scope neighbor', () async {
    final db = await _makeDb();
    addTearDown(db.close);
    final repository = TaskRepository(db);
    final firstId = await repository.insert(_task(0, '同域A'));
    await repository.insert(_task(0, '其他分类', category: '工作'));
    final secondId = await repository.insert(_task(0, '同域B'));

    await repository.moveUp(secondId);

    final tasks = await repository.getActive();
    expect(tasks.map((task) => task.title).toList(), ['同域B', '其他分类', '同域A']);
    expect(tasks.firstWhere((task) => task.id == firstId).category, '默认');
  });

  test('service exposes collapse settings and subset reorder', () async {
    final db = await _makeDb();
    addTearDown(db.close);
    final service = TaskService(
      TaskRepository(db),
      SubTaskRepository(db),
      CategoryRepository(db),
    );
    expect(await service.getArrangementCollapsedModes(), isEmpty);
    await service.setArrangementCollapsedModes({Task.planNextMode});
    expect(await service.getArrangementCollapsedModes(), {Task.planNextMode});
  });
}
