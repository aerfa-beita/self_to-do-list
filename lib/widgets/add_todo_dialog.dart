import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AddTaskDialog extends StatefulWidget {
  final String? initialTitle;
  final String? initialNote;
  final String? initialCategory;
  final DateTime? initialDueDate;
  final DateTime? initialReminderTime;
  final String? initialRepeatType;
  final int initialEffortPoints;
  final List<String> categories;
  final bool showScheduleFields;

  const AddTaskDialog({
    super.key,
    this.initialTitle,
    this.initialNote,
    this.initialCategory,
    this.initialDueDate,
    this.initialReminderTime,
    this.initialRepeatType,
    this.initialEffortPoints = 2,
    this.categories = const ['默认', '工作', '学习', '生活', '重要'],
    this.showScheduleFields = true,
  });

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late String _category;
  DateTime? _dueDate;
  DateTime? _reminderTime;
  String? _repeatType;
  late int _effortPoints;

  bool get isEditing => widget.initialTitle != null;

  bool get _countsTowardToday {
    if (_dueDate == null) return false;
    final now = DateTime.now();
    return _dueDate!.year == now.year &&
        _dueDate!.month == now.month &&
        _dueDate!.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _noteController = TextEditingController(text: widget.initialNote ?? '');
    _category =
        widget.initialCategory ??
        (widget.categories.isNotEmpty ? widget.categories.first : '默认');
    _dueDate = widget.initialDueDate;
    _reminderTime = widget.initialReminderTime;
    _repeatType = widget.initialRepeatType;
    _effortPoints = widget.initialEffortPoints;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) return;
    Navigator.pop(context, {
      'title': _titleController.text.trim(),
      'note': _noteController.text.trim(),
      'category': _category,
      'due_date': _dueDate?.toIso8601String(),
      'reminder_time': _reminderTime?.toIso8601String(),
      'repeat_type': _repeatType,
      'effort_points': _effortPoints.toString(),
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('zh'),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final initial = _reminderTime != null
        ? TimeOfDay(hour: _reminderTime!.hour, minute: _reminderTime!.minute)
        : TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(
        () => _reminderTime = DateTime(2024, 1, 1, picked.hour, picked.minute),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MM/dd (E)', 'zh');

    return AlertDialog(
      title: Text(isEditing ? '编辑任务' : '新建任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: '标题',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: '备忘录内容（可选）',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: widget.categories.contains(_category) ? _category : null,
              decoration: const InputDecoration(
                labelText: '分类',
                border: OutlineInputBorder(),
              ),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _effortPoints,
              decoration: const InputDecoration(
                labelText: '心力值',
                helperText: '轻松 1 / 普通 2 / 费力 3',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('轻松 · 1')),
                DropdownMenuItem(value: 2, child: Text('普通 · 2')),
                DropdownMenuItem(value: 3, child: Text('费力 · 3')),
              ],
              onChanged: (value) => setState(() => _effortPoints = value ?? 2),
            ),
            if (widget.showScheduleFields) ...[
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: _countsTowardToday,
                title: const Text('计入今日负荷'),
                subtitle: const Text('开启后，心力值会显示在小花精灵旁'),
                secondary: const Icon(Icons.local_florist_outlined),
                onChanged: (enabled) {
                  setState(() {
                    if (enabled) {
                      final now = DateTime.now();
                      _dueDate = DateTime(now.year, now.month, now.day);
                    } else if (_countsTowardToday) {
                      _dueDate = null;
                      _reminderTime = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 6),
              // 截止日期
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '截止日期',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                    _dueDate != null ? df.format(_dueDate!) : '点击选择（可选）',
                    style: TextStyle(
                      color: _dueDate != null ? null : Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              if (_dueDate != null) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _repeatType,
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
                  onChanged: (v) => setState(() => _repeatType = v),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '提醒时间',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.access_time, size: 18),
                    ),
                    child: Text(
                      _reminderTime != null
                          ? '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}'
                          : '点击设置提醒（可选）',
                      style: TextStyle(
                        color: _reminderTime != null
                            ? null
                            : Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _dueDate = null;
                    _reminderTime = null;
                  }),
                  child: const Text('清除日期', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(isEditing ? '保存' : '创建')),
      ],
    );
  }
}
