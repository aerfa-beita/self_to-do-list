import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/widgets/deleted_task_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('deleted task card fits ${width.toInt()}dp', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeletedTaskCard(
              task: Task(
                id: 7,
                title: '整理北京出差的行程安排，包括机票酒店预订、会议资料准备以及与客户的沟通要点',
                deletedAt: DateTime(2026, 9, 16, 20, 23),
                deletedScope: Task.actionScopeWeek,
              ),
              onRestore: () {},
              onPermanentDelete: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('来自 本周'), findsOneWidget);
      expect(find.text('删除于 9月16日 20:23'), findsOneWidget);
      expect(find.text('恢复'), findsOneWidget);
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('deleted-task-title-7')),
      );
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });
  }

  testWidgets('permanent delete stays in the overflow menu', (tester) async {
    var permanentlyDeleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeletedTaskCard(
            task: Task(
              id: 8,
              title: '待永久删除任务',
              deletedAt: DateTime(2026, 9, 16, 18, 47),
              deletedScope: Task.actionScopeStage,
            ),
            onRestore: () {},
            onPermanentDelete: () => permanentlyDeleted = true,
          ),
        ),
      ),
    );

    expect(find.text('永久删除'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('deleted-task-more-8')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    expect(permanentlyDeleted, isTrue);
  });
}
