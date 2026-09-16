import 'package:flutter/material.dart';

import '../models/task.dart';

class DeletedTaskCard extends StatelessWidget {
  const DeletedTaskCard({
    super.key,
    required this.task,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final Task task;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  String get _scopeLabel => switch (task.deletedScope) {
    Task.actionScopeStage => '阶段',
    Task.actionScopeWeek => '本周',
    _ => '收件箱',
  };

  String get _deletedAtLabel {
    final value = task.deletedAt;
    if (value == null) return '删除时间未知';
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '删除于 ${value.month}月${value.day}日 $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('deleted-task-${task.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 0,
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = _DeletedTaskContent(
            taskId: task.id,
            title: task.title,
            scopeLabel: _scopeLabel,
            deletedAtLabel: _deletedAtLabel,
          );
          final actions = _DeletedTaskActions(
            taskId: task.id,
            onRestore: onRestore,
            onPermanentDelete: onPermanentDelete,
          );
          if (constraints.maxWidth < 350) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: content),
                const SizedBox(width: 8),
                actions,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeletedTaskContent extends StatelessWidget {
  const _DeletedTaskContent({
    required this.taskId,
    required this.title,
    required this.scopeLabel,
    required this.deletedAtLabel,
  });

  final int? taskId;
  final String title;
  final String scopeLabel;
  final String deletedAtLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: ValueKey('deleted-task-title-$taskId'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withAlpha(120),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  '来自 $scopeLabel',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            Text(
              deletedAtLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeletedTaskActions extends StatelessWidget {
  const _DeletedTaskActions({
    required this.taskId,
    required this.onRestore,
    required this.onPermanentDelete,
  });

  final int? taskId;
  final VoidCallback onRestore;
  final VoidCallback onPermanentDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          key: ValueKey('deleted-task-restore-$taskId'),
          onPressed: onRestore,
          icon: const Icon(Icons.restore_outlined, size: 20),
          label: const Text('恢复'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: PopupMenuButton<String>(
            key: ValueKey('deleted-task-more-$taskId'),
            tooltip: '更多删除操作',
            icon: const Icon(Icons.more_vert),
            iconSize: 22,
            onSelected: (value) {
              if (value == 'permanent_delete') onPermanentDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'permanent_delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever_outlined,
                      size: 20,
                      color: colors.error,
                    ),
                    const SizedBox(width: 12),
                    Text('永久删除', style: TextStyle(color: colors.error)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
