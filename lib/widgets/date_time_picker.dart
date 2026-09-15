import 'package:flutter/material.dart';

/// 日期 + 时间选择器——复用组件
/// 用于 task 新建/编辑、memo 编辑、子任务编辑
class DateTimePicker extends StatelessWidget {
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final ValueChanged<DateTime?> onDateChanged;
  final ValueChanged<DateTime?> onTimeChanged;

  const DateTimePicker({
    super.key,
    required this.dueDate,
    required this.reminderTime,
    required this.onDateChanged,
    required this.onTimeChanged,
  });

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('zh'),
    );
    if (picked != null) onDateChanged(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final initial = reminderTime != null
        ? TimeOfDay(hour: reminderTime!.hour, minute: reminderTime!.minute)
        : TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      onTimeChanged(DateTime(2024, 1, 1, picked.hour, picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(context),
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
                  onTap: () => _pickTime(context),
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
                        color: reminderTime != null ? null : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (dueDate != null)
          TextButton(
            onPressed: () {
              onDateChanged(null);
              onTimeChanged(null);
            },
            child: const Text('清除日期', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
