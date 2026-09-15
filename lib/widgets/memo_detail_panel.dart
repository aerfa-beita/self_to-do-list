import 'dart:async';

import 'package:flutter/material.dart';

import '../models/memo.dart';
import '../models/task.dart';
import '../utils/date_utils.dart';

class MemoEditValue {
  const MemoEditValue({
    required this.content,
    required this.category,
    required this.dueDate,
    required this.reminderTime,
    required this.repeatType,
  });

  final String content;
  final String category;
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final String? repeatType;
}

class MemoDetailPanel extends StatefulWidget {
  const MemoDetailPanel({
    super.key,
    required this.memo,
    required this.categories,
    required this.loadLinkedTasks,
    required this.onSave,
    required this.onClose,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onCreateTodo,
    required this.onGenerateTodos,
    required this.onLinkTodo,
    required this.onToggleTask,
    this.compact = false,
  });

  final Memo memo;
  final List<String> categories;
  final Future<List<Task>> Function() loadLinkedTasks;
  final Future<void> Function(MemoEditValue value) onSave;
  final VoidCallback onClose;
  final Future<void> Function() onTogglePin;
  final Future<void> Function() onToggleArchive;
  final Future<void> Function() onCreateTodo;
  final Future<void> Function() onGenerateTodos;
  final Future<void> Function() onLinkTodo;
  final Future<void> Function(Task task) onToggleTask;
  final bool compact;

  @override
  State<MemoDetailPanel> createState() => _MemoDetailPanelState();
}

class _MemoDetailPanelState extends State<MemoDetailPanel> {
  late TextEditingController _contentController;
  late String _category;
  DateTime? _dueDate;
  DateTime? _reminderTime;
  String? _repeatType;
  Timer? _saveTimer;
  bool _saving = false;
  bool _saved = true;
  late Future<List<Task>> _linkedTasks;

  @override
  void initState() {
    super.initState();
    _applyMemo(widget.memo);
    _linkedTasks = widget.loadLinkedTasks();
  }

