import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/widgets/schedule_prompt_dialog.dart';

void main() {
  testWidgets('schedule prompt can explicitly skip time', (tester) async {
    SchedulePromptResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<SchedulePromptResult>(
                context: context,
                builder: (_) => const SchedulePromptDialog(itemName: '测试任务'),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过时间'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.dueDate, isNull);
    expect(result!.reminderTime, isNull);
  });

  testWidgets('schedule prompt applies today before creation', (tester) async {
    SchedulePromptResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<SchedulePromptResult>(
                context: context,
                builder: (_) => const SchedulePromptDialog(itemName: '测试备忘录'),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成创建'));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    expect(result, isNotNull);
    expect(result!.dueDate?.year, today.year);
    expect(result!.dueDate?.month, today.month);
    expect(result!.dueDate?.day, today.day);
  });
}
