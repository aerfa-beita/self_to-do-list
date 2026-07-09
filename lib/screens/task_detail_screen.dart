import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/sub_task.dart';
import '../services/task_service.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';

class TaskDetailScreen extends StatefulWidget {
  final Task task;
  final TaskService taskService;
  final NotificationService notificationService;

  const TaskDetailScreen({
    super.key,
    required this.task,
    required this.taskService,
    required this.notificationService,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  List<SubTask> _roots = [];
  Map<int, List<SubTask>> _children = {};
  final Set<int> _expanded = {};
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
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
    setState(() { _roots = roots; _children = children; });
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
    await widget.taskService.insertSubTask(SubTask(taskId: widget.task.id!, title: title, level: 0));
    _inputController.clear();
    _inputFocus.requestFocus();
    await widget.taskService.checkTaskCompletion(widget.task.id!);
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
                  decoration: const InputDecoration(hintText: '子任务名称', border: OutlineInputBorder()),
                  onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          locale: const Locale('zh'),
                        );
                        if (p != null) setSt(() => dueDate = p);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '截止日期（可选）', border: OutlineInputBorder(), isDense: true,
                          suffixIcon: Icon(Icons.calendar_today, size: 16),
                        ),
                        child: Text(dueDate != null ? '${dueDate!.month}/${dueDate!.day}' : '点击选择',
                            style: TextStyle(fontSize: 13, color: dueDate != null ? null : Colors.grey)),
                      ),
                    ),
                  ),
                  if (dueDate != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final initial = reminderTime != null
                              ? TimeOfDay(hour: reminderTime!.hour, minute: reminderTime!.minute)
                              : TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
                          final p = await showTimePicker(
                            context: ctx,
                            initialTime: initial,
                          );
                          if (p != null) {
                            setSt(() => reminderTime = DateTime(2024, 1, 1, p.hour, p.minute));
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '提醒时间', border: OutlineInputBorder(), isDense: true,
                            suffixIcon: Icon(Icons.access_time, size: 16),
                          ),
                          child: Text(
                            reminderTime != null
                                ? '${reminderTime!.hour.toString().padLeft(2, '0')}:${reminderTime!.minute.toString().padLeft(2, '0')}'
                                : '可选',
                            style: TextStyle(fontSize: 13, color: reminderTime != null ? null : Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
    final newId = await widget.taskService.insertSubTask(SubTask(
      taskId: widget.task.id!, parentId: parent.id, level: parent.level + 1,
      title: title, dueDate: dueDate, reminderTime: reminderTime,
      repeatType: repeatType,
    ));
    if (dueDate != null && reminderTime != null) {
      await _scheduleSubTaskReminder(SubTask(
        id: newId, taskId: widget.task.id!, title: title,
        dueDate: dueDate, reminderTime: reminderTime,
        repeatType: repeatType,
      ));
    }
    _expanded.add(parent.id!);
    await _loadChildren(parent.id!);
    await widget.taskService.checkTaskCompletion(widget.task.id!);
    final roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (!mounted) return;
    setState(() { _roots = roots; });
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
                  decoration: const InputDecoration(hintText: '子任务名称', border: OutlineInputBorder()),
                  onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: dueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          locale: const Locale('zh'),
                        );
                        if (p != null) setSt(() => dueDate = p);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '截止日期', border: OutlineInputBorder(), isDense: true,
                          suffixIcon: Icon(Icons.calendar_today, size: 16),
                        ),
                        child: Text(dueDate != null ? '${dueDate!.month}/${dueDate!.day}' : '点击选择',
                            style: TextStyle(fontSize: 13, color: dueDate != null ? null : Colors.grey)),
                      ),
                    ),
                  ),
                  if (dueDate != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final initial = reminderTime != null
                              ? TimeOfDay(hour: reminderTime!.hour, minute: reminderTime!.minute)
                              : TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
                          final p = await showTimePicker(
                            context: ctx,
                            initialTime: initial,
                          );
                          if (p != null) {
                            setSt(() => reminderTime = DateTime(2024, 1, 1, p.hour, p.minute));
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '提醒时间', border: OutlineInputBorder(), isDense: true,
                            suffixIcon: Icon(Icons.access_time, size: 16),
                          ),
                          child: Text(
                            reminderTime != null
                                ? '${reminderTime!.hour.toString().padLeft(2, '0')}:${reminderTime!.minute.toString().padLeft(2, '0')}'
                                : '可选',
                            style: TextStyle(fontSize: 13, color: reminderTime != null ? null : Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
                if (dueDate != null) ...[
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: repeatType,
                    decoration: const InputDecoration(labelText: '重复', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('不重复')),
                      DropdownMenuItem(value: 'daily', child: Text('每天')),
                      DropdownMenuItem(value: 'weekly', child: Text('每周')),
                      DropdownMenuItem(value: 'monthly', child: Text('每月')),
                    ],
                    onChanged: (v) => setSt(() => repeatType = v),
                  ),
                  TextButton(
                    onPressed: () => setSt(() { dueDate = null; reminderTime = null; repeatType = null; }),
                    child: const Text('清除日期', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
    await widget.taskService.checkTaskCompletion(widget.task.id!);
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSubTask(SubTask st) async {
    final updated = st.copyWith(isDone: !st.isDone);
    _updateSubTaskInTree(st.id!, updated);
    if (mounted) setState(() {});           // ← 立即刷新 UI
    await widget.taskService.updateSubTask(updated);       // 后台写 DB
    await widget.taskService.checkTaskCompletion(widget.task.id!);
    if (!mounted) return;
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    } else {
      _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    }
    if (mounted) setState(() {});           // ← 二次刷新（同步 DB 结果）
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

  void _updateSubTaskInTree(int id, SubTask updated) {
    void update(List<SubTask> list) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == id) { list[i] = updated; return; }
        if (_children.containsKey(list[i].id)) update(_children[list[i].id!]!);
      }
    }
    update(_roots);
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

  Future<void> _moveSubTaskUp(SubTask st) async {
    await widget.taskService.moveSubTaskUp(st.id!);
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
  }

  Future<void> _moveSubTaskDown(SubTask st) async {
    await widget.taskService.moveSubTaskDown(st.id!);
    if (st.parentId != null) {
      await _loadChildren(st.parentId!);
    }
    _roots = await widget.taskService.getRootSubTasks(widget.task.id!);
    if (mounted) setState(() {});
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
      final remindAt = DateTime(st.dueDate!.year, st.dueDate!.month, st.dueDate!.day,
          st.reminderTime!.hour, st.reminderTime!.minute);
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

  void _showContextMenu(Offset position, SubTask st, int index, int total) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (index > 0 && !st.isDeleted)
          const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
        if (index < total - 1 && !st.isDeleted)
          const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
        if (st.parentId != null && !st.isDeleted)
          const PopupMenuItem(value: 'promote', child: Text('← 提升')),
        if (st.level < 4 && index > 0 && !st.isDeleted)
          const PopupMenuItem(value: 'demote', child: Text('→ 降入')),
        if (st.canHaveChildren && !st.isDeleted)
          const PopupMenuItem(value: 'add_child', child: Text('＋ 添加子任务')),
        if (st.isDeleted)
          const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
        PopupMenuItem(value: 'delete', child: Text(st.isDeleted ? '🗑 永久删除' : '🗑 删除')),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'up': _moveSubTaskUp(st); break;
        case 'down': _moveSubTaskDown(st); break;
        case 'promote': _promoteSubTask(st); break;
        case 'demote': _demoteSubTask(st); break;
        case 'add_child': _addChild(st); break;
        case 'delete': if (st.isDeleted) { _permDeleteSubTask(st); } else { _deleteSubTask(st); } break;
        case 'restore': _restoreSubTask(st); break;
      }
    });
  }

  List<Widget> _buildTree(List<SubTask> items) {
    final list = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final st = items[i];
      final hasChildren = _children.containsKey(st.id);
      final isExpanded = _expanded.contains(st.id);
      final indent = st.level * 24.0;

      list.add(Padding(
        padding: EdgeInsets.only(left: indent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition, st, i, items.length),
              child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasChildren || st.canHaveChildren)
                    InkWell(
                      onTap: () => _toggleExpand(st.id!),
                      child: Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 20, color: Colors.grey.shade500,
                      ),
                    )
                  else
                    const SizedBox(width: 20),
                  Checkbox(
                    value: st.isDone,
                    onChanged: (_) => _toggleSubTask(st),
                  ),
                ],
              ),
              title: InkWell(
                onTap: () => _editSubTask(st),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      st.title,
                      style: TextStyle(
                        decoration: (st.isDone || st.isDeleted) ? TextDecoration.lineThrough : null,
                        color: (st.isDone || st.isDeleted) ? Colors.grey : null,
                        fontSize: 16,
                      ),
                    ),
                    if (st.dueDate != null)
                      Text(
                        '${st.isOverdue ? "已过期 " : ""}${fmtDateTime(st.dueDate, st.reminderTime)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: st.isOverdue ? Colors.red : Colors.grey.shade500,
                          fontWeight: st.isOverdue ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
              ),
              trailing: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(Icons.more_vert, color: Colors.grey.shade500),
                onSelected: (v) {
                  switch (v) {
                    case 'up': _moveSubTaskUp(st); break;
                    case 'down': _moveSubTaskDown(st); break;
                    case 'promote': _promoteSubTask(st); break;
                    case 'demote': _demoteSubTask(st); break;
                    case 'add_child': _addChild(st); break;
                    case 'delete': st.isDeleted ? _permDeleteSubTask(st) : _deleteSubTask(st); break;
                    case 'restore': _restoreSubTask(st); break;
                  }
                },
                itemBuilder: (_) => [
                  if (!st.isDeleted && i > 0)
                    const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
                  if (!st.isDeleted && i < items.length - 1)
                    const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
                  if (!st.isDeleted && st.parentId != null)
                    const PopupMenuItem(value: 'promote', child: Text('← 提升')),
                  if (!st.isDeleted && st.level < 4 && i > 0)
                    const PopupMenuItem(value: 'demote', child: Text('→ 降入')),
                  if (!st.isDeleted && st.canHaveChildren)
                    const PopupMenuItem(value: 'add_child', child: Text('＋ 添加子任务')),
                  if (st.isDeleted)
                    const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
                  PopupMenuItem(value: 'delete', child: Text(st.isDeleted ? '🗑 永久删除' : '🗑 删除')),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
              visualDensity: VisualDensity.standard,
            ),
            ), // GestureDetector
            if (isExpanded && hasChildren)
              ..._buildTree(_children[st.id!]!),
          ],
        ),
      ));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final total = _countAll();
    final done = _countDone();
    final treeItems = _buildTree(_roots);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task.title),
        actions: [
          Center(child: Text('$done/$total 完成')),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (widget.task.note.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📝 备忘录', style: TextStyle(fontSize: 12, color: Colors.indigo.shade400)),
                  const SizedBox(height: 6),
                  Text(widget.task.note, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Text('子任务', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              Text('$total 项', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ]),
          ),
          Expanded(
            child: _roots.isEmpty
                ? Center(child: Text('还没有子任务，在下方添加', style: TextStyle(color: Colors.grey.shade400)))
                : ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: treeItems),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -1))],
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '添加子任务...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _addRoot(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _addRoot, icon: const Icon(Icons.add)),
            ]),
          ),
        ],
      ),
    );
  }
}
