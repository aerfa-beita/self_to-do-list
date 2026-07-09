import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/sub_task.dart';
import '../utils/date_utils.dart';

class TaskItem extends StatelessWidget {
  final Task task;
  final int doneCount;
  final int totalCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onRestore;
  final VoidCallback? onPermanentDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final List<SubTask> subTasks;
  final void Function(SubTask st)? onToggleSubTask;
  final void Function(SubTask st)? onDeleteSubTask;
  final void Function(SubTask st)? onMoveSubTaskUp;
  final void Function(SubTask st)? onMoveSubTaskDown;
  // 批量选择
  final bool selectMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;

  const TaskItem({
    super.key,
    required this.task,
    required this.doneCount,
    required this.totalCount,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.onRestore,
    this.onPermanentDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.canMoveUp = true,
    this.canMoveDown = true,
    this.isExpanded = false,
    this.onToggleExpand,
    this.subTasks = const [],
    this.onToggleSubTask,
    this.onDeleteSubTask,
    this.onMoveSubTaskUp,
    this.onMoveSubTaskDown,
    this.selectMode = false,
    this.isSelected = false,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasProgress = totalCount > 0;
    final allDone = hasProgress && doneCount == totalCount;
    final catColor = categoryColor(task.category);
    final hasSubtasks = subTasks.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: task.isDeleted ? null : (selectMode ? onSelectToggle : onTap),
            onSecondaryTapUp: selectMode ? null : (task.isDeleted ? null : (details) {
              showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
                items: [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                  if (onMoveUp != null && canMoveUp)
                    const PopupMenuItem(value: 'move_up', child: Text('⬆ 上移')),
                  if (onMoveDown != null && canMoveDown)
                    const PopupMenuItem(value: 'move_down', child: Text('⬇ 下移')),
                ],
              ).then((v) {
                if (v == null) return;
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
                if (v == 'move_up') onMoveUp?.call();
                if (v == 'move_down') onMoveDown?.call();
              });
            }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.zero),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (selectMode)
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => onSelectToggle?.call(),
                        ),
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600,
                            decoration: (allDone || task.isDeleted) ? TextDecoration.lineThrough : null,
                            color: task.isDeleted ? Colors.grey : (allDone ? Colors.grey : null),
                          ),
                        ),
                      ),
                      _buildMenu(allDone),
                    ],
                  ),
                  if (task.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(task.note, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                  if (task.dueDate != null && !task.isDeleted) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.event, size: 12, color: task.isOverdue ? Colors.red : Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        task.isOverdue ? '已过期 ${fmtDateTime(task.dueDate, task.reminderTime)}' : fmtDateTime(task.dueDate, task.reminderTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: task.isOverdue ? Colors.red : Colors.grey.shade500,
                          fontWeight: task.isOverdue ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    _chip(task.category, catColor),
                    if (task.isDeleted && task.deletedAt != null) ...[
                      const SizedBox(width: 8),
                      Text('剩余$_remainingDays天', style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                    ],
                    const Spacer(),
                    if (!task.isDeleted)
                      InkWell(
                        onTap: onToggleExpand,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (allDone)
                                const Icon(Icons.check_circle, size: 14, color: Colors.green)
                              else if (hasProgress)
                                Icon(Icons.checklist, size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                allDone ? '已完成' : '$doneCount/$totalCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: allDone ? Colors.green : Colors.grey.shade600,
                                  fontWeight: allDone ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                isExpanded ? Icons.expand_less : Icons.expand_more,
                                size: 16, color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),

          // 展开的子任务区域
          if (isExpanded && hasSubtasks)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                children: subTasks.asMap().entries.map((e) =>
                  _subTaskRow(e.value, e.key, subTasks.length, context)
                ).toList(),
              ),
            ),
          if (isExpanded && !hasSubtasks)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Text('还没有子任务，点击卡片进入详情添加',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
            ),
        ],
      ),
    );
  }

  Widget _subTaskRow(SubTask st, int index, int total, BuildContext context) {
    return _SubTaskRowWidget(
      st: st,
      index: index,
      total: total,
      onToggleSubTask: onToggleSubTask,
      onDeleteSubTask: onDeleteSubTask,
      onMoveSubTaskUp: onMoveSubTaskUp,
      onMoveSubTaskDown: onMoveSubTaskDown,
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _buildMenu(bool allDone) {
    if (task.isDeleted) {
      return PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'restore') onRestore?.call();
          if (v == 'perm_delete') onPermanentDelete?.call();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'restore', child: Text('恢复')),
          const PopupMenuItem(value: 'perm_delete', child: Text('永久删除')),
        ],
      );
    }
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
        if (v == 'move_up') onMoveUp?.call();
        if (v == 'move_down') onMoveDown?.call();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
        if (onMoveUp != null && canMoveUp)
          const PopupMenuItem(value: 'move_up', child: Text('⬆ 上移')),
        if (onMoveDown != null && canMoveDown)
          const PopupMenuItem(value: 'move_down', child: Text('⬇ 下移')),
      ],
    );
  }

  String get _remainingDays {
    if (task.deletedAt == null) return '';
    return '${15 - DateTime.now().difference(task.deletedAt!).inDays}';
  }

}

