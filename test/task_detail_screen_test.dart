import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/models/sub_task.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/repositories/category_repository.dart';
import 'package:todo_list/repositories/subtask_repository.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/screens/task_detail_screen.dart';
import 'package:todo_list/services/notification_service.dart';
import 'package:todo_list/services/task_service.dart';

Future<void> _loadVisualFonts() async {
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
  if (iconFont == null) fail('Cannot locate MaterialIcons-Regular.otf');
  final iconBytes = iconFont.readAsBytesSync();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
}

Future<void> _settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('subtask detail uses compact cards and icon menus', (
    tester,
  ) async {
    await _loadVisualFonts();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late Database db;
    late Task task;
    late TaskService service;
    late int mathId;
    await tester.runAsync(() async {
      db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      final taskRepository = TaskRepository(db);
      final taskId = await taskRepository.insert(Task(title: '作业'));
      task = Task(id: taskId, title: '作业');
      service = TaskService(
        taskRepository,
        SubTaskRepository(db),
        CategoryRepository(db),
      );
      mathId = await service.insertSubTask(
        SubTask(taskId: taskId, title: '数分', level: 0),
      );
      final algebraId = await service.insertSubTask(
        SubTask(
          taskId: taskId,
          title: '代数',
          level: 0,
          dueDate: DateTime(2026, 9, 16),
          reminderTime: DateTime(2024, 1, 1, 21, 30),
        ),
      );
      await service.insertSubTask(
        SubTask(taskId: taskId, parentId: algebraId, title: '整理错题', level: 1),
      );
      await service.insertSubTask(
        SubTask(taskId: taskId, title: '常微分', level: 0),
      );
    });
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          fontFamily: 'Microsoft YaHei',
          popupMenuTheme: PopupMenuThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
          ),
        ),
        home: TaskDetailScreen(
          task: task,
          taskService: service,
          notificationService: NotificationService(),
          onEditTask: (value) async => value,
        ),
      ),
    );
    await _settleUntil(tester, find.text('数分'));

    expect(find.byKey(const Key('subtask-progress-card')), findsOneWidget);
    expect(find.text('还剩 4 项'), findsOneWidget);
    expect(find.text('长按排序'), findsOneWidget);

    await tester.tap(find.byKey(Key('subtask-more-$mathId')));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsWidgets);
    expect(find.text('添加下级'), findsOneWidget);
    expect(find.text('上移'), findsNothing);
    expect(find.text('下移'), findsNothing);
    expect(find.text('删除'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/subtask_detail_mobile.png'),
    );

    await tester.tapAt(const Offset(8, 650));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
