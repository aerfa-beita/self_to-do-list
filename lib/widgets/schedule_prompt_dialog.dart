import 'package:flutter/material.dart';

import 'date_time_picker.dart';

class SchedulePromptResult {
  const SchedulePromptResult({
    this.dueDate,
    this.reminderTime,
    this.repeatType,
  });

  final DateTime? dueDate;
  final DateTime? reminderTime;
  final String? repeatType;
}

class SchedulePromptDialog extends StatefulWidget {
  const SchedulePromptDialog({
    super.key,
    required this.itemName,
    this.initialDueDate,
    this.initialReminderTime,
    this.initialRepeatType,
  });

  final String itemName;
  final DateTime? initialDueDate;
  final DateTime? initialReminderTime;
  final String? initialRepeatType;

  @override
  State<SchedulePromptDialog> createState() => _SchedulePromptDialogState();
}

class _SchedulePromptDialogState extends State<SchedulePromptDialog> {
  DateTime? _dueDate;
  DateTime? _reminderTime;
  String? _repeatType;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.initialDueDate;
    _reminderTime = widget.initialReminderTime;
    _repeatType = widget.initialRepeatType;
  }

  DateTime _dayFromNow(int days) {
    final value = DateTime.now().add(Duration(days: days));
    return DateTime(value.year, value.month, value.day);
  }

  bool _isSameDay(DateTime? value, DateTime target) {
    return value?.year == target.year &&
        value?.month == target.month &&
        value?.day == target.day;
  }

  void _selectDay(int days) {
    setState(() => _dueDate = _dayFromNow(days));
  }

  void _finish({required bool skip}) {
    Navigator.pop(
      context,
      skip
          ? const SchedulePromptResult()
          : SchedulePromptResult(
              dueDate: _dueDate,
              reminderTime: _dueDate == null ? null : _reminderTime,
              repeatType: _dueDate == null ? null : _repeatType,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _dayFromNow(0);
    final tomorrow = _dayFromNow(1);
    return AlertDialog(
      title: const Text('设置时间'),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.itemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('今天'),
                    selected: _isSameDay(_dueDate, today),
                    onSelected: (_) => _selectDay(0),
                  ),
                  ChoiceChip(
                    label: const Text('明天'),
                    selected: _isSameDay(_dueDate, tomorrow),
                    onSelected: (_) => _selectDay(1),
                  ),
                  if (_dueDate != null)
                    ActionChip(
                      avatar: const Icon(Icons.close, size: 16),
                      label: const Text('清除'),
                      onPressed: () => setState(() {
                        _dueDate = null;
                        _reminderTime = null;
                        _repeatType = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DateTimePicker(
                dueDate: _dueDate,
                reminderTime: _reminderTime,
                onDateChanged: (value) => setState(() {
                  _dueDate = value;
                  if (value == null) {
                    _reminderTime = null;
                    _repeatType = null;
                  }
                }),
                onTimeChanged: (value) => setState(() => _reminderTime = value),
              ),
              if (_dueDate != null) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _repeatType,
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
                  onChanged: (value) => setState(() => _repeatType = value),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
        TextButton(
          onPressed: () => _finish(skip: true),
          child: const Text('跳过时间'),
        ),
        FilledButton(
          onPressed: () => _finish(skip: false),
          child: const Text('完成创建'),
        ),
      ],
    );
  }
}
