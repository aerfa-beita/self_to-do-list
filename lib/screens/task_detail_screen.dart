import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../models/sub_task.dart';
import '../services/task_service.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';

class _FocusSubInputIntent extends Intent {
  const _FocusSubInputIntent();
}

class TaskDetailScreen extends StatefulWidget {
  final Task task;
  final TaskService taskService;
  final NotificationService notificationService;
  final Future<Task?> Function(Task task)? onEditTask;
  final String actionScope;

  const TaskDetailScreen({
    super.key,
    required this.task,
    required this.taskService,
    required this.notificationService,
    this.onEditTask,
    this.actionScope = Task.actionScopeInbox,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late Task _currentTask;
  List<SubTask> _roots = [];
  Map<int, List<SubTask>> _children = {};
  final Set<int> _expanded = {};
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    _loadAll();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    final children = <int, List<SubTask>>{};
    for (final r in roots) {
      final ch = await widget.taskService.getChildSubTasks(r.id!);
      if (ch.isNotEmpty) children[r.id!] = ch;
    }
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _children = children;
    });
  }

  Future<void> _loadChildren(int parentId) async {
    final ch = await widget.taskService.getChildSubTasks(parentId);
    if (ch.isEmpty) {
      _children.remove(parentId);
    } else {
      _children[parentId] = ch;
    }
  }

  Future<void> _addRoot() async {
    final title = _inputController.text.trim();
    if (title.isEmpty) return;
    await widget.taskService.insertSubTask(
      SubTask(taskId: widget.task.id!, title: title, level: 0),
    );
    _inputController.clear();
    _inputFocus.requestFocus();
    await widget.taskService.checkTaskCompletion(
      widget.task.id!,
      source: widget.actionScope,
    );
    _loadAll();
  }

  Future<void> _addChild(SubTask parent) async {
    final ctrl = TextEditingController();
    DateTime? dueDate;
    DateTime? reminderTime;
    String? repeatType;

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('添加子任务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '子任务名称',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
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
                            labelText: '截止日期（可选）',
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(
                            dueDate != null
                                ? '${dueDate!.month}/${dueDate!.day}'
                                : '点击选择',
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
                              labelText: '提醒时间',
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
                final v = ctrl.text.trim();
                if (v.isNotEmpty) Navigator.pop(ctx, v);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    final newId = await widget.taskService.insertSubTask(
      SubTask(
        taskId: widget.task.id!,
        parentId: parent.id,
        level: parent.level + 1,
        title: title,
        dueDate: dueDate,
        reminderTime: reminderTime,
        repeatType: repeatType,
      ),
    );
    if (dueDate != null && reminderTime != null) {
      await _scheduleSubTaskReminder(
        SubTask(
          id: newId,
          taskId: widget.task.id!,
          title: title,
          dueDate: dueDate,
          reminderTime: reminderTime,
          repeatType: repeatType,
        ),
      );
    }
    _expanded.add(parent.id!);
    await _loadChildren(parent.id!);
    await widget.taskService.checkTaskCompletion(
      widget.task.id!,
      source: widget.actionScope,
    );
    final roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (!mounted) return;
    setState(() {
      _roots = roots;
    });
  }

  Future<void> _editSubTask(SubTask st) async {
    await _cancelSubTaskReminder(st);
    final ctrl = TextEditingController(text: st.title);
    DateTime? dueDate = st.dueDate;
    DateTime? reminderTime = st.reminderTime;
    String? repeatType = st.repeatType;

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('编辑子任务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '子任务名称',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                  },
                ),
                const SizedBox(height: 10),
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
                                : '点击选择',
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
                              labelText: '提醒时间',
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
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isNotEmpty) Navigator.pop(ctx, v);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    final updated = st.copyWith(
      title: title,
      dueDate: dueDate,
      reminderTime: reminderTime,
      clearDueDate: dueDate == null,
      clearReminderTime: reminderTime == null,
      repeatType: repeatType,
      clearRepeatType: repeatType == null,
    );
    await widget.taskService.updateSubTask(updated);
    if (dueDate != null && reminderTime != null) {
      await _scheduleSubTaskReminder(updated);
    }
    await widget.taskService.checkTaskCompletion(
      widget.task.id!,
      source: widget.actionScope,
    );
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSubTask(SubTask st) async {
    await widget.taskService.toggleSubTaskForTask(
      _currentTask,
      st,
      source: widget.actionScope,
    );
    if (!mounted) return;
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    } else {
      _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    }
    if (mounted) setState(() {}); // ← 二次刷新（同步 DB 结果）
  }

  Future<void> _deleteSubTask(SubTask st) async {
    await _cancelSubTaskReminder(st);
    await widget.taskService.softDeleteSubTask(st.id!);
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Future<void> _restoreSubTask(SubTask st) async {
    await widget.taskService.restoreSubTask(st.id!);
    await _scheduleSubTaskReminder(st);
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Future<void> _permDeleteSubTask(SubTask st) async {
    await widget.taskService.permanentlyDeleteSubTask(st.id!); // 硬删除
    _expanded.remove(st.id);
    _children.remove(st.id);
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Future<void> _promoteSubTask(SubTask st) async {
    final affected = await widget.taskService.promoteSubTask(st.id!);
    if (affected.isEmpty) return;
    _refreshAffected(affected[0], affected[1]);
  }

  Future<void> _demoteSubTask(SubTask st) async {
    final affected = await widget.taskService.demoteSubTask(st.id!);
    if (affected.isEmpty) return;
    _refreshAffected(affected[0], affected[1]);
  }

  Future<void> _refreshAffected(int? oldParent, int? newParent) async {
    if (oldParent != null) await _loadChildren(oldParent);
    if (newParent != null) await _loadChildren(newParent);
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  // ── 子任务通知 ──

  Future<void> _scheduleSubTaskReminder(SubTask st) async {
    if (st.reminderTime != null && st.dueDate != null && st.id != null) {
      final remindAt = DateTime(
        st.dueDate!.year,
        st.dueDate!.month,
        st.dueDate!.day,
        st.reminderTime!.hour,
        st.reminderTime!.minute,
      );
      if (remindAt.isAfter(DateTime.now())) {
        await widget.notificationService.scheduleReminder(
          id: st.id! + 30000,
          title: '📌 ${st.title}',
          body: '子任务截止日期到了',
          scheduledTime: remindAt,
          repeatType: st.repeatType,
        );
      }
    }
  }

  Future<void> _cancelSubTaskReminder(SubTask st) async {
    if (st.id != null) {
      await widget.notificationService.cancelReminder(st.id! + 30000);
    }
  }

  void _toggleExpand(int id) {
    if (_expanded.contains(id)) {
      _expanded.remove(id);
    } else {
      _expanded.add(id);
      _loadChildren(id);
    }
    if (mounted) setState(() {});
  }

  int _countAll() {
    int count(List<SubTask> list) {
      int c = list.length;
      for (final item in list) {
        if (_children.containsKey(item.id)) c += count(_children[item.id!]!);
      }
      return c;
    }

    return count(_roots);
  }

  int _countDone() {
    int count(List<SubTask> list) {
      int c = list.where((s) => s.isDone).length;
      for (final item in list) {
        if (_children.containsKey(item.id)) c += count(_children[item.id!]!);
      }
      return c;
    }

    return count(_roots);
  }

  Widget _menuLabel(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }

  List<PopupMenuEntry<String>> _subTaskMenuItems(SubTask st, int index) {
    if (st.isDeleted) {
      return [
        PopupMenuItem(
          value: 'restore',
          child: _menuLabel(Icons.restore_outlined, '恢复'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: _menuLabel(
            Icons.delete_forever_outlined,
            '永久删除',
            color: Colors.red,
          ),
        ),
      ];
    }
    return [
      PopupMenuItem(
        value: 'edit',
        child: _menuLabel(Icons.edit_outlined, '编辑'),
      ),
      if (st.canHaveChildren)
        PopupMenuItem(
          value: 'add_child',
          child: _menuLabel(Icons.add_circle_outline, '添加下级'),
        ),
      if (st.parentId != null)
        PopupMenuItem(
          value: 'promote',
          child: _menuLabel(Icons.subdirectory_arrow_left, '提升一级'),
        ),
      if (st.level < 4 && index > 0)
        PopupMenuItem(
          value: 'demote',
          child: _menuLabel(Icons.subdirectory_arrow_right, '设为上一项的下级'),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: _menuLabel(Icons.delete_outline, '删除', color: Colors.red),
      ),
    ];
  }

  void _handleSubTaskAction(String value, SubTask st) {
    switch (value) {
      case 'edit':
        _editSubTask(st);
      case 'promote':
        _promoteSubTask(st);
      case 'demote':
        _demoteSubTask(st);
      case 'add_child':
        _addChild(st);
      case 'delete':
        st.isDeleted ? _permDeleteSubTask(st) : _deleteSubTask(st);
      case 'restore':
        _restoreSubTask(st);
    }
  }

  void _showContextMenu(Offset position, SubTask st, int index) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: _subTaskMenuItems(st, index),
    ).then((v) {
      if (v == null) return;
      _handleSubTaskAction(v, st);
    });
  }

  Future<void> _onSubTaskReorder(
    List<SubTask> items,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = List<SubTask>.from(items);
    final st = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, st);
    for (int i = 0; i < reordered.length; i++) {
      await widget.taskService.updateSubTaskSortOrder(reordered[i].id!, i);
    }
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Widget _buildSubTaskTile(
    SubTask st,
    int i,
    bool hasChildren,
    bool isExpanded,
    double indent, {
    Key? key,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: EdgeInsets.only(left: indent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: st.isDone
                  ? colors.surfaceContainerLow
                  : colors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                onSecondaryTapUp: (details) =>
                    _showContextMenu(details.globalPosition, st, i),
                child: ListTile(
                  onTap: st.isDeleted ? null : () => _editSubTask(st),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasChildren || st.canHaveChildren)
                        IconButton(
                          tooltip: isExpanded ? '收起下级' : '展开下级',
                          onPressed: () => _toggleExpand(st.id!),
                          icon: Icon(
                            isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 20,
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                      Checkbox(
                        value: st.isDone,
                        shape: const CircleBorder(),
                        side: BorderSide(color: colors.primary, width: 1.8),
                        onChanged: st.isDeleted
                            ? null
                            : (_) => _toggleSubTask(st),
                      ),
                    ],
                  ),
                  title: Text(
                    st.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      decoration: (st.isDone || st.isDeleted)
                          ? TextDecoration.lineThrough
                          : null,
                      color: (st.isDone || st.isDeleted)
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                  subtitle: st.dueDate == null
                      ? null
                      : Text(
                          '${st.isOverdue ? "已过期 · " : ""}${fmtDateTime(st.dueDate, st.reminderTime)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: st.isOverdue
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                                fontWeight: st.isOverdue
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                        ),
                  trailing: PopupMenuButton<String>(
                    key: Key('subtask-more-${st.id}'),
                    tooltip: '更多子任务操作',
                    iconSize: 22,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
                    onSelected: (value) => _handleSubTaskAction(value, st),
                    itemBuilder: (_) => _subTaskMenuItems(st, i),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
          if (isExpanded && hasChildren) ..._buildTree(_children[st.id!]!),
        ],
      ),
    );
  }

  List<Widget> _buildTree(List<SubTask> items) {
    if (items.length <= 1) {
      final list = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        final st = items[i];
        final hasChildren = _children.containsKey(st.id);
        final isExpanded = _expanded.contains(st.id);
        final indent = st.level * 20.0;
        list.add(_buildSubTaskTile(st, i, hasChildren, isExpanded, indent));
      }
      return list;
    }
    return [
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: true,
        onReorderItem: (oldIdx, newIdx) =>
            _onSubTaskReorder(items, oldIdx, newIdx),
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final st = e.value;
          final hasChildren = _children.containsKey(st.id);
          final isExpanded = _expanded.contains(st.id);
          final indent = st.level * 20.0;
          return _buildSubTaskTile(
            st,
            i,
            hasChildren,
            isExpanded,
            indent,
            key: ValueKey(st.id),
          );
        }).toList(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final total = _countAll();
    final done = _countDone();
    final treeItems = _buildTree(_roots);
    final colors = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : done / total;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyT, control: true):
            const _FocusSubInputIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            const _FocusSubInputIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusSubInputIntent: CallbackAction<_FocusSubInputIntent>(
            onInvoke: (_) {
              _inputFocus.requestFocus();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_currentTask.title),
            actions: [
              // 只读展示当前安排分组；分类一律在列表/安排视图的菜单里改
              if (_currentTask.isArranged)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Chip(
                      avatar: const Icon(Icons.view_week_outlined, size: 16),
                      label: Text(_currentTask.arrangementLabel),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              if (widget.onEditTask != null)
                TextButton(
                  onPressed: () async {
                    final updated = await widget.onEditTask!(_currentTask);
                    if (mounted && updated != null) {
                      setState(() => _currentTask = updated);
                    }
                  },
                  child: const Text('编辑'),
                ),
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              if (_currentTask.note.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.note_alt_outlined,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '任务备注',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: colors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _currentTask.note,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Container(
                  key: const Key('subtask-progress-card'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer.withAlpha(110),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '任务进度',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              total == 0
                                  ? '还没有子任务'
                                  : done == total
                                  ? '全部完成'
                                  : '还剩 ${total - done} 项',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width < 360
                            ? 132
                            : 176,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$done / $total 完成',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progress,
                              minHeight: 7,
                              borderRadius: BorderRadius.circular(4),
                              backgroundColor: colors.surfaceContainerHighest,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    Text(
                      '子任务',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      total > 1 ? '长按排序' : '$total 项',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _roots.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.checklist_rounded,
                              size: 36,
                              color: colors.outline,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '还没有子任务',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: treeItems,
                      ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocus,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: '添加子任务',
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: colors.outlineVariant,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                          ),
                          onSubmitted: (_) => _addRoot(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: '添加子任务',
                        onPressed: _addRoot,
                        constraints: const BoxConstraints.tightFor(
                          width: 50,
                          height: 50,
                        ),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
