import 'dart:async';
import 'dart:io';

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
import 'repositories/task_memo_repository.dart';
import 'services/task_service.dart';
import 'services/memo_service.dart';
import 'services/task_memo_service.dart';
import 'services/notification_service.dart';
import 'services/backup_file_service.dart';
import 'sync/supabase_sync_gateway.dart';
import 'sync/sync_config.dart';
import 'sync/sync_coordinator.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_status.dart';
import 'screens/todo_screen.dart';
import 'screens/memo_screen.dart';

final todoScreenKey = GlobalKey<TodoScreenState>();
final memoScreenKey = GlobalKey<MemoScreenState>();
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final currentTabIndex = ValueNotifier<int>(0); // 0=安排, 1=备忘录

String resolveAndroidRootPage(String? savedPage, String? legacyTab) {
  if (savedPage == 'arrange' || savedPage == 'memo') return savedPage!;
  return legacyTab == '0' ? 'memo' : 'arrange';
}

void toggleTheme() {
  final newMode = themeModeNotifier.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
  themeModeNotifier.value = newMode;
  DatabaseProvider().setSetting(
    'dark_mode',
    newMode == ThemeMode.dark ? 'true' : 'false',
  );
}

class NewTaskIntent extends Intent {}

class NewSubIntent extends Intent {}

class FocusInputIntent extends Intent {}

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
  final taskMemoRepo = TaskMemoRepository(db);
  final syncConfig = await SyncConfig.load();
  final syncGateway = SupabaseSyncGateway(syncConfig, db);
  await syncGateway.restoreSession();
  final syncCoordinator = SyncCoordinator(
    config: syncConfig,
    engine: SyncEngine(db, syncGateway),
    gateway: syncGateway,
    isAuthenticated: () => syncGateway.isAuthenticated,
  );
  final taskService = TaskService(
    taskRepo,
    subTaskRepo,
    categoryRepo,
    onChanged: syncCoordinator.scheduleSync,
  );
  final memoService = MemoService(
    memoRepo,
    memoCatRepo,
    onChanged: syncCoordinator.scheduleSync,
  );
  final taskMemoService = TaskMemoService(
    taskRepo,
    taskMemoRepo,
    subTaskRepo,
    memoService,
    onChanged: syncCoordinator.scheduleSync,
  );
  final notificationService = NotificationService();
  await notificationService.init();
  syncCoordinator.start();

  // 恢复主题偏好
  final savedTheme = await DatabaseProvider().getSetting('dark_mode');
  if (savedTheme == 'true') {
    themeModeNotifier.value = ThemeMode.dark;
  } else if (savedTheme == 'false') {
    themeModeNotifier.value = ThemeMode.light;
  }

  runApp(
    TodoApp(
      taskService: taskService,
      memoService: memoService,
      notificationService: notificationService,
      taskMemoService: taskMemoService,
      syncCoordinator: syncCoordinator,
      syncGateway: syncGateway,
      syncConfig: syncConfig,
    ),
  );
}

class TodoApp extends StatelessWidget {
  final TaskService taskService;
  final MemoService memoService;
  final NotificationService notificationService;
  final TaskMemoService taskMemoService;
  final SyncCoordinator syncCoordinator;
  final SupabaseSyncGateway syncGateway;
  final SyncConfig syncConfig;

