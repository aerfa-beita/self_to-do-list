import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/services/companion_dialogue_service.dart';
import 'package:todo_list/widgets/workload_companion.dart';

void main() {
  testWidgets('chibi companion renders and completes an articulated walk', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkloadCompanion(
            current: 3,
            limit: 8,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byType(WorkloadCompanion), findsOneWidget);
    expect(find.byKey(const ValueKey('companion-mascot-idle')), findsOneWidget);
    await tester.tap(find.byType(WorkloadCompanion));
    expect(tapped, isTrue);

    final state = tester.state<WorkloadCompanionState>(
      find.byType(WorkloadCompanion),
    );
    state.startJourney(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump(const Duration(milliseconds: 310));

    expect(tester.takeException(), isNull);
  });

  testWidgets('companion exposes the five-state visual state machine', (
    tester,
  ) async {
    final key = GlobalKey<WorkloadCompanionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkloadCompanion(key: key, current: 3, limit: 8, onTap: () {}),
        ),
      ),
    );

    for (final state in [
      CompanionState.checkTask,
      CompanionState.celebrate,
      CompanionState.sleepy,
      CompanionState.reminder,
    ]) {
      key.currentState!.showState(state, duration: const Duration(seconds: 2));
      await tester.pump();
      expect(
        find.byKey(ValueKey('companion-mascot-${state.name}')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('upcoming reminder selects reminder state automatically', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkloadCompanion(
            current: 3,
            limit: 8,
            reminderActive: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('companion-mascot-reminder')),
      findsOneWidget,
    );
  });

  testWidgets('companion walks over and carries the task with both hands', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: CompanionTaskEvent(taskTitle: '超出今日负荷的任务', ratio: 1.25),
          ),
        ),
      ),
    );

    expect(find.text('小精灵正跑过去…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    expect(find.text('抱稳啦，慢慢搬回去'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('轻轻放进精灵窝'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact companion keeps the mobile header short', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkloadCompanion(
            current: 5,
            limit: 8,
            compact: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(WorkloadCompanion)), const Size(72, 50));
    expect(find.text('5/8'), findsOneWidget);
  });

  testWidgets('edge companion peeks, talks locally, then opens settings', (
    tester,
  ) async {
    var settingsOpened = false;
    final key = GlobalKey<WorkloadCompanionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: WorkloadCompanion(
              key: key,
              current: 2,
              limit: 8,
              edgePeek: true,
              onTap: () => settingsOpened = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(WorkloadCompanion)), const Size(48, 48));
    await tester.runAsync(
      () => key.currentState!.showRandomDialogue(
        CompanionDialogueMoment.idle,
        cooldown: Duration.zero,
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('companion-dialogue')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('companion-edge-tap-target')));
    await tester.pump();
    expect(settingsOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edge companion can be dragged and reports drag end', (
    tester,
  ) async {
    var delta = Offset.zero;
    var ended = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: WorkloadCompanion(
              current: 2,
              limit: 8,
              edgePeek: true,
              onTap: () {},
              onDragUpdate: (value) => delta += value,
              onDragEnd: () => ended = true,
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('companion-edge-tap-target')),
      const Offset(-30, 45),
    );
    await tester.pump();

    expect(delta.distance, greaterThan(10));
    expect(ended, isTrue);
  });
}
