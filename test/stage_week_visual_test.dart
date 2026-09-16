import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/screens/flow_screen.dart';

Task _task(
  int id,
  String title, {
  String mode = Task.planNowMode,
  DateTime? dueDate,
}) => Task(id: id, title: title, taskMode: mode, dueDate: dueDate);

void main() {
  testWidgets('stage and week mobile layouts match approved direction', (
    tester,
  ) async {
    final fontBytes = File('assets/fonts/msyh.ttc').readAsBytesSync();
    await (FontLoader(
      'Microsoft YaHei',
    )..addFont(Future.value(ByteData.sublistView(fontBytes)))).load();
    final separator = Platform.pathSeparator;
    var flutterRoot = File(Platform.resolvedExecutable).parent;
    File? iconFont;
    for (var depth = 0; depth < 8; depth++) {
      final candidate = File(
        '${flutterRoot.path}${separator}bin${separator}cache${separator}artifacts'
        '${separator}material_fonts${separator}MaterialIcons-Regular.otf',
      );
      if (candidate.existsSync()) {
        iconFont = candidate;
        break;
      }
      flutterRoot = flutterRoot.parent;
    }
    if (iconFont == null) {
      fail('Cannot locate Flutter MaterialIcons-Regular.otf');
    }
    final iconBytes = iconFont.readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final monday = _task(4, '整理本周复盘', dueDate: DateTime(2026, 9, 14));
    final wednesday = _task(5, '完成安排页验收', dueDate: DateTime(2026, 9, 16));
    final thursday = _task(6, '准备明天的材料', dueDate: DateTime(2026, 9, 17));
    Widget subject(ArrangementViewMode mode) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
      ),
      home: Scaffold(
        body: SafeArea(
          child: TaskArrangementView(
            nowTasks: [_task(1, '处理今天最重要的任务')],
            nextTasks: [_task(2, '准备下一步材料', mode: Task.planNextMode)],
            laterTasks: [_task(3, '记录稍后再做的想法', mode: Task.planLaterMode)],
            doneNowTasks: const [],
            doneNextTasks: const [],
            doneLaterTasks: const [],
            unplannedTasks: const [],
            allUndoneTasks: [monday, wednesday, thursday],
            allTasks: [monday, wednesday, thursday],
            today: DateTime(2026, 9, 16),
            initialMode: mode,
            onToggleTask: (_) {},
            onOpenTask: (_) {},
            onMoveTask: (_, _) async {},
            onEditTask: (_) {},
            onDeleteTask: (_) {},
            onAddTask: (_) async {},
            onAddWeeklyTask: (_) async {},
            onReorder: (_, _, _) async {},
            onOpenStatusFilter: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(subject(ArrangementViewMode.stage));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stage_mobile.png'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(subject(ArrangementViewMode.week));
    await tester.pumpAndSettle();
    final summaryRect = tester.getRect(
      find.byKey(const Key('arrangement-compact-summary')),
    );
    final todayLabelRect = tester.getRect(find.text('今日待办'));
    expect(summaryRect.top, greaterThanOrEqualTo(50));
    expect(
      todayLabelRect.center.dy,
      inInclusiveRange(summaryRect.top, summaryRect.bottom),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/week_mobile.png'),
    );
  });
}