  const TodoApp({
    super.key,
    required this.taskService,
    required this.memoService,
    required this.notificationService,
    required this.taskMemoService,
    required this.syncCoordinator,
    required this.syncGateway,
    required this.syncConfig,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, _) => MaterialApp(
        title: '备忘录',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
          brightness: Brightness.light,
          popupMenuTheme: PopupMenuThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            position: PopupMenuPosition.under,
            elevation: 4,
          ),
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
          brightness: Brightness.dark,
          popupMenuTheme: PopupMenuThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            position: PopupMenuPosition.under,
            elevation: 4,
          ),
        ),
        themeMode: mode,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        shortcuts: <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyN, control: true):
              NewTaskIntent(),
          SingleActivator(LogicalKeyboardKey.keyT, control: true):
              NewSubIntent(),
          SingleActivator(LogicalKeyboardKey.keyE, control: true):
              FocusInputIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, control: true):
              SearchIntent(),
          SingleActivator(LogicalKeyboardKey.keyD, control: true):
              ToggleThemeIntent(),
        },
        actions: <Type, Action<Intent>>{
          NewTaskIntent: CallbackAction<NewTaskIntent>(
            onInvoke: (_) {
              if (currentTabIndex.value == 0) {
                todoScreenKey.currentState?.showAddDialog();
              } else {
                memoScreenKey.currentState?.showAddDialog();
              }
              return null;
            },
          ),
          NewSubIntent: CallbackAction<NewSubIntent>(
            onInvoke: (_) {
              if (currentTabIndex.value == 0) {
                todoScreenKey.currentState?.addSubTaskToLastExpanded();
              }
              return null;
            },
          ),
          FocusInputIntent: CallbackAction<FocusInputIntent>(
            onInvoke: (_) {
              if (currentTabIndex.value == 0) {
                todoScreenKey.currentState?.focusInput();
              } else {
                memoScreenKey.currentState?.focusInput();
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
            onInvoke: (_) {
              toggleTheme();
              return null;
            },
          ),
        },
        home: MainScreen(
          taskService: taskService,
          memoService: memoService,
          notificationService: notificationService,
          taskMemoService: taskMemoService,
          syncCoordinator: syncCoordinator,
          syncGateway: syncGateway,
          syncConfig: syncConfig,
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
  final TaskMemoService taskMemoService;
  final SyncCoordinator syncCoordinator;
  final SupabaseSyncGateway syncGateway;
  final SyncConfig syncConfig;

  const MainScreen({
    super.key,
    required this.taskService,
    required this.memoService,
    required this.notificationService,
    required this.taskMemoService,
    required this.syncCoordinator,
    required this.syncGateway,
    required this.syncConfig,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _dialogShowing = false;
  bool _todoArrangementMode = true;
  TodoPrimaryPage _todoPrimaryPage = TodoPrimaryPage.week;
  String _memoSectionTitle = '全部备忘';
  late final BackupFileService _backupFileService;
  DateTime? _lastRenderedSyncAt;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _backupFileService = BackupFileService(DatabaseProvider());
    _tabController.addListener(() {
      setState(() {});
      currentTabIndex.value = _tabController.index;
      if (_tabController.indexIsChanging) return;
      if (Platform.isAndroid) {
        unawaited(
          DatabaseProvider().setSetting(
            'android_last_root_page',
            _tabController.index == 0 ? 'arrange' : 'memo',
          ),
        );
      }
      if (_tabController.index == 0) {
        unawaited(todoScreenKey.currentState?.refresh());
      } else {
        unawaited(memoScreenKey.currentState?.refresh());
      }
    });
    widget.notificationService.pendingNotification.addListener(_showPending);
    widget.syncCoordinator.status.addListener(_refreshAfterCloudSync);
    if (Platform.isAndroid) unawaited(_restoreRootTab());
  }

  Future<void> _restoreRootTab() async {
    final database = DatabaseProvider();
    var saved = await database.getSetting('android_last_root_page');
    if (saved != 'arrange' && saved != 'memo') {
      final legacy = await database.getSetting('android_last_root_tab');
      saved = resolveAndroidRootPage(saved, legacy);
      await database.setSetting('android_last_root_page', saved);
    }
    if (!mounted || saved != 'memo') return;
    _tabController.animateTo(1);
  }

  @override
  void dispose() {
    widget.notificationService.pendingNotification.removeListener(_showPending);
    widget.syncCoordinator.status.removeListener(_refreshAfterCloudSync);
    _tabController.dispose();
    unawaited(widget.syncCoordinator.dispose());
    super.dispose();
  }

  void _refreshAfterCloudSync() {
    final status = widget.syncCoordinator.status.value;
    final syncedAt = status.lastSyncedAt;
    if (status.phase != SyncPhase.idle ||
        syncedAt == null ||
        syncedAt == _lastRenderedSyncAt) {
      return;
    }
    _lastRenderedSyncAt = syncedAt;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([
        todoScreenKey.currentState?.refresh() ?? Future<void>.value(),
        memoScreenKey.currentState?.refresh() ?? Future<void>.value(),
      ]);
    });
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
                widget.notificationService.pendingNotification.value,
              );
              if (newQueue.isNotEmpty) newQueue.removeAt(0);
              widget.notificationService.pendingNotification.value = newQueue;
              _dialogShowing = false;
              if (newQueue.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _showPending(),
                );
              }
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final path = await _backupFileService.exportBackup();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('备份已导出'),
          content: SelectableText('已保存到：\n$path'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  Future<void> _importBackup() async {
    try {
      final jsonText = await _backupFileService.pickBackupJson();
      if (jsonText == null || !mounted) return;
      final preview = DatabaseProvider().previewBackup(jsonText);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('合并导入备份'),
          content: Text(
            '任务 ${preview.counts['tasks']} 条，备忘录 ${preview.counts['memos']} 条，'
            '子任务 ${preview.counts['subtasks']} 条。\n\n'
            '导入会先自动备份当前数据，再按记录版本合并，不会清空现有内容。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始合并'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await DatabaseProvider().importAllJsonMerge(jsonText);
      await Future.wait([
        todoScreenKey.currentState?.refresh() ?? Future<void>.value(),
        memoScreenKey.currentState?.refresh() ?? Future<void>.value(),
      ]);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('合并完成'),
          content: SelectableText(
            '新增 ${result.inserted} 条，更新 ${result.updated} 条，保留本地较新记录 ${result.skipped} 条。\n\n'
            '导入前备份：\n${result.safetyBackupPath}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败，现有数据未清空：$error')));
    }
  }

  Future<void> _handleSyncTap() async {
    if (!widget.syncConfig.isBackendConfigured) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('同步服务未配置'),
          content: const SelectableText(
            '未找到 Supabase 公共配置。请检查本地配置文件或构建参数。'
            '本机数据仍会正常保存，配置后再登录即可同步。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (!widget.syncGateway.isAuthenticated) {
      await _showSyncLoginDialog();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(
                widget.syncGateway.signedInEmail.isEmpty
                    ? '已登录'
                    : widget.syncGateway.signedInEmail,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('立即同步'),
              onTap: () => Navigator.pop(sheetContext, 'sync'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出同步账号'),
              onTap: () => Navigator.pop(sheetContext, 'logout'),
            ),
          ],
        ),
      ),
    );
    if (action == 'sync') {
      await widget.syncCoordinator.syncNow();
      if (!mounted) return;
      final status = widget.syncCoordinator.status.value;
      final message = status.phase == SyncPhase.idle
          ? status.pendingCount == 0
                ? '同步完成，双端数据已刷新'
                : '同步完成，仍有 ${status.pendingCount} 条等待上传'
          : status.message ?? '同步失败，修改已保存在本机';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    if (action == 'logout') {
      await widget.syncGateway.signOut();
      await widget.syncCoordinator.handleSignedOut();
    }
  }

  Future<void> _showSyncLoginDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Windows / Android 同步'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.syncGateway.signUp(
                          emailController.text,
                          passwordController.text,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        widget.syncCoordinator.start();
                      } catch (exception) {
                        setDialogState(() {
                          busy = false;
                          error = exception.toString().replaceFirst(
                            'Bad state: ',
                            '',
                          );
                        });
                      }
                    },
              child: const Text('注册'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.syncGateway.signIn(
                          emailController.text,
                          passwordController.text,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        widget.syncCoordinator.start();
                      } catch (exception) {
                        setDialogState(() {
                          busy = false;
                          error = exception.toString().replaceFirst(
                            'Bad state: ',
                            '',
                          );
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMemo = _tabController.index == 1;
    final isCompact = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: isCompact ? 8 : 16,
        title: isMemo
            ? Text(_memoSectionTitle)
            : SegmentedButton<TodoPrimaryPage>(
                key: const Key('todo-primary-navigation'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TodoPrimaryPage.week, label: Text('本周')),
                  ButtonSegment(
                    value: TodoPrimaryPage.stage,
                    label: Text('阶段'),
                  ),
                  ButtonSegment(
                    value: TodoPrimaryPage.inbox,
                    label: Text('收件箱'),
                  ),
                ],
                selected: {_todoPrimaryPage},
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    EdgeInsets.symmetric(horizontal: isCompact ? 6 : 12),
                  ),
                ),
                onSelectionChanged: (selection) {
                  final page = selection.first;
                  setState(() {
                    _todoPrimaryPage = page;
                    _todoArrangementMode = page != TodoPrimaryPage.inbox;
                  });
                  todoScreenKey.currentState?.setPrimaryPage(page);
                },
              ),
        actions: [
          if (isMemo)
            IconButton(
              tooltip: '搜索备忘录',
              onPressed: () => memoScreenKey.currentState?.focusSearch(),
              icon: const Icon(Icons.search_rounded),
            ),
          ValueListenableBuilder<SyncStatus>(
            valueListenable: widget.syncCoordinator.status,
            builder: (_, sync, _) => IconButton(
              tooltip: sync.message ?? '立即同步',
              onPressed: sync.phase == SyncPhase.syncing
                  ? null
                  : _handleSyncTap,
              icon: Icon(switch (sync.phase) {
                SyncPhase.syncing => Icons.sync,
                SyncPhase.signedOut => Icons.account_circle_outlined,
                SyncPhase.idle => Icons.cloud_done_outlined,
                SyncPhase.offline => Icons.cloud_off_outlined,
                SyncPhase.error => Icons.error_outline,
                SyncPhase.disabled => Icons.cloud_off_outlined,
              }),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            iconSize: 22,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onSelected: (v) async {
              if (v == 'theme') {
                toggleTheme();
              } else if (v == 'export') {
                await _exportBackup();
              } else if (v == 'import') {
                await _importBackup();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      themeModeNotifier.value == ThemeMode.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      themeModeNotifier.value == ThemeMode.dark
                          ? '切换浅色主题'
                          : '切换深色主题',
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_upload_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('导出 JSON 备份'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('合并导入 JSON'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = TabBarView(
            controller: _tabController,
            children: [
              TodoScreen(
                key: todoScreenKey,
                taskService: widget.taskService,
                notificationService: widget.notificationService,
                taskMemoService: widget.taskMemoService,
                onArrangementModeChanged: (value) {
                  if (_todoArrangementMode == value) return;
                  setState(() => _todoArrangementMode = value);
                },
                onPrimaryPageChanged: (page) {
                  if (_todoPrimaryPage == page) return;
                  setState(() {
                    _todoPrimaryPage = page;
                    _todoArrangementMode = page != TodoPrimaryPage.inbox;
                  });
                },
              ),
              MemoScreen(
                key: memoScreenKey,
                memoService: widget.memoService,
                taskMemoService: widget.taskMemoService,
                taskService: widget.taskService,
                notificationService: widget.notificationService,
                onSectionChanged: (title) {
                  if (_memoSectionTitle == title) return;
                  setState(() => _memoSectionTitle = title);
                },
              ),
            ],
          );
          if (constraints.maxWidth < 900) return content;
          return Row(
            children: [
              NavigationRail(
                selectedIndex: _tabController.index,
                onDestinationSelected: _tabController.animateTo,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.85,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Icon(
                    Icons.local_florist_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.checklist_outlined),
                    selectedIcon: Icon(Icons.checklist_rounded),
                    label: Text('安排'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.note_alt_outlined),
                    selectedIcon: Icon(Icons.note_alt_rounded),
                    label: Text('备忘录'),
                  ),
                ],
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(
              selectedIndex: _tabController.index,
              onDestinationSelected: _tabController.animateTo,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.checklist_outlined),
                  selectedIcon: Icon(Icons.checklist_rounded),
                  label: '安排',
                ),
                NavigationDestination(
                  icon: Icon(Icons.note_alt_outlined),
                  selectedIcon: Icon(Icons.note_alt_rounded),
                  label: '备忘录',
                ),
              ],
            )
          : null,
      floatingActionButton: isMemo
          ? (isCompact
                ? FloatingActionButton(
                    onPressed: () =>
                        memoScreenKey.currentState?.showAddDialog(),
                    child: const Icon(Icons.add),
                  )
                : null)
          : !_todoArrangementMode
          ? FloatingActionButton(
              onPressed: () => todoScreenKey.currentState?.showAddDialog(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
