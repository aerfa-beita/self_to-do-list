import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../database/database.dart';
import '../models/sub_task.dart';
import '../services/task_service.dart';
import '../services/android_widget_service.dart';
import '../services/notification_service.dart';
import '../services/task_memo_service.dart';
import '../utils/date_utils.dart';
import '../widgets/todo_item.dart';
import '../widgets/add_todo_dialog.dart';
import '../widgets/deleted_task_card.dart';
import '../widgets/schedule_prompt_dialog.dart';
import '../widgets/workload_companion.dart';
import 'flow_screen.dart';
import 'task_detail_screen.dart';

enum TodoDisplayMode { list, arrangement }

enum TodoPrimaryPage { week, stage, inbox }

class TodoScreen extends StatefulWidget {
  final TaskService taskService;
  final NotificationService notificationService;
  final TaskMemoService taskMemoService;
  final ValueChanged<bool>? onArrangementModeChanged;
  final ValueChanged<TodoPrimaryPage>? onPrimaryPageChanged;

  const TodoScreen({
    super.key,
    required this.taskService,
    required this.notificationService,
    required this.taskMemoService,
    this.onArrangementModeChanged,
    this.onPrimaryPageChanged,
  });

  @override
  State<TodoScreen> createState() => TodoScreenState();
}

class TodoScreenState extends State<TodoScreen> with WidgetsBindingObserver {
  List<Task> _activeUndone = [];
  List<Task> _activeDone = [];
  List<Task> _deleted = [];
  Map<int, ({int total, int done})> _progress = {};
  String _filter = '全部';
  String _searchQuery = '';
  List<Map<String, dynamic>> _categories = [];
  bool _showCompleted = true;
  bool _showDeleted = true;
  final Set<int> _cardExpanded = {};
  final Map<int, List<SubTask>> _cardSubTasks = {};
  final _quickInputController = TextEditingController();
  final _quickInputFocus = FocusNode();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  int? _lastExpandedTaskId;
  bool _searchVisible = false;
  double _lastScrollOffset = 0;
  // 批量选择
  bool _selectMode = false;
  final Set<int> _selectedIds = {};
  String _smartView = 'inbox';
  int _todayEffort = 0;
  int _dailyEffortLimit = 8;
  Task? _selectedTask;
  final _companionKey = GlobalKey<WorkloadCompanionState>();
  Offset _companionPosition = const Offset(1, .18);
  bool _reminderWarningShown = false;
  TodoDisplayMode _displayMode = TodoDisplayMode.arrangement;
  ArrangementViewMode _arrangementViewMode = ArrangementViewMode.week;
  Set<String> _arrangementCollapsedModes = <String>{};
  bool _reorderInProgress = false;
  bool _arrangementCollapseWritePending = false;

