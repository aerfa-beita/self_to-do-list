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
  final ValueChanged<String>? onMoveToMode;
  final void Function(BuildContext context)? onMoveToStage;
  final void Function(BuildContext context)? onMoveToWeek;
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
  final VoidCallback? onComplete;
  final bool reorderable;
  final int? reorderIndex;
  final bool managementOnly;

  const TaskItem({
    super.key,
    required this.task,
    required this.doneCount,
    required this.totalCount,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.onMoveToMode,
    this.onMoveToStage,
    this.onMoveToWeek,
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
    this.onComplete,
    this.reorderable = false,
    this.reorderIndex,
    this.managementOnly = false,
  });

  static Widget _menuLabel(IconData icon, String label, {Color? color}) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Text(label, style: color == null ? null : TextStyle(color: color)),
    ],
  );

  void _showTaskMenu(Offset position, BuildContext context) {
    if (task.isDeleted) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 12),
              Text('编辑'),
            ],
          ),
        ),
        if (onMoveToStage != null)
          const PopupMenuItem(
            value: 'move_stage',
            child: Row(
              children: [
                Icon(Icons.view_kanban_outlined, size: 20),
                SizedBox(width: 12),
                Text('移到阶段'),
              ],
            ),
          ),
        if (onMoveToWeek != null)
          const PopupMenuItem(
            value: 'move_week',
            child: Row(
              children: [
                Icon(Icons.calendar_view_week_outlined, size: 20),
                SizedBox(width: 12),
                Text('移到本周'),
              ],
            ),
          ),
        if (onMoveToStage == null &&
            onMoveToWeek == null &&
            onMoveToMode != null)
          if (task.isArranged)
            const PopupMenuItem(value: 'move_back', child: Text('移回收件箱'))
          else ...[
            const PopupMenuItem(value: 'plan_now', child: Text('移到：现在')),
            const PopupMenuItem(value: 'plan_next', child: Text('移到：接下来')),
            const PopupMenuItem(value: 'plan_later', child: Text('移到：稍后')),
          ],
        if (!managementOnly) const PopupMenuDivider(),
        if (!managementOnly)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: Colors.red),
                SizedBox(width: 12),
                Text('删除', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
      ],
    ).then((v) {
      if (v == null) return;
      if (!context.mounted) return;
      if (v == 'edit') onEdit();
      if (v == 'move_stage') onMoveToStage?.call(context);
      if (v == 'move_week') onMoveToWeek?.call(context);
      if (v == 'move_back') onMoveToMode?.call(Task.normalMode);
      if (v == 'plan_now') onMoveToMode?.call(Task.planNowMode);
      if (v == 'plan_next') onMoveToMode?.call(Task.planNextMode);
      if (v == 'plan_later') onMoveToMode?.call(Task.planLaterMode);
      if (v == 'delete') onDelete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasProgress = totalCount > 0;
    final allDone =
        task.isCompleted || (hasProgress && doneCount == totalCount);
    final catColor = categoryColor(task.category);
    final hasSubtasks = subTasks.isNotEmpty;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    if (MediaQuery.sizeOf(context).width < 900) {
      return _buildCompactTask(context);
    }

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: task.isDeleted
                ? null
                : (selectMode ? onSelectToggle : onTap),
            onLongPress: null,
            onSecondaryTapUp: selectMode
                ? null
                : (task.isDeleted
                      ? null
                      : (details) {
                          _showTaskMenu(details.globalPosition, context);
                        }),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  if (selectMode)
                    Checkbox(
                      value: isSelected,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => onSelectToggle?.call(),
                    )
                  else if (!task.isDeleted && !managementOnly)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: allDone ? '已完成' : '完成',
                      onPressed: onComplete,
                      icon: Icon(
                        allDone
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: allDone ? Colors.green : Colors.grey.shade500,
                        size: 20,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: (allDone || task.isDeleted)
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isDeleted || allDone ? Colors.grey : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (task.isArranged) ...[
                    if (isNarrow)
                      Tooltip(
                        message: '已安排到${task.arrangementLabel}',
                        child: Icon(
                          Icons.account_tree_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    else
                      _chip(
                        task.arrangementLabel,
                        Theme.of(context).colorScheme.primary,
                      ),
                    const SizedBox(width: 6),
                  ],
                  _chip(task.category, catColor),
                  if (!isNarrow && task.dueDate != null && !task.isDeleted) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.event_outlined,
                      size: 13,
                      color: task.isOverdue ? Colors.red : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      fmtDateTime(task.dueDate, task.reminderTime),
                      style: TextStyle(
                        fontSize: 11,
                        color: task.isOverdue
                            ? Colors.red
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  if (!task.isDeleted)
                    InkWell(
                      onTap: onToggleExpand,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isNarrow)
                              Text(
                                '$doneCount/$totalCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (task.isDeleted && task.deletedAt != null) ...[
                    Text(
                      '删除于 ${task.deletedAt!.month}月${task.deletedAt!.day}日',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                  _buildMenu(allDone, context),
                ],
              ),
            ),
          ),

          // 展开的子任务区域
          if (isExpanded && hasSubtasks)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Column(
                children: subTasks
                    .asMap()
                    .entries
                    .map(
                      (e) =>
                          _subTaskRow(e.value, e.key, subTasks.length, context),
                    )
                    .toList(),
              ),
            ),
          if (isExpanded && !hasSubtasks)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Text(
                '还没有子任务，点击卡片进入详情添加',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
              ),
            ),
        ],
      ),
    );
    if (task.isDeleted || selectMode) return card;
    return Dismissible(
      key: ValueKey('task-swipe-${task.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('更多操作', style: TextStyle(color: Colors.white)),
            SizedBox(width: 8),
            Icon(Icons.more_horiz, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑'),
                  onTap: () => Navigator.pop(sheetContext, 'edit'),
                ),
                if (onMoveToMode != null)
                  if (task.isArranged)
                    ListTile(
                      leading: const Icon(Icons.view_list_outlined),
                      title: const Text('移回收件箱'),
                      onTap: () => Navigator.pop(sheetContext, 'move_back'),
                    )
                  else ...[
                    ListTile(
                      leading: const Icon(Icons.play_arrow_outlined),
                      title: const Text('移到：现在'),
                      onTap: () => Navigator.pop(sheetContext, 'plan_now'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('移到：接下来'),
                      onTap: () => Navigator.pop(sheetContext, 'plan_next'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.hourglass_bottom_outlined),
                      title: const Text('移到：稍后'),
                      onTap: () => Navigator.pop(sheetContext, 'plan_later'),
                    ),
                  ],
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('删除', style: TextStyle(color: Colors.red)),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
              ],
            ),
          ),
        );
        if (!context.mounted) return false;
        if (action == 'edit') onEdit();
        if (action == 'move_back') onMoveToMode?.call(Task.normalMode);
        if (action == 'plan_now') onMoveToMode?.call(Task.planNowMode);
        if (action == 'plan_next') onMoveToMode?.call(Task.planNextMode);
        if (action == 'plan_later') onMoveToMode?.call(Task.planLaterMode);
        if (action == 'delete') onDelete();
        return false;
      },
      child: card,
    );
  }

  Widget _buildCompactTask(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasProgress = totalCount > 0;
    final allDone =
        task.isCompleted || (hasProgress && doneCount == totalCount);
    final catColor = categoryColor(task.category);
    final canDrag =
        reorderable && reorderIndex != null && !task.isDeleted && !selectMode;
    final meta = <Widget>[
      _compactMeta(task.category, catColor),
      if (task.dueDate != null && !task.isDeleted)
        _compactMeta(
          fmtDateTime(task.dueDate, task.reminderTime),
          task.isOverdue ? colors.error : colors.onSurfaceVariant,
        ),
      if (task.deletedAt != null)
        _compactMeta(
          '删除于 ${task.deletedAt!.month}月${task.deletedAt!.day}日',
          colors.onSurfaceVariant,
        ),
      if (hasProgress)
        _compactMeta('子任务 $doneCount/$totalCount', colors.onSurfaceVariant),
    ];
    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withAlpha(130)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (selectMode)
            Checkbox(
              value: isSelected,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => onSelectToggle?.call(),
            )
          else if (!task.isDeleted && !managementOnly)
            SizedBox(
              width: 48,
              height: 56,
              child: IconButton(
                tooltip: allDone ? '已完成' : '完成',
                onPressed: onComplete,
                icon: Icon(
                  allDone ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: allDone ? Colors.green : colors.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          Expanded(
            child: InkWell(
              onTap: task.isDeleted
                  ? null
                  : (selectMode ? onSelectToggle : onTap),
              onLongPress: null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        decoration: allDone && !task.isDeleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isDeleted || allDone
                            ? colors.onSurfaceVariant
                            : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(spacing: 6, runSpacing: 2, children: meta),
                  ],
                ),
              ),
            ),
          ),
          if (!selectMode)
            SizedBox(
              width: 48,
              height: 56,
              child: _buildMenu(allDone, context),
            ),
        ],
      ),
    );
    if (task.isDeleted || selectMode) return card;
    final swipeCard = Dismissible(
      key: ValueKey('task-swipe-${task.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.more_horiz, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑'),
                  onTap: () => Navigator.pop(sheetContext, 'edit'),
                ),
                if (onMoveToStage != null)
                  ListTile(
                    minTileHeight: 48,
                    leading: const Icon(Icons.view_kanban_outlined, size: 20),
                    title: const Text('移到阶段'),
                    onTap: () => Navigator.pop(sheetContext, 'move_stage'),
                  ),
                if (onMoveToWeek != null)
                  ListTile(
                    minTileHeight: 48,
                    leading: const Icon(
                      Icons.calendar_view_week_outlined,
                      size: 20,
                    ),
                    title: const Text('移到本周'),
                    onTap: () => Navigator.pop(sheetContext, 'move_week'),
                  ),
                if (onMoveToStage == null &&
                    onMoveToWeek == null &&
                    onMoveToMode != null)
                  if (task.isArranged)
                    ListTile(
                      leading: const Icon(Icons.view_list_outlined),
                      title: const Text('移回收件箱'),
                      onTap: () => Navigator.pop(sheetContext, 'move_back'),
                    )
                  else ...[
                    ListTile(
                      leading: const Icon(Icons.play_arrow_outlined),
                      title: const Text('移到：现在'),
                      onTap: () => Navigator.pop(sheetContext, 'plan_now'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('移到：接下来'),
                      onTap: () => Navigator.pop(sheetContext, 'plan_next'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.hourglass_bottom_outlined),
                      title: const Text('移到：稍后'),
                      onTap: () => Navigator.pop(sheetContext, 'plan_later'),
                    ),
                  ],
                if (!managementOnly)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    title: const Text(
                      '删除',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () => Navigator.pop(sheetContext, 'delete'),
                  ),
              ],
            ),
          ),
        );
        if (!context.mounted) return false;
        if (action == 'edit') onEdit();
        if (action == 'move_stage') onMoveToStage?.call(context);
        if (action == 'move_week') onMoveToWeek?.call(context);
        if (action == 'move_back') onMoveToMode?.call(Task.normalMode);
        if (action == 'plan_now') onMoveToMode?.call(Task.planNowMode);
        if (action == 'plan_next') onMoveToMode?.call(Task.planNextMode);
        if (action == 'plan_later') onMoveToMode?.call(Task.planLaterMode);
        if (action == 'delete') onDelete();
        return false;
      },
      child: card,
    );
    if (!canDrag) return swipeCard;
    return ReorderableDelayedDragStartListener(
      index: reorderIndex!,
      child: swipeCard,
    );
  }

  Widget _compactMeta(String label, Color color) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: color),
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
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 84),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ),
    );
  }

  Widget _buildMenu(bool allDone, BuildContext context) {
    if (task.isDeleted) {
      return PopupMenuButton<String>(
        key: Key('task-more-${task.id}'),
        tooltip: '更多任务操作',
        icon: const Icon(Icons.more_vert),
        iconSize: 22,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onSelected: (v) {
          if (v == 'restore') onRestore?.call();
          if (v == 'perm_delete') onPermanentDelete?.call();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'restore',
            child: _menuLabel(Icons.restore_outlined, '恢复'),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'perm_delete',
            child: _menuLabel(
              Icons.delete_forever_outlined,
              '永久删除',
              color: Colors.red,
            ),
          ),
        ],
      );
    }
    return PopupMenuButton<String>(
      key: Key('task-more-${task.id}'),
      tooltip: '更多任务操作',
      icon: const Icon(Icons.more_vert),
      iconSize: 22,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'move_stage') onMoveToStage?.call(context);
        if (v == 'move_week') onMoveToWeek?.call(context);
        if (v == 'move_back') onMoveToMode?.call(Task.normalMode);
        if (v == 'plan_now') onMoveToMode?.call(Task.planNowMode);
        if (v == 'plan_next') onMoveToMode?.call(Task.planNextMode);
        if (v == 'plan_later') onMoveToMode?.call(Task.planLaterMode);
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: _menuLabel(Icons.edit_outlined, '编辑'),
        ),
        if (onMoveToStage != null)
          PopupMenuItem(
            value: 'move_stage',
            child: _menuLabel(Icons.view_kanban_outlined, '移到阶段'),
          ),
        if (onMoveToWeek != null)
          PopupMenuItem(
            value: 'move_week',
            child: _menuLabel(Icons.calendar_view_week_outlined, '移到本周'),
          ),
        if (onMoveToStage == null &&
            onMoveToWeek == null &&
            onMoveToMode != null)
          if (task.isArranged)
            const PopupMenuItem(value: 'move_back', child: Text('移回收件箱'))
          else ...[
            const PopupMenuItem(value: 'plan_now', child: Text('移到：现在')),
            const PopupMenuItem(value: 'plan_next', child: Text('移到：接下来')),
            const PopupMenuItem(value: 'plan_later', child: Text('移到：稍后')),
          ],
        if (!managementOnly) const PopupMenuDivider(),
        if (!managementOnly)
          PopupMenuItem(
            value: 'delete',
            child: _menuLabel(Icons.delete_outline, '删除', color: Colors.red),
          ),
      ],
    );
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
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (widget.onMoveSubTaskUp != null && i > 0 && !st.isDeleted)
          const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
        if (widget.onMoveSubTaskDown != null && i < total - 1 && !st.isDeleted)
          const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
        if (st.isDeleted)
          const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
        PopupMenuItem(
          value: 'delete',
          child: Text(st.isDeleted ? '🗑 永久删除' : '🗑 删除'),
        ),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'up':
          widget.onMoveSubTaskUp?.call(st);
          break;
        case 'down':
          widget.onMoveSubTaskDown?.call(st);
          break;
        case 'restore':
          widget.onDeleteSubTask?.call(st);
          break;
        case 'delete':
          widget.onDeleteSubTask?.call(st);
          break;
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
                            decoration: (st.isDone || st.isDeleted)
                                ? TextDecoration.lineThrough
                                : null,
                            color: (st.isDone || st.isDeleted)
                                ? Colors.grey
                                : null,
                          ),
                        ),
                        if (st.dueDate != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${st.isOverdue ? "已过期 " : ""}${fmtDateTime(st.dueDate, st.reminderTime)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: st.isOverdue
                                  ? Colors.red
                                  : Colors.grey.shade500,
                              fontWeight: st.isOverdue
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
                      case 'up':
                        widget.onMoveSubTaskUp?.call(st);
                        break;
                      case 'down':
                        widget.onMoveSubTaskDown?.call(st);
                        break;
                      case 'restore':
                        widget.onDeleteSubTask?.call(st);
                        break;
                      case 'delete':
                        widget.onDeleteSubTask?.call(st);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    if (widget.onMoveSubTaskUp != null &&
                        widget.index > 0 &&
                        !st.isDeleted)
                      const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
                    if (widget.onMoveSubTaskDown != null &&
                        widget.index < widget.total - 1 &&
                        !st.isDeleted)
                      const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
                    if (st.isDeleted)
                      const PopupMenuItem(
                        value: 'restore',
                        child: Text('↩ 恢复'),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(st.isDeleted ? '🗑 永久删除' : '🗑 删除'),
                    ),
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
