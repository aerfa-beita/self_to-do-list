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

    final monday = _task(4, '整理本周复盘', dueDate: DateTime(2026, 9, 7));
    final saturday = _task(5, '完成阶段页面验收', dueDate: DateTime(2026, 9, 12));
    await tester.pumpWidget(
      MaterialApp(
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
              allUndoneTasks: [monday, saturday],
              today: DateTime(2026, 9, 12),
              onToggleTask: (_) {},
              onOpenTask: (_) {},
              onMoveTask: (_, _) async {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTask: (_) async {},
              onAddWeeklyTask: (_) async {},
              onReorder: (_, _, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/stage_mobile.png'),
    );

    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/week_mobile.png'),
    );
  });
}
