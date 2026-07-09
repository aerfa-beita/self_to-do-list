import 'package:flutter/material.dart';
import '../models/memo.dart';
import '../utils/date_utils.dart';

/// 备忘录卡片（树形）——无 checkbox，支持展开/折叠/排序/层级操作
class MemoItem extends StatelessWidget {
  final Memo memo;
  final int index;
  final int total;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onPromote;
  final VoidCallback? onDemote;
  final VoidCallback? onAddChild;
  final VoidCallback onDelete;
  final VoidCallback? onRestore;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;

  const MemoItem({
    super.key,
    required this.memo,
    required this.index,
    required this.total,
    required this.hasChildren,
    required this.isExpanded,
    required this.onTap,
    required this.onToggleExpand,
    this.onMoveUp,
    this.onMoveDown,
    this.onPromote,
    this.onDemote,
    this.onAddChild,
    required this.onDelete,
    this.onRestore,
    this.selectMode = false,
    this.isSelected = false,
    this.onSelectToggle,
  });

  void _showContextMenu(Offset position, BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (onMoveUp != null && index > 0 && !memo.isDeleted)
          const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
        if (onMoveDown != null && index < total - 1 && !memo.isDeleted)
          const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
        if (onPromote != null && !memo.isDeleted)
          const PopupMenuItem(value: 'promote', child: Text('← 提升')),
        if (onDemote != null && index > 0 && !memo.isDeleted)
          const PopupMenuItem(value: 'demote', child: Text('→ 降入')),
        if (onAddChild != null && !memo.isDeleted)
          const PopupMenuItem(value: 'add_child', child: Text('＋ 添加子项')),
        if (memo.isDeleted)
          const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
        PopupMenuItem(value: 'delete', child: Text(memo.isDeleted ? '🗑 永久删除' : '🗑 删除')),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'up': onMoveUp?.call(); break;
        case 'down': onMoveDown?.call(); break;
        case 'promote': onPromote?.call(); break;
        case 'demote': onDemote?.call(); break;
        case 'add_child': onAddChild?.call(); break;
        case 'delete': onDelete(); break;
        case 'restore': onRestore?.call(); break;
      }
    });
  }

  Widget _chip(String label) {
    final color = categoryColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indent = memo.level * 24.0;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: GestureDetector(
          onSecondaryTapUp: selectMode ? null : (details) => _showContextMenu(details.globalPosition, context),
          child: InkWell(
            onTap: selectMode ? onSelectToggle : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectMode)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => onSelectToggle?.call(),
                ),
              // 展开/折叠
              GestureDetector(
                onTap: onToggleExpand,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18, color: Colors.grey.shade500,
                  ),
                ),
              ),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(memo.content,
                        style: TextStyle(
                          fontSize: 16,
                          decoration: memo.isDeleted ? TextDecoration.lineThrough : null,
                          color: memo.isDeleted ? Colors.grey : null,
                        )),
                    const SizedBox(height: 4),
                    Row(children: [
                      _chip(memo.category),
                      const SizedBox(width: 8),
                      Text(fmtRelativeTime(memo.createdAt),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      if (memo.dueDate != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.event, size: 10,
                            color: memo.isOverdue ? Colors.red : Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Text(
                          memo.isOverdue ? '已过期 ${fmtDateTime(memo.dueDate, memo.reminderTime)}' : fmtDateTime(memo.dueDate, memo.reminderTime),
                          style: TextStyle(
                            fontSize: 10,
                            color: memo.isOverdue ? Colors.red : Colors.grey.shade500,
                            fontWeight: memo.isOverdue ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              // 集合菜单（选择模式下隐藏）
              if (!selectMode)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(Icons.more_vert, color: Colors.grey.shade500),
                onSelected: (v) {
                  switch (v) {
                    case 'up': onMoveUp?.call(); break;
                    case 'down': onMoveDown?.call(); break;
                    case 'promote': onPromote?.call(); break;
                    case 'demote': onDemote?.call(); break;
                    case 'add_child': onAddChild?.call(); break;
                    case 'delete': onDelete(); break;
                    case 'restore': onRestore?.call(); break;
                  }
                },
                itemBuilder: (_) => [
                  if (onMoveUp != null && index > 0 && !memo.isDeleted)
                    const PopupMenuItem(value: 'up', child: Text('⬆ 上移')),
                  if (onMoveDown != null && index < total - 1 && !memo.isDeleted)
                    const PopupMenuItem(value: 'down', child: Text('⬇ 下移')),
                  if (onPromote != null && !memo.isDeleted)
                    const PopupMenuItem(value: 'promote', child: Text('← 提升')),
                  if (onDemote != null && index > 0 && !memo.isDeleted)
                    const PopupMenuItem(value: 'demote', child: Text('→ 降入')),
                  if (onAddChild != null && !memo.isDeleted)
                    const PopupMenuItem(value: 'add_child', child: Text('＋ 添加子项')),
                  if (memo.isDeleted)
                    const PopupMenuItem(value: 'restore', child: Text('↩ 恢复')),
                  PopupMenuItem(value: 'delete', child: Text(memo.isDeleted ? '🗑 永久删除' : '🗑 删除')),
                ],
              ),
            ],
          ),
        ),
      ),
        ), // GestureDetector
      ), // Card
    );
  }
}