  List<String> get _categoryNames => [
    '全部',
    ..._categories.map((c) => c['name'] as String),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    if (Platform.isAndroid) unawaited(_restorePageState());
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted || MediaQuery.sizeOf(context).width < 900) return;
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (offset <= 0 && _lastScrollOffset > 0 && !_searchVisible) {
      setState(() => _searchVisible = true);
    }
    if (offset > 100 && _searchVisible) {
      setState(() => _searchVisible = false);
    }
    _lastScrollOffset = offset;
  }

  Future<void> _restorePageState() async {
    final raw = await DatabaseProvider().getSetting('android_last_todo_page');
    if (raw == null || !mounted) return;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final primary = switch (saved['primary']) {
        'stage' => TodoPrimaryPage.stage,
        'inbox' => TodoPrimaryPage.inbox,
        'week' => TodoPrimaryPage.week,
        _ =>
          saved['display'] == 'list'
              ? TodoPrimaryPage.inbox
              : saved['arrangement'] == 'stage'
              ? TodoPrimaryPage.stage
              : TodoPrimaryPage.week,
      };
      final mode = primary == TodoPrimaryPage.inbox
          ? TodoDisplayMode.list
          : TodoDisplayMode.arrangement;
      final smart = saved['smart'] as String? ?? 'inbox';
      final stage = primary == TodoPrimaryPage.stage
          ? ArrangementViewMode.stage
          : ArrangementViewMode.week;
      setState(() {
        _displayMode = mode;
        _smartView = mode == TodoDisplayMode.list
            ? const {
                    'inbox',
                    'arranged',
                    'completed',
                    'deleted',
                  }.contains(smart)
                  ? smart
                  : 'inbox'
            : const {'active', 'completed', 'deleted'}.contains(smart)
            ? smart
            : 'active';
        _arrangementViewMode = stage;
      });
      widget.onArrangementModeChanged?.call(
        mode == TodoDisplayMode.arrangement,
      );
      widget.onPrimaryPageChanged?.call(primary);
    } catch (_) {
      // Invalid local UI state falls back to the default view.
    }
  }

  void _savePageState() {
    if (!Platform.isAndroid) return;
    unawaited(
      DatabaseProvider().setSetting(
        'android_last_todo_page',
        jsonEncode({
          'primary': switch (primaryPage) {
            TodoPrimaryPage.week => 'week',
            TodoPrimaryPage.stage => 'stage',
            TodoPrimaryPage.inbox => 'inbox',
          },
          'display': _displayMode == TodoDisplayMode.arrangement
              ? 'arrangement'
              : 'list',
          'smart': _smartView,
          'arrangement': _arrangementViewMode == ArrangementViewMode.week
              ? 'week'
              : 'stage',
        }),
      ),
    );
  }

  TodoPrimaryPage get primaryPage => _displayMode == TodoDisplayMode.list
      ? TodoPrimaryPage.inbox
      : _arrangementViewMode == ArrangementViewMode.week
      ? TodoPrimaryPage.week
      : TodoPrimaryPage.stage;

  String get _currentActionScope => switch (primaryPage) {
    TodoPrimaryPage.inbox => Task.actionScopeInbox,
    TodoPrimaryPage.stage => Task.actionScopeStage,
    TodoPrimaryPage.week => Task.actionScopeWeek,
  };

  void setPrimaryPage(TodoPrimaryPage page) {
    if (page == primaryPage) return;
    setState(() {
      _displayMode = page == TodoPrimaryPage.inbox
          ? TodoDisplayMode.list
          : TodoDisplayMode.arrangement;
      _arrangementViewMode = page == TodoPrimaryPage.stage
          ? ArrangementViewMode.stage
          : ArrangementViewMode.week;
      _smartView = page == TodoPrimaryPage.inbox ? 'inbox' : 'active';
      _selectedTask = null;
      _selectMode = false;
      _selectedIds.clear();
    });
    widget.onArrangementModeChanged?.call(
      _displayMode == TodoDisplayMode.arrangement,
    );
    widget.onPrimaryPageChanged?.call(page);
    _savePageState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickInputController.dispose();
    _quickInputFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadAll());
  }

  Future<void> _quickCreate() async {
    final title = _quickInputController.text.trim();
    if (title.isEmpty) return;
    final schedule = await _promptForSchedule(
      title,
      initialDueDate: _defaultDueDateForView(),
    );
    if (schedule == null) return;
    final draft = Task(
      title: title,
      dueDate: schedule.dueDate,
      reminderTime: schedule.reminderTime,
      repeatType: schedule.repeatType,
    );
    final approved = await _applyWorkloadGuard(draft);
    if (approved == null) return;
    final newId = await widget.taskService.insertTask(approved);
    final savedTask = approved.copyWith(id: newId);
    await _scheduleReminder(savedTask);
    _quickInputController.clear();
    if (mounted && MediaQuery.sizeOf(context).width >= 900) {
      _quickInputFocus.requestFocus();
    }
    await _loadAll();
  }

  Future<void> _loadAll() async {
    final collapseVersionAtRead = _collapseWriteVersion;
    final collapseWritePendingAtRead = _arrangementCollapseWritePending;
    final active = await widget.taskService.getActiveTasks();
    final deleted = await widget.taskService.getDeletedTasks();
    final categories = await widget.taskService.getCategories();
    final todayEffort = await widget.taskService.getTodayEffort();
    final dailyEffortLimit = await widget.taskService.getDailyEffortLimit();
    final companionPosition = await widget.taskService.getCompanionPosition();
    final arrangementCollapsedModes = await widget.taskService
        .getArrangementCollapsedModes();
    final progress = <int, ({int total, int done})>{};
    for (final t in [...active, ...deleted]) {
      progress[t.id!] = await widget.taskService.getSubTaskProgress(t.id!);
    }
    for (final t in active.where((t) => !t.isCompleted)) {
      _scheduleReminder(t);
    }
    if (!mounted) return;
    setState(() {
      _activeUndone = active.where((t) => !t.isCompleted).toList();
      _activeDone = active.where((t) => t.isCompleted).toList();
      _deleted = deleted;
      _categories = categories;
      _progress = progress;
      _todayEffort = todayEffort;
      _dailyEffortLimit = dailyEffortLimit;
      if (collapseVersionAtRead == _collapseWriteVersion &&
          !collapseWritePendingAtRead) {
        _arrangementCollapsedModes = arrangementCollapsedModes;
      }
      if (companionPosition != null) {
        _companionPosition = Offset(companionPosition.x, companionPosition.y);
      }
    });
    unawaited(AndroidWidgetService.refresh());
  }

  void _moveCompanion(Offset delta, Size viewport) {
    final travelWidth = math.max(1.0, viewport.width - 48);
    final bodyHeight = math.max(48.0, viewport.height - 56 - 80);
    final travelHeight = math.max(1.0, bodyHeight - 56);
    setState(() {
      _companionPosition = Offset(
        (_companionPosition.dx + delta.dx / travelWidth).clamp(0.0, 1.0),
        (_companionPosition.dy + delta.dy / travelHeight).clamp(0.02, 0.88),
      );
    });
  }

  Future<void> _snapAndSaveCompanion() async {
    final snapped = Offset(
      _companionPosition.dx < .5 ? 0 : 1,
      _companionPosition.dy,
    );
    setState(() => _companionPosition = snapped);
    await widget.taskService.setCompanionPosition(snapped.dx, snapped.dy);
  }

  double _companionTop(Size viewport) {
    final bodyHeight = math.max(48.0, viewport.height - 56 - 80);
    var top = 8 + _companionPosition.dy * math.max(1.0, bodyHeight - 56);
    if (_companionPosition.dx >= .5 && top > bodyHeight - 144) {
      top = bodyHeight - 144;
    }
    return top.clamp(8.0, math.max(8.0, bodyHeight - 56)).toDouble();
  }

  Future<void> refresh() => _loadAll();

  void _showError(String message) {
    if (!mounted) return;
    _showNotice(message);
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      );
  }

  int _collapseWriteVersion = 0;

  void _onArrangementCollapsedModesChanged(Set<String> modes) {
    final valid = modes.where(Task.arrangementModes.contains).toSet();
    setState(() => _arrangementCollapsedModes = valid);
    final version = ++_collapseWriteVersion;
    _arrangementCollapseWritePending = true;
    unawaited(() async {
      try {
        await widget.taskService.setArrangementCollapsedModes(valid);
      } catch (error) {
        if (mounted && version == _collapseWriteVersion) {
          _showError('安排分组状态保存失败：$error');
        }
      } finally {
        if (mounted && version == _collapseWriteVersion) {
          _arrangementCollapseWritePending = false;
        }
      }
    }());
  }

  Future<void> _softDelete(Task task, {String? source}) async {
    await _cancelReminder(task);
    await widget.taskService.softDeleteTask(
      task.id!,
      source: source ?? _currentActionScope,
    );
    _loadAll();
  }

  /// 安排视图删除确认：软删除，可在列表页回收站恢复
  Future<void> _confirmDeleteArranged(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('“${task.title}”将移入回收站，可在列表页恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _softDelete(task);
  }

  DateTime _dateInCurrentWeekFor(Task task) {
    final now = DateTime.now();
    final reference = task.dueDate ?? task.completedAt ?? task.deletedAt ?? now;
    return TaskService.dateInCurrentWeek(reference, now: now);
  }

  Future<void> _restore(Task task) async {
    var restored = task;
    if (task.deletedScope == Task.actionScopeWeek) {
      final day = _dateInCurrentWeekFor(task);
      await widget.taskService.moveToWeekDay(task, day);
      restored = task.copyWith(dueDate: day);
    } else if (task.deletedScope == Task.actionScopeInbox) {
      restored = task.copyWith(
        taskMode: Task.normalMode,
        clearDueDate: true,
        clearReminderTime: true,
      );
      await widget.taskService.updateTask(restored);
    }
    await widget.taskService.restoreTask(task.id!);
    if (!restored.isCompleted) await _scheduleReminder(restored);
    _loadAll();
  }

  Future<void> _restoreCompleted(Task task) async {
    await _cancelReminder(task);
    if (task.completedScope == Task.actionScopeWeek) {
      final day = _dateInCurrentWeekFor(task);
      await widget.taskService.updateTask(
        task.copyWith(
          dueDate: day,
          clearCompletedAt: true,
          clearCompletedScope: true,
        ),
      );
      await _scheduleReminder(
        task.copyWith(
          dueDate: day,
          clearCompletedAt: true,
          clearCompletedScope: true,
        ),
      );
    } else if (task.completedScope == Task.actionScopeStage) {
      await widget.taskService.setTaskCompleted(
        task,
        completed: false,
        source: Task.actionScopeStage,
      );
      await _scheduleReminder(task.copyWith(clearCompletedAt: true));
    } else {
      await widget.taskService.updateTask(
        task.copyWith(
          taskMode: Task.normalMode,
          clearDueDate: true,
          clearReminderTime: true,
          clearCompletedAt: true,
          clearCompletedScope: true,
        ),
      );
    }
    await _loadAll();
  }

  Future<void> _permDelete(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除任务？'),
        content: Text('“${task.title}”及其子任务将永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cancelReminder(task);
    await widget.taskService.permanentlyDeleteTask(task.id!);
    _loadAll();
  }

  void _toggleCardExpand(int taskId) async {
    if (_cardExpanded.contains(taskId)) {
      _cardExpanded.remove(taskId);
      if (mounted) setState(() {});
      return;
    }
    final roots = await widget.taskService.getRootSubTasks(taskId);
    if (!mounted) return;
    _cardExpanded.add(taskId);
    _cardSubTasks[taskId] = roots;
    _lastExpandedTaskId = taskId;
    _companionKey.currentState?.showState(CompanionState.checkTask);
    if (mounted) setState(() {});
  }

  /// Ctrl+T 快捷键：给最后展开的任务添加子任务
  Future<void> addSubTaskToLastExpanded() async {
    if (_lastExpandedTaskId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先在任务卡片上点 ▼ 展开子任务列表，再用 Ctrl+T'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final task = [..._activeUndone, ..._activeDone].firstWhere(
      (t) => t.id == _lastExpandedTaskId,
      orElse: () =>
          _activeUndone.isNotEmpty ? _activeUndone.first : _activeDone.first,
    );
    if (task.id != _lastExpandedTaskId) return; // 任务已被删除
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          '添加子任务到「${task.title.length > 15 ? '${task.title.substring(0, 15)}...' : task.title}」',
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '子任务名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(context, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(context, t);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await widget.taskService.insertSubTask(
      SubTask(taskId: _lastExpandedTaskId!, title: result, level: 0),
    );
    // 刷新展开的子任务列表
    final roots = await widget.taskService.getRootSubTasks(
      _lastExpandedTaskId!,
    );
    _cardSubTasks[_lastExpandedTaskId!] = roots;
    await widget.taskService.checkTaskCompletion(
      _lastExpandedTaskId!,
      source: _currentActionScope,
    );
    _loadAll();
  }

  Future<void> _toggleCardSubTask(SubTask st) async {
    Task? task;
    for (final item in [..._activeUndone, ..._activeDone]) {
      if (item.id == st.taskId) {
        task = item;
        break;
      }
    }
    if (task == null) return;
    await widget.taskService.toggleSubTaskForTask(
      task,
      st,
      source: _currentActionScope,
    );
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(
      st.taskId,
    );
    _loadAll();
  }

  Future<void> _moveCardSubTaskUp(SubTask st) async {
    await widget.taskService.moveSubTaskUp(st.id!);
    await widget.taskService.checkTaskCompletion(
      st.taskId,
      source: _currentActionScope,
    );
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(
      st.taskId,
    );
    if (mounted) setState(() {});
    _loadAll();
  }

  Future<void> _moveCardSubTaskDown(SubTask st) async {
    await widget.taskService.moveSubTaskDown(st.id!);
    await widget.taskService.checkTaskCompletion(
      st.taskId,
      source: _currentActionScope,
    );
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(
      st.taskId,
    );
    if (mounted) setState(() {});
    _loadAll();
  }

  Future<void> _deleteCardSubTask(SubTask st) async {
    if (st.isDeleted) {
      await widget.taskService.restoreSubTask(st.id!);
    } else {
      await widget.taskService.softDeleteSubTask(st.id!);
    }
    await widget.taskService.checkTaskCompletion(
      st.taskId,
      source: _currentActionScope,
    );
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(
      st.taskId,
    );
    if (mounted) setState(() {});
    _loadAll();
  }

  DateTime? _parseDate(String? s) =>
      s != null && s.isNotEmpty ? DateTime.parse(s) : null;

  Future<void> _scheduleReminder(Task task) async {
    if (task.reminderTime != null && task.dueDate != null) {
      final remindAt = DateTime(
        task.dueDate!.year,
        task.dueDate!.month,
        task.dueDate!.day,
        task.reminderTime!.hour,
        task.reminderTime!.minute,
      );
      if (remindAt.isAfter(DateTime.now())) {
        final scheduled = await widget.notificationService.scheduleReminder(
          id: task.id! + 10000,
          title: Platform.isAndroid ? '任务时间到了' : '📌 ${task.title}',
          body: Platform.isAndroid ? task.title : '截止日期到了',
          scheduledTime: remindAt,
          repeatType: task.repeatType,
          fullScreen: Platform.isAndroid,
          taskId: task.id,
        );
        if (!scheduled && mounted && !_reminderWarningShown) {
          _reminderWarningShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.notificationService.status.value.message),
            ),
          );
        } else if (scheduled &&
            mounted &&
            !_reminderWarningShown &&
            !(await widget.notificationService
                .isIgnoringBatteryOptimizations())) {
          // 排程成功但没进电池优化白名单：小米等 ROM 后台可能拦提醒，引导一次
          _reminderWarningShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('为保证锁屏/后台也能准时提醒，建议允许后台运行'),
              action: SnackBarAction(
                label: '去设置',
                onPressed: () => widget.notificationService
                    .requestIgnoreBatteryOptimizations(),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _cancelReminder(Task task) async {
    if (task.reminderTime == null) return;
    await widget.notificationService.cancelReminder(task.id! + 10000);
  }

  void focusSearch() {
    if (MediaQuery.sizeOf(context).width < 900) {
      unawaited(_showMobileFilterSheet(focusSearch: true));
      return;
    }
    if (!_searchVisible) setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  Future<void> focusInput() async {
    if (_displayMode == TodoDisplayMode.arrangement) {
      await showQuickAdd(taskMode: Task.planNowMode);
      return;
    }
    if (MediaQuery.sizeOf(context).width < 900) {
      await showAddDialog();
      return;
    }
    _quickInputFocus.requestFocus();
  }

  Future<SchedulePromptResult?> _promptForSchedule(
    String title, {
    DateTime? initialDueDate,
  }) {
    return showDialog<SchedulePromptResult>(
      context: context,
      builder: (_) =>
          SchedulePromptDialog(itemName: title, initialDueDate: initialDueDate),
    );
  }

  Future<void> showAddDialog({
    String? taskMode,
    DateTime? initialDueDate,
  }) async {
    final cats = _categoryNames.where((c) => c != '全部').toList();
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => AddTaskDialog(
        categories: cats.isEmpty ? ['默认'] : cats,
        showScheduleFields: false,
      ),
    );
    if (result != null) {
      final schedule = await _promptForSchedule(
        result['title']!,
        initialDueDate: initialDueDate ?? _defaultDueDateForView(),
      );
      if (schedule == null) return;
      final task = Task(
        title: result['title']!,
        note: result['note'] ?? '',
        category: result['category']!,
        dueDate: schedule.dueDate,
        reminderTime: schedule.reminderTime,
        repeatType: schedule.repeatType,
        effortPoints: int.tryParse(result['effort_points'] ?? '') ?? 2,
        taskMode:
            taskMode ??
            (_displayMode == TodoDisplayMode.arrangement
                ? Task.planNowMode
                : Task.normalMode),
      );
      final approved = await _applyWorkloadGuard(task);
      if (approved == null) return;
      final newId = await widget.taskService.insertTask(approved);
      final savedTask = approved.copyWith(
        id: newId,
        updatedAt: approved.updatedAt,
        revision: approved.revision,
      );
      await _scheduleReminder(savedTask);
      await _loadAll();
    }
  }

  Future<void> showQuickAdd({String? taskMode, DateTime? dueDate}) async {
    final controller = TextEditingController();
    final normalizedMode = Task.normalizeMode(taskMode);
    final targetLabel = dueDate == null
        ? Task.arrangementLabelForMode(normalizedMode)
        : _quickAddDateLabel(dueDate);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('添加到「$targetLabel」'),
        content: TextField(
          key: const Key('arrangement-quick-add-input'),
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '任务名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final text = value.trim();
            if (text.isNotEmpty) Navigator.pop(dialogContext, text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('arrangement-quick-add-submit'),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await widget.taskService.insertTask(
      Task(title: title, taskMode: normalizedMode, dueDate: dueDate),
    );
    await _loadAll();
    _showNotice('已添加到$targetLabel');
  }

  String _quickAddDateLabel(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return isToday
        ? '今天 · ${weekdays[date.weekday - 1]}'
        : weekdays[date.weekday - 1];
  }

  Future<Task?> _showEditDialog(Task task) async {
    final cats = _categoryNames.where((c) => c != '全部').toList();
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => AddTaskDialog(
        initialTitle: task.title,
        initialNote: task.note,
        initialCategory: task.category,
        initialDueDate: task.dueDate,
        initialReminderTime: task.reminderTime,
        initialRepeatType: task.repeatType,
        initialEffortPoints: task.effortPoints,
        categories: cats.isEmpty ? ['默认'] : cats,
      ),
    );
    if (result != null) {
      await _cancelReminder(task);
      final updated = task.copyWith(
        title: result['title']!,
        note: result['note'] ?? '',
        category: result['category']!,
        dueDate: _parseDate(result['due_date']),
        reminderTime: _parseDate(result['reminder_time']),
        clearDueDate: result['due_date'] == null,
        clearReminderTime: result['reminder_time'] == null,
        repeatType: result['repeat_type'],
        clearRepeatType: result['repeat_type'] == null,
        effortPoints:
            int.tryParse(result['effort_points'] ?? '') ?? task.effortPoints,
        clearCompanionStashedAt: task.companionStashedAt != null,
      );
      await widget.taskService.updateTask(updated);
      await _scheduleReminder(updated);
      await _loadAll();
      return updated;
    }
    return null;
  }

  void _openDetail(Task task) async {
    // 仅列表模式桌面用侧栏；安排模式一律进详情页（详情页提供分组切换）
    if (_displayMode == TodoDisplayMode.list &&
        MediaQuery.sizeOf(context).width >= 900) {
      setState(() => _selectedTask = task);
      return;
    }
    await _pushDetail(task);
  }

  Future<void> _pushDetail(Task task) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          task: task,
          taskService: widget.taskService,
          notificationService: widget.notificationService,
          onEditTask: _showEditDialog,
          actionScope: _currentActionScope,
        ),
      ),
    );
    _loadAll();
  }

  List<Task> _filterTasks(List<Task> tasks) {
    var result = tasks;
    if (_smartView == 'inbox') {
      result = result.where((task) => !task.isScheduled).toList();
    } else if (_smartView == 'arranged') {
      result = result.where((task) => task.isScheduled).toList();
    }
    return _applyCategoryAndSearch(result);
  }

  List<Task> _applyCategoryAndSearch(List<Task> tasks) {
    var result = tasks;
    if (_filter != '全部') {
      result = result.where((task) => task.category == _filter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result
          .where(
            (task) =>
                task.title.contains(_searchQuery) ||
                task.note.contains(_searchQuery),
          )
          .toList();
    }
    return result;
  }

  int _compareTaskEventNewestFirst(
    Task a,
    Task b,
    DateTime? Function(Task task) eventTime,
  ) {
    final aTime = eventTime(a);
    final bTime = eventTime(b);
    if (aTime == null && bTime != null) return 1;
    if (aTime != null && bTime == null) return -1;
    if (aTime != null && bTime != null) {
      final eventOrder = bTime.compareTo(aTime);
      if (eventOrder != 0) return eventOrder;
    }
    final updateOrder = b.updatedAt.compareTo(a.updatedAt);
    if (updateOrder != 0) return updateOrder;
    return (b.id ?? -1).compareTo(a.id ?? -1);
  }

  bool get _manualSortAllowed =>
      primaryPage == TodoPrimaryPage.inbox && _smartView == 'inbox';

  Future<void> _onTaskReorder(
    List<Task> visibleTasks,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reorderInProgress || oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= visibleTasks.length) return;
    if (newIndex < 0 || newIndex >= visibleTasks.length) return;
    final beforeIds = visibleTasks
        .map((task) => task.id)
        .whereType<int>()
        .toList(growable: false);
    final reordered = List<int>.from(beforeIds);
    final id = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, id);
    await _persistReorder(beforeIds, reordered);
  }

  Future<void> _persistReorder(List<int> beforeIds, List<int> afterIds) async {
    if (beforeIds.length < 2 || beforeIds.length != afterIds.length) return;
    _reorderInProgress = true;
    HapticFeedback.lightImpact();
    try {
      await widget.taskService.reorderTaskSubset(afterIds);
      await _loadAll();
      if (!mounted) return;
      _showNotice('顺序已更新');
    } catch (error) {
      await _loadAll();
      if (mounted) _showError('顺序更新失败，已恢复原顺序：$error');
    } finally {
      _reorderInProgress = false;
    }
  }

  // ── 批量操作 ──

  void _toggleSelectMode() => setState(() {
    _selectMode = !_selectMode;
    _selectedIds.clear();
  });

  void _toggleSelect(int id) => setState(() {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
  });

  Future<void> _toggleTaskComplete(Task task, {String? source}) async {
    if (task.isCompleted) {
      await _restoreCompleted(task);
      return;
    }
    await _cancelReminder(task);
    await widget.taskService.setTaskCompleted(
      task,
      completed: true,
      source: source ?? _currentActionScope,
    );
    _companionKey.currentState?.showState(CompanionState.celebrate);
    await _loadAll();
  }

  Future<void> _moveTaskToMode(Task task, String mode) async {
    final normalized = Task.normalizeMode(mode);
    await widget.taskService.setTaskMode(task, normalized);
    if (_selectedTask?.id == task.id) {
      _selectedTask = task.copyWith(
        taskMode: normalized,
        revision: task.revision + 1,
      );
    }
    await _loadAll();
    if (!mounted) return;
    _showNotice(
      normalized == Task.normalMode
          ? '已移回列表'
          : '已移到${Task.arrangementLabelForMode(normalized)}',
    );
  }

  Future<void> _syncTaskToToday(Task task) async {
    final now = DateTime.now();
    await _changeTaskDay(task, DateTime(now.year, now.month, now.day));
    if (mounted) _showNotice('已同步到今天');
  }

  Future<void> _changeTaskDay(Task task, DateTime day) async {
    if (task.isCompleted) return;
    if (task.dueDate != null &&
        task.dueDate!.year == day.year &&
        task.dueDate!.month == day.month &&
        task.dueDate!.day == day.day)
      return;
    await _cancelReminder(task);
    await widget.taskService.moveToWeekDay(task, day);
    await _scheduleReminder(task.copyWith(dueDate: day));
    await _loadAll();
  }

  bool _sameDate(DateTime? first, DateTime second) =>
      first != null &&
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  Future<T?> _showTaskChoice<T>({
    required String title,
    BuildContext? anchorContext,
    required List<
      ({T value, IconData icon, String label, String? subtitle, bool selected})
    >
    options,
  }) async {
    // Let the first-level popup finish closing before opening its child menu.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return null;
    if (Platform.isAndroid) {
      return await showModalBottomSheet<T>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded, size: 20),
              title: Text(title),
            ),
            for (final option in options)
              ListTile(
                minTileHeight: 48,
                leading: Icon(option.icon, size: 20),
                title: Text(option.label),
                subtitle: option.subtitle == null
                    ? null
                    : Text(option.subtitle!),
                trailing: option.selected
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option.value),
              ),
          ],
        ),
      );
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchor = anchorContext?.findRenderObject() as RenderBox?;
    final fallbackRect = Rect.fromLTWH(
      math.max(8, overlay.size.width - 280),
      64,
      48,
      48,
    );
    final candidateRect = anchor == null || !anchor.attached || !anchor.hasSize
        ? fallbackRect
        : Rect.fromPoints(
            anchor.localToGlobal(Offset.zero, ancestor: overlay),
            anchor.localToGlobal(
              anchor.size.bottomRight(Offset.zero),
              ancestor: overlay,
            ),
          );
    final rect =
        candidateRect.left >= 0 &&
            candidateRect.top >= 0 &&
            candidateRect.right <= overlay.size.width &&
            candidateRect.bottom <= overlay.size.height &&
            candidateRect.width <= overlay.size.width / 2
        ? candidateRect
        : fallbackRect;
    return await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        PopupMenuItem<T>(enabled: false, child: Text(title)),
        for (final option in options)
          PopupMenuItem<T>(
            value: option.value,
            child: Row(
              children: [
                Icon(option.icon, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label),
                      if (option.subtitle != null)
                        Text(
                          option.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (option.selected) const Icon(Icons.check, size: 20),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _chooseStageForTask(
    Task task, {
    required String title,
    BuildContext? anchorContext,
  }) async {
    final mode = await _showTaskChoice<String>(
      title: title,
      anchorContext: anchorContext,
      options: [
        for (final target in Task.arrangementModes)
          (
            value: target,
            icon: switch (target) {
              Task.planNowMode => Icons.bolt_outlined,
              Task.planNextMode => Icons.arrow_forward_rounded,
              _ => Icons.schedule_outlined,
            },
            label: Task.arrangementLabelForMode(target),
            subtitle: null,
            selected: Task.normalizeMode(task.taskMode) == target,
          ),
      ],
    );
    if (mode != null && Task.normalizeMode(task.taskMode) != mode) {
      await _moveTaskToMode(task, mode);
    }
  }

  Future<void> _chooseStageForWeekTask(Task task) =>
      _chooseStageForTask(task, title: '同步阶段');

  Future<void> _chooseStageForInboxTask(
    Task task, [
    BuildContext? anchorContext,
  ]) => _chooseStageForTask(task, title: '移到阶段', anchorContext: anchorContext);

  Future<void> _chooseWeekForTask(
    Task task, [
    BuildContext? anchorContext,
  ]) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final day = await _showTaskChoice<DateTime>(
      title: '移到本周',
      anchorContext: anchorContext,
      options: [
        for (var index = 0; index < 7; index++)
          (
            value: monday.add(Duration(days: index)),
            icon: Icons.calendar_today_outlined,
            label: labels[index],
            subtitle:
                '${monday.add(Duration(days: index)).month}月${monday.add(Duration(days: index)).day}日${monday.add(Duration(days: index)) == today ? ' · 今天' : ''}',
            selected: _sameDate(
              task.dueDate,
              monday.add(Duration(days: index)),
            ),
          ),
      ],
    );
    if (day != null) await _changeTaskDay(task, day);
  }

  Future<void> _reorderWeekDay(DateTime day, int oldIndex, int newIndex) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tasks =
        [..._activeUndone, ..._activeDone]
            .where(
              (task) =>
                  task.dueDate != null &&
                  task.dueDate!.year == day.year &&
                  task.dueDate!.month == day.month &&
                  task.dueDate!.day == day.day &&
                  (day.isBefore(today) || !task.isCompleted),
            )
            .toList()
          ..sort((a, b) => a.weekSortOrder.compareTo(b.weekSortOrder));
    if (oldIndex < 0 ||
        oldIndex >= tasks.length ||
        newIndex < 0 ||
        newIndex >= tasks.length ||
        oldIndex == newIndex)
      return;
    final ids = tasks.map((task) => task.id!).toList();
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    await widget.taskService.reorderWeekDay(day, ids);
    await _loadAll();
  }

  Future<void> _reorderArrangement(
    String mode,
    int oldIndex,
    int newIndex,
  ) async {
    final tasks = _arrangedUndoneForMode(mode);
    if (oldIndex < 0 || oldIndex >= tasks.length) return;
    if (newIndex < 0 || newIndex >= tasks.length) return;
    final beforeIds = tasks
        .map((task) => task.id)
        .whereType<int>()
        .toList(growable: false);
    final reordered = List<int>.from(beforeIds);
    final task = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, task);
    await _persistReorder(beforeIds, reordered);
  }

  List<Task> _arrangedUndoneForMode(String mode) {
    final normalized = Task.normalizeMode(mode);
    return _activeUndone
        .where(
          (task) =>
              task.isArranged &&
              Task.normalizeMode(task.taskMode) == normalized,
        )
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  List<Task> _arrangedDoneForMode(String mode) {
    final normalized = Task.normalizeMode(mode);
    return _activeDone
        .where(
          (task) =>
              task.isArranged &&
              Task.normalizeMode(task.taskMode) == normalized,
        )
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  DateTime? _defaultDueDateForView() {
    final now = DateTime.now();
    if (_smartView == 'today') return DateTime(now.year, now.month, now.day);
    if (_smartView == 'next7') {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }
    return null;
  }

  bool _isToday(DateTime? value) {
    if (value == null) return false;
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  bool get _hasUpcomingReminder {
    final now = DateTime.now();
    return _activeUndone.any((task) {
      final dueDate = task.dueDate;
      final reminderTime = task.reminderTime;
      if (dueDate == null || reminderTime == null) return false;
      final reminder = DateTime(
        dueDate.year,
        dueDate.month,
        dueDate.day,
        reminderTime.hour,
        reminderTime.minute,
      );
      final remaining = reminder.difference(now);
      return !remaining.isNegative && remaining <= const Duration(hours: 1);
    });
  }

  Future<Task?> _applyWorkloadGuard(Task task) async {
    final dueToday = _isToday(task.dueDate);
    final wouldExceedToday =
        dueToday && _todayEffort + task.effortPoints > _dailyEffortLimit;
    final creatingAfterFull =
        task.dueDate == null && _todayEffort >= _dailyEffortLimit;
    if (!wouldExceedToday && !creatingAfterFull) {
      return task;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('今日负荷已满'),
        content: Text(
          dueToday
              ? '当前 $_todayEffort/$_dailyEffortLimit，加入后为 '
                    '${_todayEffort + task.effortPoints}/$_dailyEffortLimit。可改到明天，或仍然创建。'
              : '今天已经达到 $_todayEffort/$_dailyEffortLimit。可改到明天，或仍然创建。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'tomorrow'),
            child: const Text('改到明天'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            child: const Text('仍然创建'),
          ),
        ],
      ),
    );
    if (choice == 'continue') return task;
    if (choice == 'tomorrow') {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      return task.copyWith(
        dueDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
      );
    }
    return null;
  }

  Future<void> _batchComplete() async {
    for (final id in _selectedIds.toList()) {
      final task = _activeUndone.firstWhere((t) => t.id == id);
      await widget.taskService.updateTask(
        task.copyWith(
          completedAt: DateTime.now(),
          completedScope: Task.actionScopeInbox,
        ),
      );
    }
    _selectedIds.clear();
    _selectMode = false;
    await _loadAll();
  }

  Future<void> _batchDelete() async {
    await widget.taskService.softDeleteTasks(
      _selectedIds,
      source: Task.actionScopeInbox,
    );
    _selectedIds.clear();
    _selectMode = false;
    await _loadAll();
  }

  Future<void> _clearCompletedTasks(
    List<Task> tasks, {
    required String label,
  }) async {
    if (tasks.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('清空$label'),
        content: Text('将 ${tasks.length} 项已完成任务移入最近删除，之后可手动恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.taskService.softDeleteTasks(
      tasks.map((task) => task.id!).toList(growable: false),
      source: _currentActionScope,
    );
    await _loadAll();
  }

  Future<void> _showCategoryManager() async {
    final TextEditingController nameCtrl = TextEditingController();

    Future<void> refreshCats() async {
      final cats = await widget.taskService.getCategories();
      if (mounted) setState(() => _categories = cats);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '管理分类',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _categories.length,
                      itemBuilder: (_, i) {
                        final cat = _categories[i];
                        final name = cat['name'] as String;
                        final color = Color(
                          int.parse(
                            (cat['color'] as String).replaceFirst('#', '0xFF'),
                          ),
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color,
                            radius: 14,
                          ),
                          title: Text(name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (name != '默认')
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () async {
                                    nameCtrl.text = name;
                                    final result =
                                        await showDialog<Map<String, String>>(
                                          context: ctx,
                                          builder: (_) => AlertDialog(
                                            title: const Text('编辑分类'),
                                            content: TextField(
                                              controller: nameCtrl,
                                              decoration: const InputDecoration(
                                                hintText: '分类名称',
                                                border: OutlineInputBorder(),
                                              ),
                                              autofocus: true,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text('取消'),
                                              ),
                                              FilledButton(
                                                onPressed: () {
                                                  final n = nameCtrl.text
                                                      .trim();
                                                  if (n.isEmpty) return;
                                                  Navigator.pop(ctx, {
                                                    'name': n,
                                                  });
                                                },
                                                child: const Text('保存'),
                                              ),
                                            ],
                                          ),
                                        );
                                    if (result != null) {
                                      await widget.taskService.updateCategory(
                                        cat['id'] as int,
                                        result['name']!,
                                        cat['color'] as String,
                                      );
                                      if (_filter == name)
                                        _filter = result['name']!;
                                      await refreshCats();
                                      setSheetState(() {});
                                    }
                                  },
                                ),
                              if (name != '默认')
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    await widget.taskService.deleteCategory(
                                      cat['id'] as int,
                                    );
                                    if (_filter == name) _filter = '全部';
                                    await refreshCats();
                                    setSheetState(() {});
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            hintText: '新分类名称',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          final hash =
                              name.codeUnits.fold<int>(0, (s, c) => s + c) % 12;
                          const palette = [
                            '#607D8B',
                            '#2196F3',
                            '#4CAF50',
                            '#FF9800',
                            '#F44336',
                            '#9C27B0',
                            '#009688',
                            '#3F51B5',
                            '#FFC107',
                            '#00BCD4',
                            '#E91E63',
                            '#795548',
                          ];
                          await widget.taskService.addCategory(
                            name,
                            palette[hash],
                          );
                          nameCtrl.clear();
                          await refreshCats();
                          setSheetState(() {});
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    _loadAll();
  }

  Future<void> _showEffortLimitDialog() async {
    var value = _dailyEffortLimit.toDouble();
    final saved = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('今日心力上限'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.round()} 点',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Slider(
                value: value,
                min: 3,
                max: 20,
                divisions: 17,
                label: value.round().toString(),
                onChanged: (next) => setDialogState(() => value = next),
              ),
              const Text('超出上限时会提示改到明天，也可以仍然创建。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, value.round()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await widget.taskService.setDailyEffortLimit(saved);
    _loadAll();
  }

  Widget _buildSidePanel(Task task) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭详情',
                onPressed: () => setState(() => _selectedTask = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(task.category)),
              Chip(label: Text('心力 ${task.effortPoints}')),
              if (task.dueDate != null)
                Chip(label: Text(fmtDateTime(task.dueDate, task.reminderTime))),
            ],
          ),
          if (task.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(task.note),
          ],
          const SizedBox(height: 20),
          Text('关联备忘录', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          FutureBuilder(
            future: widget.taskMemoService.getMemosForTask(task.id!),
            builder: (_, snapshot) {
              final memos = snapshot.data ?? const [];
              if (memos.isEmpty)
                return const Text('暂无关联', style: TextStyle(color: Colors.grey));
              return Column(
                children: memos
                    .map(
                      (memo) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.note_outlined, size: 18),
                        title: Text(
                          memo.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _pushDetail(task),
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开完整详情'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showEditDialog(task),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑任务'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    int count,
    bool expanded,
    VoidCallback toggle, {
    Color color = Colors.indigo,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
            const Spacer(),
            if (onClear != null)
              IconButton(
                key: Key('clear-$title'),
                tooltip: '清空$title',
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  String _smartViewLabel() {
    return switch (_smartView) {
      'active' => '未完成',
      'arranged' => '已安排',
      'completed' => '已完成',
      'deleted' => '最近删除',
      _ => '收件箱',
    };
  }

  String _currentFilterLabel() {
    final labels = <String>[_smartViewLabel()];
    if (_filter != '全部') labels.add(_filter);
    if (_searchQuery.isNotEmpty) labels.add('搜索');
    return labels.join(' · ');
  }

  Widget _buildSmartViews(BuildContext context, {VoidCallback? onChanged}) {
    final colors = Theme.of(context).colorScheme;
    final views = primaryPage == TodoPrimaryPage.inbox
        ? [
            (key: 'inbox', label: '收件箱', icon: Icons.inbox_outlined),
            (key: 'arranged', label: '已安排', icon: Icons.event_note_outlined),
            (key: 'completed', label: '已完成', icon: Icons.check_circle_outline),
            (key: 'deleted', label: '最近删除', icon: Icons.delete_outline),
          ]
        : [
            (key: 'active', label: '未完成', icon: Icons.pending_actions),
            (key: 'completed', label: '已完成', icon: Icons.check_circle_outline),
            (key: 'deleted', label: '最近删除', icon: Icons.delete_outline),
          ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: views.map((view) {
            final selected = _smartView == view.key;
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Material(
                color: selected
                    ? colors.surfaceContainerLowest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  onTap: () {
                    setState(() => _smartView = view.key);
                    _savePageState();
                    onChanged?.call();
                  },
                  borderRadius: BorderRadius.circular(11),
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          view.icon,
                          size: 17,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          view.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _categoryColor(String label, Color fallback) {
    if (label == '全部') return fallback;
    for (final category in _categories) {
      if (category['name'] != label) continue;
      final raw = category['color'] as String?;
      if (raw == null) return fallback;
      return Color(
        int.tryParse(raw.replaceFirst('#', '0xFF')) ?? fallback.toARGB32(),
      );
    }
    return fallback;
  }

  Widget _buildCategoryFilters(
    BuildContext context, {
    VoidCallback? onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final label in _categoryNames)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Material(
                color: _filter == label
                    ? colors.primaryContainer.withAlpha(150)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () {
                    setState(() => _filter = label);
                    onChanged?.call();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _categoryColor(label, colors.primary),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _filter == label
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '管理分类',
            onPressed: _showCategoryManager,
            icon: const Icon(Icons.tune_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showCompanion = MediaQuery.sizeOf(context).width >= 900;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 650;
        return Container(
          margin: EdgeInsets.fromLTRB(
            wide ? 12 : 8,
            wide ? 10 : 6,
            wide ? 12 : 8,
            4,
          ),
          padding: EdgeInsets.all(wide ? 10 : 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(wide ? 18 : 14),
            border: Border.all(color: colors.outlineVariant.withAlpha(100)),
          ),
          child: Builder(
            builder: (context) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showCompanion)
                    Row(
                      children: [
                        Expanded(child: _buildSmartViews(context)),
                        const SizedBox(width: 10),
                        WorkloadCompanion(
                          key: _companionKey,
                          current: _todayEffort,
                          limit: _dailyEffortLimit,
                          reminderActive: _hasUpcomingReminder,
                          onTap: _showEffortLimitDialog,
                        ),
                      ],
                    )
                  else
                    _buildSmartViews(context),
                  SizedBox(height: wide ? 8 : 5),
                  _buildCategoryFilters(context),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showMobileFilterSheet({bool focusSearch = false}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, sheetSetState) {
          void refreshSheet() => sheetSetState(() {});
          final totalSubtasks = [..._activeUndone, ..._activeDone].fold<int>(
            0,
            (sum, task) => sum + (_progress[task.id!]?.total ?? 0),
          );
          final doneSubtasks = [
            ..._activeUndone,
            ..._activeDone,
          ].fold<int>(0, (sum, task) => sum + (_progress[task.id!]?.done ?? 0));
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '筛选与统计',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (primaryPage == TodoPrimaryPage.inbox &&
                          _smartView == 'inbox')
                        TextButton.icon(
                          key: const Key('todo-mobile-select-button'),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _toggleSelectMode();
                          },
                          icon: const Icon(Icons.select_all_rounded, size: 20),
                          label: Text(_selectMode ? '取消选择' : '选择'),
                        ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  TextField(
                    autofocus: focusSearch,
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: '搜索任务',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                refreshSheet();
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      refreshSheet();
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '智能视图',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildSmartViews(context, onChanged: refreshSheet),
                  const SizedBox(height: 14),
                  Text(
                    '分类',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildCategoryFilters(context, onChanged: refreshSheet),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('$doneSubtasks/$totalSubtasks 项完成'),
                          ),
                          Text('今日负荷 $_todayEffort/$_dailyEffortLimit'),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _smartView = primaryPage == TodoPrimaryPage.inbox
                              ? 'inbox'
                              : 'active';
                          _filter = '全部';
                          _searchQuery = '';
                        });
                        refreshSheet();
                      },
                      child: const Text('重置筛选'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewSwitcher(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 900) {
      final colors = Theme.of(context).colorScheme;
      return Container(
        key: const Key('todo-mobile-toolbar'),
        height: 56,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: const Key('todo-mobile-filter-button'),
                  onTap: _showMobileFilterSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _currentFilterLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final isCompact = viewport.width < 900;
    final filteredUndone =
        _displayMode == TodoDisplayMode.list &&
            const {'inbox', 'arranged'}.contains(_smartView)
        ? _filterTasks(_activeUndone)
        : const <Task>[];
    final filteredDone = _smartView == 'completed'
        ? (_applyCategoryAndSearch(
            _activeDone
                .where((task) => task.completedScope == _currentActionScope)
                .toList(),
          )..sort(
            (a, b) =>
                _compareTaskEventNewestFirst(a, b, (task) => task.completedAt),
          ))
        : const <Task>[];
    final filteredDeleted = _smartView == 'deleted'
        ? (_applyCategoryAndSearch(
            _deleted
                .where((task) => task.deletedScope == _currentActionScope)
                .toList(),
          )..sort(
            (a, b) =>
                _compareTaskEventNewestFirst(a, b, (task) => task.deletedAt),
          ))
        : const <Task>[];
    final showArrangementBoard =
        _displayMode == TodoDisplayMode.arrangement && _smartView == 'active';
    final nowTasks = _arrangedUndoneForMode(Task.planNowMode);
    final nextTasks = _arrangedUndoneForMode(Task.planNextMode);
    final laterTasks = _arrangedUndoneForMode(Task.planLaterMode);
    final doneNowTasks = _arrangedDoneForMode(Task.planNowMode);
    final doneNextTasks = _arrangedDoneForMode(Task.planNextMode);
    final doneLaterTasks = _arrangedDoneForMode(Task.planLaterMode);
    final totalSubtasks = [
      ..._activeUndone,
      ..._activeDone,
      ..._deleted,
    ].fold<int>(0, (s, t) => s + (_progress[t.id!]?.total ?? 0));
    final doneSubtasks = [
      ..._activeUndone,
      ..._activeDone,
      ..._deleted,
    ].fold<int>(0, (s, t) => s + (_progress[t.id!]?.done ?? 0));

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    if (!(isCompact && showArrangementBoard))
                      _buildViewSwitcher(context),
                    if (!isCompact) _buildFilterHeader(context),
                    // 搜索（滚回顶部时出现）
                    if (!isCompact)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: _searchVisible
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocus,
                                  decoration: InputDecoration(
                                    hintText: '搜索任务...',
                                    isDense: true,
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 20,
                                    ),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.clear,
                                              size: 18,
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => _searchQuery = v),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    // 统计
                    if (_displayMode == TodoDisplayMode.list && !isCompact)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text(
                              '$doneSubtasks/$totalSubtasks 项完成',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: _toggleSelectMode,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _selectMode
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _selectMode ? '取消' : '多选',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_displayMode == TodoDisplayMode.list && !isCompact)
                      const SizedBox(height: 4),
                    // 主体
                    Expanded(
                      child: showArrangementBoard
                          ? TaskArrangementView(
                              nowTasks: nowTasks,
                              nextTasks: nextTasks,
                              laterTasks: laterTasks,
                              doneNowTasks: doneNowTasks,
                              doneNextTasks: doneNextTasks,
                              doneLaterTasks: doneLaterTasks,
                              unplannedTasks: const [],
                              onToggleTask: (task) => _toggleTaskComplete(
                                task,
                                source: _currentActionScope,
                              ),
                              onOpenTask: _openDetail,
                              onMoveTask: _moveTaskToMode,
                              onEditTask: _showEditDialog,
                              onDeleteTask: _confirmDeleteArranged,
                              onAddTask: (mode) => showQuickAdd(taskMode: mode),
                              allUndoneTasks: _activeUndone,
                              allTasks: [
                                ..._activeUndone,
                                ..._activeDone.where(
                                  (task) =>
                                      task.completedScope ==
                                      Task.actionScopeWeek,
                                ),
                              ],
                              onAddWeeklyTask: (date) =>
                                  showQuickAdd(dueDate: date),
                              onReorder: _reorderArrangement,
                              onReorderWeekDay: _reorderWeekDay,
                              onMoveToWeekDay: _changeTaskDay,
                              onSyncStage: _chooseStageForWeekTask,
                              onSyncToday: _syncTaskToToday,
                              statusLabel: _currentFilterLabel(),
                              onOpenStatusFilter: _showMobileFilterSheet,
                              initialMode: _arrangementViewMode,
                              showSwitcher: false,
                              onModeChanged: (mode) {
                                _arrangementViewMode = mode;
                                _savePageState();
                              },
                              collapsedModes: _arrangementCollapsedModes,
                              onCollapsedModesChanged:
                                  _onArrangementCollapsedModesChanged,
                            )
                          : filteredUndone.isEmpty &&
                                filteredDone.isEmpty &&
                                filteredDeleted.isEmpty
                          ? Center(
                              child: Text(
                                '还没有任务，点右下角创建',
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            )
                          : ListView(
                              controller: _scrollController,
                              children: [
                                // ── 未完成（长按拖拽排序）──
                                if (filteredUndone.isNotEmpty)
                                  ReorderableListView(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    buildDefaultDragHandles:
                                        !isCompact && _manualSortAllowed,
                                    onReorderItem: (oldIndex, newIndex) =>
                                        _onTaskReorder(
                                          filteredUndone,
                                          oldIndex,
                                          newIndex,
                                        ),
                                    children: filteredUndone
                                        .asMap()
                                        .entries
                                        .map((e) {
                                          final i = e.key;
                                          final task = e.value;
                                          final p =
                                              _progress[task.id!] ??
                                              (total: 0, done: 0);
                                          return TaskItem(
                                            key: ValueKey(task.id),
                                            task: task,
                                            doneCount: p.done,
                                            totalCount: p.total,
                                            selectMode: _selectMode,
                                            isSelected: _selectedIds.contains(
                                              task.id,
                                            ),
                                            onSelectToggle: () =>
                                                _toggleSelect(task.id!),
                                            onComplete: () =>
                                                _toggleTaskComplete(task),
                                            onTap: () => _openDetail(task),
                                            onDelete: () => _softDelete(
                                              task,
                                              source: Task.actionScopeInbox,
                                            ),
                                            onEdit: () => _showEditDialog(task),
                                            onMoveToMode: (mode) =>
                                                _moveTaskToMode(task, mode),
                                            onMoveToStage: (anchorContext) =>
                                                _chooseStageForInboxTask(
                                                  task,
                                                  anchorContext,
                                                ),
                                            onMoveToWeek: (anchorContext) =>
                                                _chooseWeekForTask(
                                                  task,
                                                  anchorContext,
                                                ),
                                            managementOnly:
                                                _smartView == 'arranged',
                                            reorderable: _manualSortAllowed,
                                            reorderIndex: i,
                                            isExpanded: _cardExpanded.contains(
                                              task.id,
                                            ),
                                            onToggleExpand: () =>
                                                _toggleCardExpand(task.id!),
                                            subTasks:
                                                _cardSubTasks[task.id] ?? [],
                                            onToggleSubTask: (st) =>
                                                _toggleCardSubTask(st),
                                            onDeleteSubTask: (st) =>
                                                _deleteCardSubTask(st),
                                            onMoveSubTaskUp: (st) =>
                                                _moveCardSubTaskUp(st),
                                            onMoveSubTaskDown: (st) =>
                                                _moveCardSubTaskDown(st),
                                          );
                                        })
                                        .toList(),
                                  ),
                                // ── 已完成 ──
                                if (filteredDone.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _sectionHeader(
                                    '已完成',
                                    filteredDone.length,
                                    _showCompleted,
                                    () => setState(
                                      () => _showCompleted = !_showCompleted,
                                    ),
                                    color: Colors.green,
                                    onClear: () => _clearCompletedTasks(
                                      filteredDone,
                                      label: '列表已完成任务',
                                    ),
                                  ),
                                  if (_showCompleted)
                                    ...filteredDone.map((task) {
                                      final p =
                                          _progress[task.id!] ??
                                          (total: 0, done: 0);
                                      return TaskItem(
                                        task: task,
                                        doneCount: p.done,
                                        totalCount: p.total,
                                        onTap: () => _openDetail(task),
                                        onDelete: () => _softDelete(
                                          task,
                                          source: _currentActionScope,
                                        ),
                                        onEdit: () => _showEditDialog(task),
                                        onComplete: () =>
                                            _restoreCompleted(task),
                                        isExpanded: _cardExpanded.contains(
                                          task.id,
                                        ),
                                        onToggleExpand: () =>
                                            _toggleCardExpand(task.id!),
                                        subTasks: _cardSubTasks[task.id] ?? [],
                                        onToggleSubTask: (st) =>
                                            _toggleCardSubTask(st),
                                        onDeleteSubTask: (st) =>
                                            _deleteCardSubTask(st),
                                        onMoveSubTaskUp: (st) =>
                                            _moveCardSubTaskUp(st),
                                        onMoveSubTaskDown: (st) =>
                                            _moveCardSubTaskDown(st),
                                      );
                                    }),
                                ],
                                // ── 最近删除 ──
                                if (filteredDeleted.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _sectionHeader(
                                    '最近删除',
                                    filteredDeleted.length,
                                    _showDeleted,
                                    () => setState(
                                      () => _showDeleted = !_showDeleted,
                                    ),
                                    color: Colors.red,
                                  ),
                                  if (_showDeleted)
                                    ...filteredDeleted.map((task) {
                                      return DeletedTaskCard(
                                        task: task,
                                        onRestore: () => _restore(task),
                                        onPermanentDelete: () =>
                                            _permDelete(task),
                                      );
                                    }),
                                ],
                              ],
                            ),
                    ),
                    // ── 批量操作栏 ──
                    if (_displayMode == TodoDisplayMode.list &&
                        _selectMode &&
                        _selectedIds.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: const Offset(0, -1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Text(
                              '已选 ${_selectedIds.length} 项',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              key: const Key('todo-selection-cancel'),
                              tooltip: '取消多选',
                              onPressed: _toggleSelectMode,
                              icon: const Icon(Icons.close),
                            ),
                            TextButton.icon(
                              onPressed: _batchComplete,
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: const Text('完成'),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              key: const Key('todo-selection-more'),
                              tooltip: '更多批量操作',
                              iconSize: 22,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onSelected: (value) {
                                if (value == 'delete') _batchDelete();
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除所选任务'),
                                ),
                              ],
                              icon: const Icon(Icons.more_vert),
                            ),
                          ],
                        ),
                      ),
                    // 桌面端保留快速输入；手机端由右下角按钮按需打开。
                    if (_displayMode == TodoDisplayMode.list && !isCompact)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: const Offset(0, -1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _quickInputController,
                                focusNode: _quickInputFocus,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  hintText: '输入标题，按 Enter 快速创建...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                onSubmitted: (_) => _quickCreate(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _quickCreate,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_displayMode == TodoDisplayMode.list &&
                  _selectedTask != null &&
                  MediaQuery.sizeOf(context).width >= 900)
                _buildSidePanel(_selectedTask!),
            ],
          ),
          if (isCompact)
            Positioned(
              left: _companionPosition.dx < .5
                  ? 0
                  : math.max(0, viewport.width - 48),
              top: _companionTop(viewport),
              child: WorkloadCompanion(
                key: _companionKey,
                current: _todayEffort,
                limit: _dailyEffortLimit,
                edgePeek: true,
                peekFromLeft: _companionPosition.dx < .5,
                onDragUpdate: (delta) => _moveCompanion(delta, viewport),
                onDragEnd: _snapAndSaveCompanion,
                reminderActive: _hasUpcomingReminder,
                onTap: _showEffortLimitDialog,
              ),
            ),
        ],
      ),
    );
  }
}
