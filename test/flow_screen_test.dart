import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/screens/flow_screen.dart';

Task _task(int id, String title, String mode, {DateTime? completedAt}) {
  return Task(id: id, title: title, taskMode: mode, completedAt: completedAt);
}

Widget _subject({
  List<Task> nowTasks = const [],
  List<Task> nextTasks = const [],
  List<Task> laterTasks = const [],
  List<Task> doneNowTasks = const [],
  List<Task> doneNextTasks = const [],
  List<Task> doneLaterTasks = const [],
  List<Task> unplannedTasks = const [],
  ValueChanged<Task>? onToggleTask,
  ValueChanged<Task>? onEditTask,
  ValueChanged<Task>? onDeleteTask,
  ValueChanged<Task>? onSyncToday,
  void Function(Task, String)? onMoveTask,
  Size size = const Size(1200, 800),
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: size),
        child: TaskArrangementView(
          nowTasks: nowTasks,
          nextTasks: nextTasks,
          laterTasks: laterTasks,
          doneNowTasks: doneNowTasks,
          doneNextTasks: doneNextTasks,
          doneLaterTasks: doneLaterTasks,
          unplannedTasks: unplannedTasks,
          onToggleTask: onToggleTask ?? (_) {},
          onOpenTask: (_) {},
          onMoveTask: onMoveTask == null
              ? (_, _) async {}
              : (task, mode) async => onMoveTask(task, mode),
          onEditTask: onEditTask ?? (_) {},
          onDeleteTask: onDeleteTask ?? (_) {},
          onAddTask: (_) async {},
          onReorder: (_, _, _) async {},
          onSyncToday: onSyncToday,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('arrangement view adapts from desktop stages to mobile list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final nowTasks = [
      _task(1, '让 GPT 完成项目', Task.planNowMode),
      _task(2, '读一会儿书', Task.planNowMode),
    ];
    final nextTasks = [_task(3, '吃饭', Task.planNextMode)];
    String? movedMode;

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(
      _subject(
        nowTasks: nowTasks,
        nextTasks: nextTasks,
        unplannedTasks: [_task(4, '整理桌面', Task.normalMode)],
        onMoveTask: (_, mode) => movedMode = mode,
      ),
    );
    expect(find.byKey(const Key('arrangement-desktop')), findsOneWidget);
    expect(find.text('现在 · 2'), findsOneWidget);
    expect(find.text('接下来 · 1'), findsOneWidget);
    expect(find.text('让 GPT 完成项目'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);

    await tester.tap(find.byTooltip('任务操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移到稍后').first);
    expect(movedMode, Task.planLaterMode);

    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpWidget(
      _subject(
        nowTasks: nowTasks,
        nextTasks: nextTasks,
        laterTasks: const [],
        unplannedTasks: [_task(4, '整理桌面', Task.normalMode)],
        size: const Size(390, 800),
      ),
    );
    expect(find.byKey(const Key('arrangement-mobile')), findsOneWidget);
    expect(find.text('稍后 · 0'), findsOneWidget);
  });

  testWidgets('completed tasks stay out of arrangement entirely', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(1200, 800);
    final doneAt = DateTime.now();
    await tester.pumpWidget(
      _subject(
        // 列只收未完成；组件是纯展示，拆分由上层完成
        nowTasks: [_task(1, '未完成任务A', Task.planNowMode)],
        doneNowTasks: [
          _task(2, '已完成任务B', Task.planNowMode, completedAt: doneAt),
        ],
        doneLaterTasks: [
          _task(3, '稍后已完成C', Task.planLaterMode, completedAt: doneAt),
        ],
      ),
    );
    expect(find.text('现在 · 1'), findsOneWidget);
    expect(find.text('已完成 · 2'), findsNothing);
    expect(find.text('未完成任务A'), findsOneWidget);
    expect(find.text('已完成任务B'), findsNothing);
    expect(find.text('稍后已完成C'), findsNothing);
  });

  testWidgets('completed section has no arrangement entry or clear action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(
      _subject(
        doneNowTasks: [
          _task(2, '已完成任务', Task.planNowMode, completedAt: DateTime.now()),
        ],
      ),
    );
    expect(find.byKey(const Key('arrangement-clear-completed')), findsNothing);
    expect(find.text('已完成 · 1'), findsNothing);
  });

  testWidgets('stage row menu offers edit, movement, sync today and delete', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(1200, 800);
    Task? edited;
    Task? deleted;
    Task? syncedToday;
    await tester.pumpWidget(
      _subject(
        nowTasks: [_task(1, '任务A', Task.planNowMode)],
        onEditTask: (task) => edited = task,
        onDeleteTask: (task) => deleted = task,
        onSyncToday: (task) => syncedToday = task,
      ),
    );
    await tester.tap(find.byTooltip('任务操作').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('移到接下来'), findsOneWidget);
    expect(find.text('移到稍后'), findsOneWidget);
    expect(find.text('移回列表'), findsOneWidget);
    expect(find.text('同步今日'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(edited?.id, 1);
    expect(deleted, isNull);

    await tester.tap(find.byTooltip('任务操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步今日'));
    await tester.pumpAndSettle();
    expect(syncedToday?.id, 1);

    await tester.tap(find.byTooltip('任务操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleted?.id, 1);
  });

  testWidgets('unplanned tasks are omitted from arrangement', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(
      _subject(unplannedTasks: [_task(4, '整理桌面', Task.normalMode)]),
    );
    expect(find.textContaining('未安排任务'), findsNothing);
    expect(find.text('整理桌面'), findsNothing);
  });

  testWidgets('stage with only done tasks shows undone empty hint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(1200, 800);
    final doneAt = DateTime.now();
    await tester.pumpWidget(
      _subject(
        // 唯一任务已完成 → 未完成列空，显示空态
        nowTasks: const [],
        doneNowTasks: [_task(1, '唯一任务', Task.planNowMode, completedAt: doneAt)],
      ),
    );
    expect(find.text('现在 · 0'), findsOneWidget);
    // 三列都空 → 三处空态
    expect(find.text('暂无未完成任务'), findsNWidgets(3));
  });

  testWidgets('mobile arrangement has no completed shortcut', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(390, 800);
    final doneAt = DateTime.now();
    await tester.pumpWidget(
      _subject(
        doneLaterTasks: [
          _task(3, '稍后已完成C', Task.planLaterMode, completedAt: doneAt),
        ],
        size: const Size(390, 800),
      ),
    );
    expect(find.text('已完成 · 1'), findsNothing);
    expect(find.text('稍后已完成C'), findsNothing);
  });
}
