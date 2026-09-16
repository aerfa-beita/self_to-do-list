import 'package:flutter/material.dart';
import '../models/memo.dart';
import '../models/task.dart';
import '../services/memo_service.dart';
import '../services/notification_service.dart';
import '../services/task_memo_service.dart';
import '../services/task_service.dart';
import '../widgets/memo_item.dart';
import '../widgets/memo_detail_panel.dart';
import '../widgets/schedule_prompt_dialog.dart';

/// 备忘录页——树形嵌套 + 快速记录
class MemoScreen extends StatefulWidget {
  final MemoService memoService;
  final NotificationService notificationService;
  final TaskMemoService taskMemoService;
  final TaskService taskService;
  final ValueChanged<String>? onSectionChanged;

  const MemoScreen({
    super.key,
    required this.memoService,
    required this.notificationService,
    required this.taskMemoService,
    required this.taskService,
    this.onSectionChanged,
  });

  @override
  State<MemoScreen> createState() => MemoScreenState();
}

class MemoScreenState extends State<MemoScreen> {
  List<Memo> _roots = [];
  final Map<int, List<Memo>> _children = {};
  final Set<int> _expanded = {};
  List<Memo> _deleted = [];
  bool _showDeleted = false;
  String _filter = '全部';
  String _searchQuery = '';
  List<Map<String, dynamic>> _categories = [];
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchVisible = false;
  double _lastScrollOffset = 0;
  // 批量选择
  bool _selectMode = false;
  final Set<int> _selectedIds = {};
  bool _showArchivedView = false;
  Memo? _selectedMemo;
  // 提醒引导：每进程只提示一次（失败或白名单引导）
  bool _reminderWarningShown = false;

  void _setFilter(String value) {
    setState(() => _filter = value);
    widget.onSectionChanged?.call(value == '全部' ? '全部备忘' : value);
  }

  @override
  void initState() {
    super.initState();
    _loadRoots();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    // 滚回顶部（offset 从 >0 变到 <=0）→ 显示搜索框
    if (offset <= 0 && _lastScrollOffset > 0 && !_searchVisible) {
      setState(() => _searchVisible = true);
    }
    // 向下滚出一定距离 → 隐藏搜索框
    if (offset > 100 && _searchVisible) {
      setState(() => _searchVisible = false);
    }
    _lastScrollOffset = offset;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void focusSearch() {
    if (!_searchVisible) setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  Future<void> focusInput() async {
    if (MediaQuery.sizeOf(context).width < 900) {
      await showAddDialog();
      return;
    }
    _inputFocus.requestFocus();
  }

  Future<void> _loadRoots() async {
    final roots = _showArchivedView
        ? await widget.memoService.getArchived()
        : await widget.memoService.getRoots();
    final deleted = await widget.memoService.getDeleted();
    final cats = await widget.memoService.getCategories();
    if (mounted)
      setState(() {
        _roots = roots;
        _deleted = deleted;
        _categories = cats;
      });
  }

  Future<void> refresh() => _loadRoots();

  Future<void> _togglePin(Memo memo) async {
    await widget.memoService.setPinned(memo.id!, !memo.isPinned);
    _loadRoots();
  }

  Future<void> _toggleArchive(Memo memo) async {
    await widget.memoService.setArchived(memo.id!, !memo.isArchived);
    _expanded.remove(memo.id);
    _children.remove(memo.id);
    _loadRoots();
  }

  Future<void> _convertToTodo(Memo memo) async {
    final subtree = await widget.taskMemoService.collectSubtree(memo);
    final subCount = subtree.length - 1;
    await widget.taskMemoService.createTaskFromMemo(memo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          subCount > 0
              ? '已生成 1 个 Todo 及 $subCount 个子任务，并保留双向关联'
              : '已生成 1 个 Todo，并保留双向关联',
        ),
      ),
    );
  }

