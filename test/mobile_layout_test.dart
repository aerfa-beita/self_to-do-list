import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/main.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/repositories/category_repository.dart';
import 'package:todo_list/repositories/memo_category_repository.dart';
import 'package:todo_list/repositories/memo_repository.dart';
import 'package:todo_list/repositories/subtask_repository.dart';
import 'package:todo_list/repositories/task_memo_repository.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/screens/memo_screen.dart';
import 'package:todo_list/screens/todo_screen.dart';
import 'package:todo_list/services/memo_service.dart';
import 'package:todo_list/services/notification_service.dart';
import 'package:todo_list/services/reminder_coordinator.dart';
import 'package:todo_list/services/reminder_settings_service.dart';
import 'package:todo_list/services/task_memo_service.dart';
import 'package:todo_list/services/task_service.dart';
import 'package:todo_list/sync/supabase_sync_gateway.dart';
import 'package:todo_list/sync/sync_config.dart';
import 'package:todo_list/sync/sync_coordinator.dart';
import 'package:todo_list/sync/sync_engine.dart';
import 'package:todo_list/widgets/workload_companion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy root tab values migrate to semantic arrange or memo pages', () {
    expect(resolveAndroidRootPage('memo', '1'), 'memo');
    expect(resolveAndroidRootPage('arrange', '0'), 'arrange');
    expect(resolveAndroidRootPage(null, '0'), 'memo');
    expect(resolveAndroidRootPage(null, '1'), 'arrange');
    expect(resolveAndroidRootPage(null, null), 'arrange');
  });

  Future<void> waitForNativeDatabase(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('mobile Todo hides persistent input and uses edge companion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final db = (await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      return DatabaseProvider().openAtPath(inMemoryDatabasePath);
    }))!;
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(
      () => TaskRepository(db).insert(Task(title: '长按取消测试')),
    );
    final screenKey = GlobalKey<TodoScreenState>();

    await tester.pumpWidget(
      MaterialApp(
        home: TodoScreen(
          key: screenKey,
          taskService: TaskService(
            TaskRepository(db),
            SubTaskRepository(db),
            CategoryRepository(db),
          ),
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
    await waitForNativeDatabase(tester);
    screenKey.currentState!.setPrimaryPage(TodoPrimaryPage.inbox);
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    await tester.longPress(find.text('长按取消测试'));
    await tester.pump();
    expect(find.byKey(const Key('todo-selection-cancel')), findsNothing);
    expect(tester.getSize(find.byType(WorkloadCompanion)), const Size(48, 48));
    expect(
      find.byKey(const ValueKey('companion-edge-tap-target')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('todo-display-mode')), findsNothing);
    expect(find.byKey(const Key('todo-mobile-toolbar')), findsOneWidget);
    expect(find.byKey(const Key('todo-mobile-filter-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('todo-mobile-filter-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('筛选与统计'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('todo-mobile-select-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('todo-mobile-select-button')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('长按取消测试'));
    await tester.pump();
    expect(find.byKey(const Key('todo-selection-cancel')), findsOneWidget);
    expect(find.byKey(const Key('todo-selection-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('todo-selection-cancel')));
    await tester.pump();
    screenKey.currentState!.setPrimaryPage(TodoPrimaryPage.stage);
    await tester.pump();
    expect(find.byKey(const Key('arrangement-mobile')), findsOneWidget);
    expect(find.textContaining('未安排任务'), findsNothing);
    expect(find.byKey(const Key('arrangement-add-plan_now')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await waitForNativeDatabase(tester);
  });

  testWidgets('mobile Memo hides persistent input', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final db = (await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      return DatabaseProvider().openAtPath(inMemoryDatabasePath);
    }))!;
    addTearDown(() => tester.runAsync(db.close));
    final screenKey = GlobalKey<MemoScreenState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemoScreen(
            key: screenKey,
            memoService: MemoService(
              MemoRepository(db),
              MemoCategoryRepository(db),
            ),
            notificationService: NotificationService(),
            taskMemoService: TaskMemoService(
              TaskRepository(db),
              TaskMemoRepository(db),
              SubTaskRepository(db),
              MemoService(MemoRepository(db), MemoCategoryRepository(db)),
            ),
            taskService: TaskService(
              TaskRepository(db),
              SubTaskRepository(db),
              CategoryRepository(db),
            ),
          ),
        ),
      ),
    );
    await waitForNativeDatabase(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.text('还没有备忘录，点右下角创建'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await waitForNativeDatabase(tester);
  });

  testWidgets('mobile app shell uses arrange-first single-level navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final db = (await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      return DatabaseProvider().openAtPath(inMemoryDatabasePath);
    }))!;
    addTearDown(() => tester.runAsync(db.close));
    const config = SyncConfig(
      supabaseUrl: '',
      anonKey: '',
      accessToken: '',
      userId: '',
      realtimeEnabled: false,
    );
    final gateway = SupabaseSyncGateway(config, db);
    final coordinator = SyncCoordinator(
      config: config,
      engine: SyncEngine(db, gateway),
      gateway: gateway,
      isAuthenticated: () => false,
    );
    final taskRepository = TaskRepository(db);
    final subTaskRepository = SubTaskRepository(db);
    final memoService = MemoService(
      MemoRepository(db),
      MemoCategoryRepository(db),
    );
    final taskService = TaskService(
      taskRepository,
      subTaskRepository,
      CategoryRepository(db),
    );
    final notificationService = NotificationService();
    final reminderSettingsService = ReminderSettingsService(DatabaseProvider());
    final reminderCoordinator = ReminderCoordinator(
      taskService,
      notificationService,
      reminderSettingsService,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainScreen(
          taskService: taskService,
          memoService: memoService,
          notificationService: notificationService,
          reminderSettingsService: reminderSettingsService,
          reminderCoordinator: reminderCoordinator,
          taskMemoService: TaskMemoService(
            taskRepository,
            TaskMemoRepository(db),
            subTaskRepository,
            memoService,
          ),
          syncCoordinator: coordinator,
          syncGateway: gateway,
          syncConfig: config,
        ),
      ),
    );
    await waitForNativeDatabase(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect((navigation.destinations[0] as NavigationDestination).label, '安排');
    expect((navigation.destinations[1] as NavigationDestination).label, '备忘录');
    expect(find.byKey(const Key('todo-primary-navigation')), findsOneWidget);
    expect(find.text('本周'), findsOneWidget);
    expect(find.text('阶段'), findsOneWidget);
    expect(find.text('收件箱'), findsWidgets);
    expect(find.byKey(const Key('arrangement-week-list')), findsOneWidget);
    expect(find.byKey(const Key('todo-display-mode')), findsNothing);
    expect(find.text('Todo List'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('备忘录'));
    await tester.pump(const Duration(milliseconds: 400));
    await waitForNativeDatabase(tester);
    expect(find.byKey(const Key('todo-primary-navigation')), findsNothing);
    expect(find.text('全部备忘'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await waitForNativeDatabase(tester);
  });
}
