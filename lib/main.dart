import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'database/database.dart';
import 'repositories/task_repository.dart';
import 'repositories/subtask_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/memo_repository.dart';
import 'repositories/memo_category_repository.dart';
import 'services/task_service.dart';
import 'services/memo_service.dart';
import 'services/notification_service.dart';
import 'screens/todo_screen.dart';
import 'screens/memo_screen.dart';

final todoScreenKey = GlobalKey<TodoScreenState>();
final memoScreenKey = GlobalKey<MemoScreenState>();
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final currentTabIndex = ValueNotifier<int>(0); // 0=备忘录, 1=Todo

void toggleTheme() {
  final newMode = themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  themeModeNotifier.value = newMode;
  DatabaseProvider().setSetting('dark_mode', newMode == ThemeMode.dark ? 'true' : 'false');
}

class NewTaskIntent extends Intent {}
class SearchIntent extends Intent {}
class ToggleThemeIntent extends Intent {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh');

  // ── DI 链：Database → Repositories → Services ──
  final db = await DatabaseProvider().database;
  final taskRepo = TaskRepository(db);
  final subTaskRepo = SubTaskRepository(db);
  final categoryRepo = CategoryRepository(db);
  final memoRepo = MemoRepository(db);
  final memoCatRepo = MemoCategoryRepository(db);
  final taskService = TaskService(taskRepo, subTaskRepo, categoryRepo);
  final memoService = MemoService(memoRepo, memoCatRepo);
  final notificationService = NotificationService();
  await notificationService.init();

  // 恢复主题偏好
  final savedTheme = await DatabaseProvider().getSetting('dark_mode');
  if (savedTheme == 'true') {
    themeModeNotifier.value = ThemeMode.dark;
  } else if (savedTheme == 'false') {
    themeModeNotifier.value = ThemeMode.light;
  }

  runApp(TodoApp(
    taskService: taskService,
    memoService: memoService,
    notificationService: notificationService,
  ));
}

class TodoApp extends StatelessWidget {
  final TaskService taskService;
  final MemoService memoService;
  final NotificationService notificationService;

  const TodoApp({
    super.key,
    required this.taskService,
    required this.memoService,
    required this.notificationService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: '备忘录',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
          brightness: Brightness.dark,
        ),
        themeMode: mode,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        shortcuts: <ShortcutActivator, Intent>{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN): NewTaskIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF): SearchIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyD): ToggleThemeIntent(),
        },
        actions: <Type, Action<Intent>>{
          NewTaskIntent: CallbackAction<NewTaskIntent>(
            onInvoke: (_) {
              if (currentTabIndex.value == 0) {
                memoScreenKey.currentState?.showAddDialog();
              } else {
                todoScreenKey.currentState?.showAddDialog();
              }
              return null;
            },
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) {
              todoScreenKey.currentState?.focusSearch();
              memoScreenKey.currentState?.focusSearch();
              return null;
            },
          ),
          ToggleThemeIntent: CallbackAction<ToggleThemeIntent>(
            onInvoke: (_) { toggleTheme(); return null; },
          ),
        },
        home: MainScreen(
          taskService: taskService,
          memoService: memoService,
          notificationService: notificationService,
        ),
      ),
    );
  }
}

/// 底部 TabBar 主页面
class MainScreen extends StatefulWidget {
  final TaskService taskService;
  final MemoService memoService;
  final NotificationService notificationService;

  const MainScreen({
    super.key,
    required this.taskService,
    required this.memoService,
    required this.notificationService,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
      currentTabIndex.value = _tabController.index;
    });
    widget.notificationService.pendingNotification.addListener(_showPending);
  }

  @override
  void dispose() {
    widget.notificationService.pendingNotification.removeListener(_showPending);
    _tabController.dispose();
    super.dispose();
  }

  void _showPending() {
    if (_dialogShowing || !mounted) return;
    final queue = widget.notificationService.pendingNotification.value;
    if (queue.isEmpty) return;
    _dialogShowing = true;
    final data = queue.first;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(data.title),
        content: Text(data.body),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // 消费当前通知，若有剩余继续弹
              final newQueue = List<({String title, String body})>.from(
                  widget.notificationService.pendingNotification.value);
              if (newQueue.isNotEmpty) newQueue.removeAt(0);
              widget.notificationService.pendingNotification.value = newQueue;
              _dialogShowing = false;
              if (newQueue.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _showPending());
              }
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMemo = _tabController.index == 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(isMemo ? '备忘录' : 'Todo List'),
        actions: [
          IconButton(
            icon: Icon(
              themeModeNotifier.value == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
            ),
            tooltip: '切换主题',
            onPressed: toggleTheme,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                try {
                  final path = await DatabaseProvider().exportAllJson();
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('导出成功'),
                      content: SelectableText('已保存到：\n$path'),
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('好的'),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('导出失败'),
                      content: Text('$e'),
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'export', child: Text('📤 导出数据 (JSON)')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.note_alt_outlined), text: '备忘录'),
            Tab(icon: Icon(Icons.checklist), text: 'Todo List'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MemoScreen(key: memoScreenKey, memoService: widget.memoService, notificationService: widget.notificationService),
          TodoScreen(
            key: todoScreenKey,
            taskService: widget.taskService,
            notificationService: widget.notificationService,
          ),
        ],
      ),
      floatingActionButton: !isMemo
          ? FloatingActionButton(
              onPressed: () => todoScreenKey.currentState?.showAddDialog(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