  @override
  void didUpdateWidget(covariant MemoDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memo.id != widget.memo.id) {
      _saveTimer?.cancel();
      _contentController.dispose();
      _applyMemo(widget.memo);
      _linkedTasks = widget.loadLinkedTasks();
    }
  }

  void _applyMemo(Memo memo) {
    _contentController = TextEditingController(text: memo.content);
    _category = memo.category;
    _dueDate = memo.dueDate;
    _reminderTime = memo.reminderTime;
    _repeatType = memo.repeatType;
    _saved = true;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _contentController.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    if (_contentController.text.trim().isEmpty) return;
    setState(() => _saved = false);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    if (_saving || _contentController.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(
      MemoEditValue(
        content: _contentController.text.trim(),
        category: _category,
        dueDate: _dueDate,
        reminderTime: _reminderTime,
        repeatType: _repeatType,
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
  }

  Future<void> _close() async {
    _saveTimer?.cancel();
    await _save();
    widget.onClose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('zh'),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
    _scheduleSave();
  }

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(_reminderTime!),
    );
    if (picked == null) return;
    setState(() {
      _reminderTime = DateTime(2024, 1, 1, picked.hour, picked.minute);
    });
    _scheduleSave();
  }

  void _refreshTasks() {
    setState(() => _linkedTasks = widget.loadLinkedTasks());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 20,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '备忘录详情',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _saving ? '正在保存…' : (_saved ? '已自动保存' : '等待保存'),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  widget.compact ? 16 : 22,
                  18,
                  widget.compact ? 16 : 22,
                  24,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.outlineVariant.withAlpha(120),
                      ),
                    ),
                    child: TextField(
                      controller: _contentController,
                      autofocus: !widget.compact,
                      minLines: 7,
                      maxLines: 16,
                      onChanged: (_) => _scheduleSave(),
                      style: const TextStyle(fontSize: 16, height: 1.65),
                      decoration: const InputDecoration.collapsed(
                        hintText: '记录此刻需要记住的内容…',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DetailChip(
                        icon: Icons.sell_outlined,
                        label: _category,
                        onTap: () => _showCategoryMenu(context),
                      ),
                      _DetailChip(
                        icon: Icons.event_outlined,
                        label: _dueDate == null
                            ? '添加日期'
                            : fmtDateTime(_dueDate, _reminderTime),
                        onTap: _pickDate,
                        onClear: _dueDate == null
                            ? null
                            : () {
                                setState(() {
                                  _dueDate = null;
                                  _reminderTime = null;
                                  _repeatType = null;
                                });
                                _scheduleSave();
                              },
                      ),
                      if (_dueDate != null)
                        _DetailChip(
                          icon: Icons.notifications_none,
                          label: _reminderTime == null
                              ? '添加提醒'
                              : '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}',
                          onTap: _pickReminder,
                        ),
                      if (_dueDate != null)
                        _DetailChip(
                          icon: Icons.repeat,
                          label: switch (_repeatType) {
                            'daily' => '每天',
                            'weekly' => '每周',
                            'monthly' => '每月',
                            _ => '不重复',
                          },
                          onTap: () => _showRepeatMenu(context),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(context, '关联任务', Icons.link),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Task>>(
                    future: _linkedTasks,
                    builder: (_, snapshot) {
                      final tasks = snapshot.data ?? const [];
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator(minHeight: 2);
                      }
                      if (tasks.isEmpty) {
                        return _EmptyLinkedTasks(
                          onPressed: () async {
                            await widget.onLinkTodo();
                            _refreshTasks();
                          },
                        );
                      }
                      return Container(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            for (final task in tasks)
                              ListTile(
                                dense: true,
                                leading: IconButton(
                                  tooltip: task.isCompleted ? '取消完成' : '完成',
                                  onPressed: () async {
                                    await widget.onToggleTask(task);
                                    _refreshTasks();
                                  },
                                  icon: Icon(
                                    task.isCompleted
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: task.isCompleted
                                        ? Colors.green
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                                title: Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: Text(task.category),
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  await widget.onLinkTodo();
                                  _refreshTasks();
                                },
                                icon: const Icon(Icons.add_link, size: 18),
                                label: const Text('关联其他 Todo'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(context, '快捷操作', Icons.bolt_outlined),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onCreateTodo,
                        icon: const Icon(Icons.add_task, size: 18),
                        label: const Text('生成一个 Todo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onGenerateTodos,
                        icon: const Icon(Icons.playlist_add_check, size: 18),
                        label: const Text('按行生成多个'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onTogglePin,
                        icon: Icon(
                          widget.memo.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                        ),
                        label: Text(widget.memo.isPinned ? '取消置顶' : '置顶'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onToggleArchive,
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: Text(widget.memo.isArchived ? '移出归档' : '归档'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }

  Future<void> _showCategoryMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择分类')),
            for (final category in widget.categories)
              ListTile(
                leading: Icon(
                  category == _category
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: category == _category
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(category),
                onTap: () => Navigator.pop(sheetContext, category),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() => _category = selected);
    _scheduleSave();
  }

  Future<void> _showRepeatMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('重复提醒')),
            for (final entry in const {
              'none': '不重复',
              'daily': '每天',
              'weekly': '每周',
              'monthly': '每月',
            }.entries)
              ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _repeatType = selected == 'none' ? null : selected);
    _scheduleSave();
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.fromLTRB(11, 7, onClear == null ? 11 : 5, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: colors.primary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 3),
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLinkedTasks extends StatelessWidget {
  const _EmptyLinkedTasks({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.link_off, color: colors.onSurfaceVariant),
          const SizedBox(height: 6),
          Text('还没有关联 Todo', style: TextStyle(color: colors.onSurfaceVariant)),
          TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add_link, size: 18),
            label: const Text('关联已有 Todo'),
          ),
        ],
      ),
    );
  }
}