  Future<void> _generateTodos(Memo memo) async {
    final subtree = await widget.taskMemoService.collectSubtree(memo);
    final hasChildren = subtree.length > 1;
    final subCount = subtree.length - 1;
    final titles = hasChildren
        ? <String>[]
        : TaskMemoService.extractTaskTitles(memo.content);
    if (titles.isEmpty && !hasChildren) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          hasChildren ? '整体转成 Todo + 子任务树' : '生成 ${titles.length} 个 Todo',
        ),
        content: SizedBox(
          width: 420,
          child: hasChildren
              ? Text('该备忘录含 $subCount 个子备忘录，将整体转成 1 个 Todo + 子任务树，不再按行拆分。')
              : ListView(
                  shrinkWrap: true,
                  children: titles
                      .map(
                        (title) => ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.check_box_outline_blank,
                            size: 18,
                          ),
                          title: Text(title),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final tasks = await widget.taskMemoService.createTasksFromMemo(memo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已生成 ${tasks.length} 个 Todo，并全部关联当前备忘录')),
    );
  }

  Future<void> _linkExistingTodo(Memo memo) async {
    final tasks = (await widget.taskService.getActiveTasks())
        .where((task) => !task.isCompleted && !task.isDeleted)
        .toList();
    if (!mounted) return;
    final taskId = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('关联已有 Todo'),
        content: SizedBox(
          width: 440,
          height: 360,
          child: tasks.isEmpty
              ? const Center(child: Text('暂无可关联的未完成任务'))
              : ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (_, index) {
                    final task = tasks[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      title: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(task.category),
                      onTap: () => Navigator.pop(context, task.id),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (taskId == null) return;
    final subtree = await widget.taskMemoService.collectSubtree(memo);
    final subCount = subtree.length - 1;
    await widget.taskMemoService.linkTaskToMemo(taskId, memo.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          subCount > 0 ? 'Todo 与备忘录及 $subCount 个子备忘录已关联' : 'Todo 与备忘录已关联',
        ),
      ),
    );
  }

  Future<void> _saveMemoDetails(Memo memo, MemoEditValue value) async {
    final current = await widget.memoService.getById(memo.id!) ?? memo;
    await _cancelMemoReminder(current);
    final updated = current.copyWith(
      content: value.content,
      category: value.category,
      dueDate: value.dueDate,
      reminderTime: value.reminderTime,
      clearDueDate: value.dueDate == null,
      clearReminderTime: value.reminderTime == null,
      repeatType: value.repeatType,
      clearRepeatType: value.repeatType == null,
      updatedAt: DateTime.now(),
    );
    await widget.memoService.update(updated);
    await _scheduleMemoReminder(updated);
    if (!mounted) return;
    setState(() => _selectedMemo = updated);
    await _loadRoots();
    if (memo.parentId != null) await _loadChildren(memo.parentId!);
  }

  Future<void> _toggleLinkedTask(Task task) async {
    await widget.taskService.updateTask(
      task.copyWith(
        completedAt: task.isCompleted ? null : DateTime.now(),
        clearCompletedAt: task.isCompleted,
      ),
    );
  }

  Widget _memoDetailPanel(
    Memo memo, {
    required VoidCallback onClose,
    bool compact = false,
  }) {
    return MemoDetailPanel(
      memo: memo,
      compact: compact,
      categories: _categoryNames.where((category) => category != '全部').toList(),
      loadLinkedTasks: () => widget.taskMemoService.getTasksForMemo(memo.id!),
      onSave: (value) => _saveMemoDetails(memo, value),
      onClose: onClose,
      onTogglePin: () async {
        await _togglePin(memo);
        final refreshed = await widget.memoService.getById(memo.id!);
        if (mounted && refreshed != null) {
          setState(() => _selectedMemo = refreshed);
        }
      },
      onToggleArchive: () async {
        await _toggleArchive(memo);
        if (mounted) setState(() => _selectedMemo = null);
        onClose();
      },
      onCreateTodo: () => _convertToTodo(memo),
      onGenerateTodos: () => _generateTodos(memo),
      onLinkTodo: () => _linkExistingTodo(memo),
      onToggleTask: _toggleLinkedTask,
    );
  }

  Future<void> _openMemo(Memo memo) async {
    if (MediaQuery.sizeOf(context).width >= 900) {
      setState(() => _selectedMemo = memo);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => Scaffold(
          body: _memoDetailPanel(
            memo,
            compact: true,
            onClose: () => Navigator.pop(routeContext),
          ),
        ),
      ),
    );
    await _loadRoots();
  }

  List<String> get _categoryNames => [
    '全部',
    ..._categories.map((c) => c['name'] as String),
  ];

  Future<void> _loadChildren(int parentId) async {
    final ch = await widget.memoService.getChildren(parentId);
    if (ch.isNotEmpty) {
      _children[parentId] = ch;
    } else {
      _children.remove(parentId);
    }
  }

  void _toggleExpand(int id) {
    if (_expanded.contains(id)) {
      _expanded.remove(id);
    } else {
      _expanded.add(id);
      _loadChildren(id);
    }
    setState(() {});
  }

  // ── 弹窗新建 ──

  Future<void> showAddDialog() async {
    final ctrl = TextEditingController();
    String category = _filter != '全部' ? _filter : '紧急+重要+必须';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('新建备忘录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(ctx, true);
                  },
                  decoration: const InputDecoration(
                    hintText: '备忘录内容',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _categoryNames.contains(category) ? category : null,
                  decoration: const InputDecoration(
                    labelText: '分类',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _categoryNames
                      .where((c) => c != '全部')
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setSt(() => category = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final content = ctrl.text.trim();
    if (content.isEmpty) return;
    final schedule = await _promptForSchedule(content);
    if (schedule == null) return;
    final created = await widget.memoService.create(
      content,
      category: category,
    );
    final memo = created.copyWith(
      dueDate: schedule.dueDate,
      reminderTime: schedule.reminderTime,
      repeatType: schedule.repeatType,
    );
    if (schedule.dueDate != null) await widget.memoService.update(memo);
    if (memo.dueDate != null && memo.reminderTime != null) {
      await _scheduleMemoReminder(memo);
    }
    _loadRoots();
  }

  // ── 新建根级 ──

  String get _activeCategory => _filter != '全部' ? _filter : '紧急+重要+必须';

  Future<SchedulePromptResult?> _promptForSchedule(String content) {
    return showDialog<SchedulePromptResult>(
      context: context,
      builder: (_) => SchedulePromptDialog(itemName: content),
    );
  }

  Future<void> _createRoot() async {
    final content = _inputController.text.trim();
    if (content.isEmpty) return;
    final schedule = await _promptForSchedule(content);
    if (schedule == null) return;
    final created = await widget.memoService.create(
      content,
      category: _activeCategory,
    );
    final memo = created.copyWith(
      dueDate: schedule.dueDate,
      reminderTime: schedule.reminderTime,
      repeatType: schedule.repeatType,
    );
    if (schedule.dueDate != null) await widget.memoService.update(memo);
    if (memo.dueDate != null && memo.reminderTime != null) {
      await _scheduleMemoReminder(memo);
    }
    _inputController.clear();
    if (mounted && MediaQuery.sizeOf(context).width >= 900) {
      _inputFocus.requestFocus();
    }
    await _loadRoots();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ── 添加子备忘 ──

  Future<void> _addChild(Memo parent) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('添加子备忘录'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '子备忘录内容',
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
    if (result == null || result.isEmpty) return;
    await widget.memoService.createChild(result, parent.id!, parent.level + 1);
    _expanded.add(parent.id!);
    await _loadChildren(parent.id!);
    await _loadRoots();
    if (mounted) setState(() {});
  }

  // ── 编辑 ──

  // ignore: unused_element
  Future<void> _editMemo(Memo memo) async {
    final ctrl = TextEditingController(text: memo.content);
    String editCategory = memo.category;
    DateTime? dueDate = memo.dueDate;
    DateTime? reminderTime = memo.reminderTime;
    String? repeatType = memo.repeatType;
    await _cancelMemoReminder(memo);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('编辑备忘录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '备忘录内容',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                // 分类下拉
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: editCategory,
                  decoration: const InputDecoration(
                    labelText: '分类',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _categoryNames
                      .where((c) => c != '全部')
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setSt(() => editCategory = v!),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: dueDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 5),
                            ),
                            locale: const Locale('zh'),
                          );
                          if (p != null) setSt(() => dueDate = p);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '截止日期',
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(
                            dueDate != null
                                ? '${dueDate!.month}/${dueDate!.day}'
                                : '可选',
                            style: TextStyle(
                              fontSize: 13,
                              color: dueDate != null ? null : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (dueDate != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final initial = reminderTime != null
                                ? TimeOfDay(
                                    hour: reminderTime!.hour,
                                    minute: reminderTime!.minute,
                                  )
                                : TimeOfDay(
                                    hour: (DateTime.now().hour + 1) % 24,
                                    minute: 0,
                                  );
                            final p = await showTimePicker(
                              context: ctx,
                              initialTime: initial,
                            );
                            if (p != null) {
                              setSt(
                                () => reminderTime = DateTime(
                                  2024,
                                  1,
                                  1,
                                  p.hour,
                                  p.minute,
                                ),
                              );
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: '提醒',
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: Icon(Icons.access_time, size: 16),
                            ),
                            child: Text(
                              reminderTime != null
                                  ? '${reminderTime!.hour.toString().padLeft(2, '0')}:${reminderTime!.minute.toString().padLeft(2, '0')}'
                                  : '可选',
                              style: TextStyle(
                                fontSize: 13,
                                color: reminderTime != null
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (dueDate != null) ...[
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: repeatType,
                    decoration: const InputDecoration(
                      labelText: '重复',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('不重复')),
                      DropdownMenuItem(value: 'daily', child: Text('每天')),
                      DropdownMenuItem(value: 'weekly', child: Text('每周')),
                      DropdownMenuItem(value: 'monthly', child: Text('每月')),
                    ],
                    onChanged: (v) => setSt(() => repeatType = v),
                  ),
                  TextButton(
                    onPressed: () => setSt(() {
                      dueDate = null;
                      reminderTime = null;
                      repeatType = null;
                    }),
                    child: const Text('清除日期', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                await widget.memoService.update(
                  memo.copyWith(
                    content: t,
                    category: editCategory,
                    dueDate: dueDate,
                    reminderTime: reminderTime,
                    clearDueDate: dueDate == null,
                    clearReminderTime: reminderTime == null,
                    repeatType: repeatType,
                    clearRepeatType: repeatType == null,
                  ),
                );
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      return;
    }
    // 重新调度通知（用局部变量构造，无需等 _loadRoots）
    if (dueDate != null && reminderTime != null) {
      final tmp = memo.copyWith(
        dueDate: dueDate,
        reminderTime: reminderTime,
        repeatType: repeatType,
      );
      await _scheduleMemoReminder(tmp);
    }
    await _loadRoots();
    if (_expanded.contains(memo.parentId) && memo.parentId != null) {
      await _loadChildren(memo.parentId!);
    }
    if (mounted) setState(() {});
  }

  // ── 树操作 ──

  Future<void> _moveUp(Memo memo) async {
    await widget.memoService.moveUp(memo.id!);
    await _refreshAfterTreeOp(memo.parentId);
  }

  Future<void> _moveDown(Memo memo) async {
    await widget.memoService.moveDown(memo.id!);
    await _refreshAfterTreeOp(memo.parentId);
  }

  Future<void> _promote(Memo memo) async {
    final affected = await widget.memoService.promote(memo.id!);
    if (affected.isEmpty) return;
    if (affected[0] != null) await _loadChildren(affected[0]!);
    if (affected[1] != null) await _loadChildren(affected[1]!);
    await _loadRoots();
    if (mounted) setState(() {});
  }

  Future<void> _demote(Memo memo) async {
    final affected = await widget.memoService.demote(memo.id!);
    if (affected.isEmpty) return;
    if (affected[0] != null) await _loadChildren(affected[0]!);
    if (affected[1] != null) await _loadChildren(affected[1]!);
    await _loadRoots();
    if (mounted) setState(() {});
  }

  Future<void> _softDelete(Memo memo) async {
    await _cancelMemoReminder(memo);
    await widget.memoService.softDelete(memo.id!);
    _expanded.remove(memo.id);
    _children.remove(memo.id);
    await _loadRoots();
    if (memo.parentId != null) await _loadChildren(memo.parentId!);
    if (mounted) setState(() {});
  }

  Future<void> _restore(Memo memo) async {
    await widget.memoService.restore(memo.id!);
    await _scheduleMemoReminder(memo);
    await _loadRoots();
    if (memo.parentId != null) await _loadChildren(memo.parentId!);
    if (mounted) setState(() {});
  }

  Future<void> _permDelete(Memo memo) async {
    await widget.memoService.permanentlyDelete(memo.id!);
    _expanded.remove(memo.id);
    _children.remove(memo.id);
    await _loadRoots();
    if (memo.parentId != null) await _loadChildren(memo.parentId!);
    if (mounted) setState(() {});
  }

  Future<void> _refreshAfterTreeOp(int? parentId) async {
    if (parentId != null) await _loadChildren(parentId);
    await _loadRoots();
    if (mounted) setState(() {});
  }

  // ── 通知 ──

  Future<void> _scheduleMemoReminder(Memo memo) async {
    if (memo.reminderTime != null && memo.dueDate != null) {
      final remindAt = DateTime(
        memo.dueDate!.year,
        memo.dueDate!.month,
        memo.dueDate!.day,
        memo.reminderTime!.hour,
        memo.reminderTime!.minute,
      );
      if (remindAt.isAfter(DateTime.now())) {
        final ok = await widget.notificationService.scheduleReminder(
          id: memo.id! + 20000,
          title:
              '📌 ${memo.content.length > 20 ? '${memo.content.substring(0, 20)}...' : memo.content}',
          body: '备忘录截止日期到了',
          scheduledTime: remindAt,
          repeatType: memo.repeatType,
        );
        // 失败要给反馈，避免静默失败（用户以为设了提醒实际没有）
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '提醒安排失败：${widget.notificationService.status.value.message}',
              ),
            ),
          );
        } else if (ok &&
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

  Future<void> _cancelMemoReminder(Memo memo) async {
    await widget.notificationService.cancelReminder(memo.id! + 20000);
  }

  Future<void> _onMemoReorder(
    List<Memo> items,
    int? parentId,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<Memo>.from(items);
    final memo = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, memo);
    for (int i = 0; i < reordered.length; i++) {
      await widget.memoService.updateSortOrder(reordered[i].id!, i);
    }
    await _refreshAfterTreeOp(parentId);
  }

  // ── 递归渲染树 ──

  List<Widget> _buildTree(List<Memo> items, int? parentId) {
    if (items.length <= 1 || _selectMode) {
      // 单项或选择模式：普通列表
      final list = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        final memo = items[i];
        final hasChildren = _children.containsKey(memo.id);
        final isExpanded = _expanded.contains(memo.id);
        list.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemoItem(
                memo: memo,
                index: i,
                total: items.length,
                hasChildren: hasChildren,
                selectMode: _selectMode,
                isSelected: _selectedIds.contains(memo.id),
                onSelectToggle: () => _toggleSelect(memo.id!),
                isExpanded: isExpanded,
                onTap: memo.isDeleted ? () {} : () => _openMemo(memo),
                onEdit: memo.isDeleted ? null : () => _editMemo(memo),
                onToggleExpand: () => _toggleExpand(memo.id!),
                onMoveUp: memo.isDeleted ? null : () => _moveUp(memo),
                onMoveDown: memo.isDeleted ? null : () => _moveDown(memo),
                onPromote: memo.parentId != null && !memo.isDeleted
                    ? () => _promote(memo)
                    : null,
                onDemote: memo.level < 4 && i > 0 && !memo.isDeleted
                    ? () => _demote(memo)
                    : null,
                onAddChild: memo.canHaveChildren && !memo.isDeleted
                    ? () => _addChild(memo)
                    : null,
                onPin: memo.parentId == null && !memo.isDeleted
                    ? () => _togglePin(memo)
                    : null,
                onArchive: memo.parentId == null && !memo.isDeleted
                    ? () => _toggleArchive(memo)
                    : null,
                onConvertTodo: !memo.isDeleted
                    ? () => _convertToTodo(memo)
                    : null,
                onGenerateTodos: !memo.isDeleted
                    ? () => _generateTodos(memo)
                    : null,
                onLinkTodo: !memo.isDeleted
                    ? () => _linkExistingTodo(memo)
                    : null,
                onDelete: () =>
                    memo.isDeleted ? _permDelete(memo) : _softDelete(memo),
                onRestore: memo.isDeleted ? () => _restore(memo) : null,
              ),
              if (isExpanded && hasChildren)
                ..._buildTree(_children[memo.id!]!, memo.id),
            ],
          ),
        );
      }
      return list;
    }
    // 多项：可拖拽排序
    return [
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: true,
        onReorderItem: (oldIdx, newIdx) =>
            _onMemoReorder(items, parentId, oldIdx, newIdx),
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final memo = e.value;
          final hasChildren = _children.containsKey(memo.id);
          final isExpanded = _expanded.contains(memo.id);
          return Column(
            key: ValueKey(memo.id),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemoItem(
                memo: memo,
                index: i,
                total: items.length,
                hasChildren: hasChildren,
                isExpanded: isExpanded,
                onTap: memo.isDeleted ? () {} : () => _openMemo(memo),
                onEdit: memo.isDeleted ? null : () => _editMemo(memo),
                onToggleExpand: () => _toggleExpand(memo.id!),
                onMoveUp: memo.isDeleted ? null : () => _moveUp(memo),
                onMoveDown: memo.isDeleted ? null : () => _moveDown(memo),
                onPromote: memo.parentId != null && !memo.isDeleted
                    ? () => _promote(memo)
                    : null,
                onDemote: memo.level < 4 && i > 0 && !memo.isDeleted
                    ? () => _demote(memo)
                    : null,
                onAddChild: memo.canHaveChildren && !memo.isDeleted
                    ? () => _addChild(memo)
                    : null,
                onPin: memo.parentId == null && !memo.isDeleted
                    ? () => _togglePin(memo)
                    : null,
                onArchive: memo.parentId == null && !memo.isDeleted
                    ? () => _toggleArchive(memo)
                    : null,
                onConvertTodo: !memo.isDeleted
                    ? () => _convertToTodo(memo)
                    : null,
                onGenerateTodos: !memo.isDeleted
                    ? () => _generateTodos(memo)
                    : null,
                onLinkTodo: !memo.isDeleted
                    ? () => _linkExistingTodo(memo)
                    : null,
                onDelete: () =>
                    memo.isDeleted ? _permDelete(memo) : _softDelete(memo),
                onRestore: memo.isDeleted ? () => _restore(memo) : null,
              ),
              if (isExpanded && hasChildren)
                ..._buildTree(_children[memo.id!]!, memo.id),
            ],
          );
        }).toList(),
      ),
    ];
  }