// ── 子任务行（StatefulWidget，MouseRegion hover）──

class _SubTaskRowWidget extends StatefulWidget {
  final SubTask st;
  final int index;
  final int total;
  final void Function(SubTask st)? onToggleSubTask;
  final void Function(SubTask st)? onDeleteSubTask;
  final void Function(SubTask st)? onMoveSubTaskUp;
  final void Function(SubTask st)? onMoveSubTaskDown;

  const _SubTaskRowWidget({
    required this.st,
    required this.index,
    required this.total,
    this.onToggleSubTask,
    this.onDeleteSubTask,
    this.onMoveSubTaskUp,
    this.onMoveSubTaskDown,
  });

  @override
  State<_SubTaskRowWidget> createState() => _SubTaskRowWidgetState();
}

class _SubTaskRowWidgetState extends State<_SubTaskRowWidget> {
  bool _hovered = false;

  void _showContextMenu(Offset position) {
    final st = widget.st;
    final i = widget.index;
    final total = widget.total;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (widget.onMoveSubTaskUp != null && i > 0 && !st.isDeleted)
          const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
        if (widget.onMoveSubTaskDown != null && i < total - 1 && !st.isDeleted)
          const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
        if (st.isDeleted)
          const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
        PopupMenuItem(value: 'delete', child: Text(st.isDeleted ? '🗑 永久删除' : '🗑 删除')),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'up': widget.onMoveSubTaskUp?.call(st); break;
        case 'down': widget.onMoveSubTaskDown?.call(st); break;
        case 'restore': widget.onDeleteSubTask?.call(st); break;
        case 'delete': widget.onDeleteSubTask?.call(st); break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    return Padding(
      padding: EdgeInsets.only(left: st.level * 20.0 + 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition),
          child: Container(
            decoration: BoxDecoration(
              color: _hovered ? Colors.grey.shade300 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: st.isDone,
                  onChanged: (_) => widget.onToggleSubTask?.call(st),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onToggleSubTask?.call(st),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          st.title,
                          style: TextStyle(
                            fontSize: 16,
                            decoration: (st.isDone || st.isDeleted) ? TextDecoration.lineThrough : null,
                            color: (st.isDone || st.isDeleted) ? Colors.grey : null,
                          ),
                        ),
                        if (st.dueDate != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${st.isOverdue ? "已过期 " : ""}${fmtDateTime(st.dueDate, st.reminderTime)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: st.isOverdue ? Colors.red : Colors.grey.shade500,
                              fontWeight: st.isOverdue ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  iconSize: 20,
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                  onSelected: (v) {
                    switch (v) {
                      case 'up': widget.onMoveSubTaskUp?.call(st); break;
                      case 'down': widget.onMoveSubTaskDown?.call(st); break;
                      case 'restore': widget.onDeleteSubTask?.call(st); break;
                      case 'delete': widget.onDeleteSubTask?.call(st); break;
                    }
                  },
                  itemBuilder: (_) => [
                    if (widget.onMoveSubTaskUp != null && widget.index > 0 && !st.isDeleted)
                      const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
                    if (widget.onMoveSubTaskDown != null && widget.index < widget.total - 1 && !st.isDeleted)
                      const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
                    if (st.isDeleted)
                      const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
                    PopupMenuItem(value: 'delete', child: Text(st.isDeleted ? '🗑 永久删除' : '🗑 删除')),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