  // ── 统计 ──

  String _remainingDays(Memo m) {
    if (m.deletedAt == null) return '';
    return '${15 - DateTime.now().difference(m.deletedAt!).inDays}';
  }

  int _countAll(List<Memo> list) {
    int c = list.length;
    for (final item in list) {
      if (_children.containsKey(item.id)) c += _countAll(_children[item.id!]!);
    }
    return c;
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

  Future<void> _batchDeleteMemos() async {
    for (final id in _selectedIds.toList()) {
      await widget.memoService.softDelete(id);
    }
    _selectedIds.clear();
    _selectMode = false;
    _loadRoots();
  }

  // ── 分类管理 ──

  Future<void> _showCategoryManager() async {
    final TextEditingController nameCtrl = TextEditingController();

    Future<void> refreshCats() async {
      final cats = await widget.memoService.getCategories();
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
                        final isDefault = i < 8;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color,
                            radius: 14,
                          ),
                          title: Text(name),
                          trailing: isDefault
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () async {
                                        nameCtrl.text = name;
                                        final result =
                                            await showDialog<
                                              Map<String, String>
                                            >(
                                              context: ctx,
                                              builder: (_) => AlertDialog(
                                                title: const Text('编辑分类'),
                                                content: TextField(
                                                  controller: nameCtrl,
                                                  decoration:
                                                      const InputDecoration(
                                                        hintText: '分类名称',
                                                        border:
                                                            OutlineInputBorder(),
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
                                          await widget.memoService
                                              .updateCategory(
                                                cat['id'] as int,
                                                result['name']!,
                                                cat['color'] as String,
                                              );
                                          if (_filter == name) {
                                            _filter = result['name']!;
                                            widget.onSectionChanged?.call(
                                              result['name']!,
                                            );
                                          }
                                          await refreshCats();
                                          setSheetState(() {});
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        await widget.memoService.deleteCategory(
                                          cat['id'] as int,
                                        );
                                        if (_filter == name) {
                                          _filter = '全部';
                                          widget.onSectionChanged?.call('全部备忘');
                                        }
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
                          await widget.memoService.addCategory(
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
    _loadRoots();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 900;
    final filtered = _filter == '全部'
        ? _roots
        : _roots.where((m) => m.category == _filter).toList();
    final searched = _searchQuery.isEmpty
        ? filtered
        : filtered.where((m) => m.content.contains(_searchQuery)).toList();
    final total = _countAll(_roots);
    final treeItems = _buildTree(searched, null);

    final page = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Row(
            children: [
              FilterChip(
                selected: !_showArchivedView,
                label: const Text('备忘录'),
                onSelected: (_) {
                  setState(() => _showArchivedView = false);
                  widget.onSectionChanged?.call(
                    _filter == '全部' ? '全部备忘' : _filter,
                  );
                  _loadRoots();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _showArchivedView,
                avatar: const Icon(Icons.archive_outlined, size: 16),
                label: const Text('归档'),
                onSelected: (_) {
                  setState(() => _showArchivedView = true);
                  widget.onSectionChanged?.call('已归档');
                  _loadRoots();
                },
              ),
            ],
          ),
        ),
        // 分类过滤
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._categoryNames.map((label) {
                  final selected = _filter == label;
                  final cat = _categories.firstWhere(
                    (c) => c['name'] == label,
                    orElse: () => {},
                  );
                  final colorStr = cat['color'] as String?;
                  final color = colorStr != null
                      ? Color(int.parse(colorStr.replaceFirst('#', '0xFF')))
                      : Colors.indigo;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : color,
                        ),
                      ),
                      selected: selected,
                      selectedColor: color,
                      backgroundColor: color.withAlpha(25),
                      labelPadding: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 15,
                      ),
                      side: BorderSide(color: color.withAlpha(80)),
                      onSelected: (_) => _setFilter(label),
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.label_outline, size: 16),
                    label: const Text('管理', style: TextStyle(fontSize: 13)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 15,
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    onPressed: _showCategoryManager,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 搜索（滚回顶部时出现）
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _searchVisible
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: '搜索备忘录...',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
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
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: filtered.isEmpty && _deleted.isEmpty
              ? Center(
                  child: Text(
                    isCompact ? '还没有备忘录，点右下角创建' : '还没有备忘录，输入内容后按 Enter 创建',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: [
                    if (_roots.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$total 条',
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
                      ...treeItems,
                    ],
                    if (_deleted.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () =>
                            setState(() => _showDeleted = !_showDeleted),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _showDeleted
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: Colors.red.shade400,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '最近删除',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade400,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_deleted.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showDeleted)
                        ..._deleted.map(
                          (memo) => ListTile(
                            dense: true,
                            title: Text(
                              memo.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            subtitle: Text(
                              '剩余${_remainingDays(memo)}天',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red.shade300,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.restore,
                                    size: 16,
                                    color: Colors.green.shade400,
                                  ),
                                  onPressed: () => _restore(memo),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_forever,
                                    size: 16,
                                    color: Colors.red.shade400,
                                  ),
                                  onPressed: () => _permDelete(memo),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
        // ── 批量操作栏 ──
        if (_selectMode && _selectedIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _batchDeleteMemos,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text(
                    '批量删除',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        if (!isCompact)
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
                    controller: _inputController,
                    focusNode: _inputFocus,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: '输入内容，按 Enter 创建...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _createRoot(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _createRoot,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth < 900) return page;
        return Row(
          children: [
            Expanded(child: page),
            if (_selectedMemo != null)
              SizedBox(
                width: 420,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: _memoDetailPanel(
                    _selectedMemo!,
                    onClose: () => setState(() => _selectedMemo = null),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
