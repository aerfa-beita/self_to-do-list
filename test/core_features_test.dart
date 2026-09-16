import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/models/memo.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/repositories/category_repository.dart';
import 'package:todo_list/repositories/memo_repository.dart';
import 'package:todo_list/repositories/subtask_repository.dart';
import 'package:todo_list/repositories/task_memo_repository.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/services/task_service.dart';
import 'package:todo_list/services/task_memo_service.dart';
import 'package:todo_list/utils/sync_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stable sync IDs are UUID v4 values', () {
    final first = SyncId.generate();
    final second = SyncId.generate();
    expect(first, isNot(second));
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('week restoration keeps weekday in the device current week', () {
    final restored = TaskService.dateInCurrentWeek(
      DateTime(2025, 1, 1), // Wednesday
      now: DateTime(2026, 9, 15), // Tuesday
    );
    expect(restored, DateTime(2026, 9, 16));
  });

  test('legacy task maps infer completed and deleted source scopes', () {
    final stamp = DateTime(2026, 9, 15).toIso8601String();
    final stage = Task.fromMap({
      'id': 1,
      'title': '阶段完成',
      'created_at': stamp,
      'completed_at': stamp,
      'task_mode': Task.planNowMode,
    });
    final week = Task.fromMap({
      'id': 2,
      'title': '本周删除',
      'created_at': stamp,
      'deleted_at': stamp,
      'due_date': stamp,
      'task_mode': Task.normalMode,
    });
    expect(stage.completedScope, Task.actionScopeStage);
    expect(week.deletedScope, Task.actionScopeWeek);
  });

  test(
    'memo lines generate concise Todo titles without Markdown rendering',
    () {
      final titles = TaskMemoService.extractTaskTitles('''
买牛奶
- 整理桌面
2. 回复邮件
- [ ] 预约体检
- [x] 已完成项目
''');
      expect(titles, ['买牛奶', '整理桌面', '回复邮件', '预约体检']);
    },
  );

  test(
    'fresh database contains sync, workload, archive and relation schema',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      addTearDown(db.close);

      final version = await db.getVersion();
      expect(version, 23);
      final taskColumns = await db.rawQuery("PRAGMA table_info('tasks')");
      final memoColumns = await db.rawQuery("PRAGMA table_info('memos')");
      expect(
        taskColumns.map((row) => row['name']),
        containsAll([
          'sync_id',
          'updated_at',
          'effort_points',
          'companion_stashed_at',
          'task_mode',
          'week_sort_order',
          'completed_scope',
          'deleted_scope',
        ]),
      );
      expect(
        memoColumns.map((row) => row['name']),
        containsAll(['sync_id', 'pinned_at', 'archived_at']),
      );

      final taskRepository = TaskRepository(db);
      final memoRepository = MemoRepository(db);
      final linkRepository = TaskMemoRepository(db);
      final memo = Memo(content: '第一项\n- 第二项');
      final memoId = await memoRepository.insert(memo);
      final taskId = await taskRepository.insert(
        Task(title: '第一项', effortPoints: 3),
      );
      await linkRepository.link(taskId, memoId);
      await memoRepository.setPinned(memoId, true);
      await memoRepository.setArchived(memoId, true);

      expect((await linkRepository.getMemosForTask(taskId)).single.id, memoId);
      expect((await taskRepository.getById(taskId))!.effortPoints, 3);
      expect((await memoRepository.getById(memoId))!.isPinned, isTrue);
      expect((await memoRepository.getById(memoId))!.isArchived, isTrue);
      final outbox = await db.query('sync_outbox');
      expect(outbox, isNotEmpty);
      expect((await db.query('categories')).length, 5);
      expect((await db.query('memo_categories')).length, 8);
    },
  );

  test(
    'arranged tasks share Todo records without locking task or subtask completion',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      addTearDown(db.close);

      final taskRepository = TaskRepository(db);
      final service = TaskService(
        taskRepository,
        SubTaskRepository(db),
        CategoryRepository(db),
      );
      final flowId = await service.insertTask(
        Task(title: '完成课程论文', taskMode: Task.planNowMode),
      );
      var flow = (await taskRepository.getById(flowId))!;
      await service.addFlowStep(flow, '准备资料');
      await service.addFlowStep(flow, '撰写初稿');
      await service.addFlowStep(flow, '提交论文');

      expect((await service.getActiveTasks()).single.id, flowId);
      expect((await service.getFlowTasks()).single.id, flowId);
      var steps = await service.getRootSubTasks(flowId);
      expect(steps.map((step) => step.sortOrder), [0, 1, 2]);
      expect(
        await service.toggleSubTaskForTask(
          flow,
          steps[1],
          source: Task.actionScopeStage,
        ),
        isTrue,
      );
      expect(
        await service.toggleSubTaskForTask(
          flow,
          steps[0],
          source: Task.actionScopeStage,
        ),
        isTrue,
      );

      steps = await service.getRootSubTasks(flowId);
      expect(
        await service.toggleSubTaskForTask(
          flow,
          steps[2],
          source: Task.actionScopeStage,
        ),
        isTrue,
      );
      flow = (await taskRepository.getById(flowId))!;
      expect(flow.isCompleted, isTrue);
      expect(flow.completedScope, Task.actionScopeStage);

      await service.setTaskMode(flow, Task.planNextMode);
      flow = (await taskRepository.getById(flowId))!;
      expect(flow.arrangementLabel, '接下来');
      expect((await service.getFlowTasks()).single.id, flowId);

      await service.setTaskMode(flow, Task.normalMode);
      expect(await service.getFlowTasks(), isEmpty);
      expect((await service.getActiveTasks()).single.isFlow, isFalse);
    },
  );

  test('completion and deletion preserve all three action sources', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
    addTearDown(db.close);
    final repository = TaskRepository(db);
    final service = TaskService(
      repository,
      SubTaskRepository(db),
      CategoryRepository(db),
    );

    for (final scope in Task.actionScopes) {
      final id = await service.insertTask(Task(title: '来源-$scope'));
      var task = (await repository.getById(id))!;
      await service.setTaskCompleted(task, completed: true, source: scope);
      task = (await repository.getById(id))!;
      expect(task.completedScope, scope);
      await service.softDeleteTask(id, source: scope);
      task = (await repository.getById(id))!;
      expect(task.deletedScope, scope);
      await service.restoreTask(id);
      task = (await repository.getById(id))!;
      expect(task.isDeleted, isFalse);
      expect(task.isCompleted, isTrue);
      expect(task.completedScope, scope);
    }
  });

  test('version 19 adds normal task mode without changing records', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'todo_list_v19_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() async {
      final file = File(path);
      if (await file.exists()) await file.delete();
    });
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 19,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, created_at TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE subtasks(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE memos(id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, created_at TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
        },
      ),
    );
    await legacy.insert('tasks', {
      'title': '原有普通任务',
      'created_at': DateTime.now().toIso8601String(),
      'sort_order': 0,
    });
    await legacy.close();

    final migrated = await DatabaseProvider().openAtPath(path);
    addTearDown(migrated.close);
    expect(await migrated.getVersion(), 23);
    expect((await migrated.query('tasks')).single['title'], '原有普通任务');
    expect(
      (await migrated.query('tasks')).single['task_mode'],
      Task.normalMode,
    );
    expect((await migrated.query('tasks')).single['week_sort_order'], 0);
  });

  test('version 20 migration backs up data and initializes week order', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'todo_list_v20_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final backupPath = '$path.pre-v21';
    addTearDown(() async {
      for (final candidate in [
        path,
        '$path-wal',
        '$path-shm',
        backupPath,
        '$backupPath-wal',
        '$backupPath-shm',
      ]) {
        final file = File(candidate);
        if (await file.exists()) await file.delete();
      }
    });
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 20,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, created_at TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE memos(id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, created_at TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE subtasks(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
        },
      ),
    );
    await legacy.insert('tasks', {
      'title': '迁移前任务',
      'created_at': DateTime(2026, 9, 15).toIso8601String(),
      'sort_order': 7,
    });
    await legacy.close();

    final migrated = await DatabaseProvider().openAtPath(path);
    addTearDown(migrated.close);
    expect(await migrated.getVersion(), 23);
    expect(await File(backupPath).exists(), isTrue);
    final row = (await migrated.query('tasks')).single;
    expect(row['title'], '迁移前任务');
    expect(row['sort_order'], 7);
    expect(row['week_sort_order'], 7);
  });

  test('version 21 migration backs up and infers action scopes', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'todo_list_v21_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final backupPath = '$path.pre-v22';
    addTearDown(() async {
      for (final candidate in [path, backupPath]) {
        final file = File(candidate);
        if (await file.exists()) await file.delete();
      }
    });
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 21,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE tasks(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              created_at TEXT NOT NULL,
              completed_at TEXT,
              deleted_at TEXT,
              due_date TEXT,
              task_mode TEXT NOT NULL DEFAULT 'normal',
              sort_order INTEGER NOT NULL DEFAULT 0,
              week_sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE TABLE subtasks(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE memos(id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, created_at TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
        },
      ),
    );
    final stamp = DateTime(2026, 9, 15).toIso8601String();
    await legacy.insert('tasks', {
      'title': '阶段完成',
      'created_at': stamp,
      'completed_at': stamp,
      'task_mode': Task.planNextMode,
    });
    await legacy.insert('tasks', {
      'title': '本周删除',
      'created_at': stamp,
      'deleted_at': stamp,
      'due_date': stamp,
    });
    await legacy.insert('tasks', {
      'title': '收件箱完成',
      'created_at': stamp,
      'completed_at': stamp,
    });
    await legacy.close();

    final migrated = await DatabaseProvider().openAtPath(path);
    addTearDown(migrated.close);
    expect(await migrated.getVersion(), 23);
    expect(await File(backupPath).exists(), isTrue);
    final rows = await migrated.query('tasks', orderBy: 'id ASC');
    expect(rows[0]['completed_scope'], Task.actionScopeStage);
    expect(rows[1]['deleted_scope'], Task.actionScopeWeek);
    expect(rows[2]['completed_scope'], Task.actionScopeInbox);
  });

  test(
    'version 22 migration backs up and releases companion stashed tasks',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final path = p.join(
        Directory.systemTemp.path,
        'todo_list_v22_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final backupPath = '$path.pre-v23';
      addTearDown(() async {
        for (final candidate in [path, backupPath]) {
          final file = File(candidate);
          if (await file.exists()) await file.delete();
        }
      });
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 22,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE tasks(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              created_at TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              task_mode TEXT NOT NULL DEFAULT 'normal',
              due_date TEXT,
              companion_stashed_at TEXT
            )
          ''');
            await db.execute(
              'CREATE TABLE subtasks(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, parent_id INTEGER, sort_order INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE memos(id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, created_at TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
            );
          },
        ),
      );
      final stamp = DateTime(2026, 9, 16).toIso8601String();
      await legacy.insert('tasks', {
        'title': '回到收件箱',
        'created_at': stamp,
        'companion_stashed_at': stamp,
      });
      await legacy.insert('tasks', {
        'title': '保留阶段',
        'created_at': stamp,
        'task_mode': Task.planNextMode,
        'companion_stashed_at': stamp,
      });
      await legacy.insert('tasks', {
        'title': '保留日期',
        'created_at': stamp,
        'due_date': stamp,
        'companion_stashed_at': stamp,
      });
      await legacy.close();

      final migrated = await DatabaseProvider().openAtPath(path);
      addTearDown(migrated.close);
      expect(await migrated.getVersion(), 23);
      expect(await File(backupPath).exists(), isTrue);
      final rows = await migrated.query('tasks', orderBy: 'id ASC');
      expect(rows.every((row) => row['companion_stashed_at'] == null), isTrue);
      expect(rows[0]['task_mode'], Task.normalMode);
      expect(rows[0]['due_date'], isNull);
      expect(rows[1]['task_mode'], Task.planNextMode);
      expect(rows[2]['due_date'], stamp);
    },
  );

  test('version 17 data migrates without changing categories or records', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'todo_list_migration_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 17,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            "CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '默认', created_at TEXT NOT NULL, completed_at TEXT, deleted_at TEXT, due_date TEXT, reminder_time TEXT, repeat_type TEXT, sort_order INTEGER NOT NULL DEFAULT 0)",
          );
          await db.execute(
            'CREATE TABLE subtasks(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, parent_id INTEGER, level INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0, due_date TEXT, reminder_time TEXT, repeat_type TEXT, deleted_at TEXT)',
          );
          await db.execute(
            "CREATE TABLE memos(id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER, level INTEGER NOT NULL DEFAULT 0, content TEXT NOT NULL, category TEXT NOT NULL DEFAULT '紧急+重要+必须', sort_order INTEGER NOT NULL DEFAULT 0, due_date TEXT, reminder_time TEXT, repeat_type TEXT, deleted_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
          );
          await db.execute(
            'CREATE TABLE memo_categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    await legacy.insert('categories', {
      'name': '工作',
      'color': '#2196F3',
      'sort_order': 0,
    });
    await legacy.insert('memo_categories', {
      'name': '紧急+重要+必须',
      'color': '#F44336',
      'sort_order': 0,
    });
    await legacy.insert('tasks', {
      'title': '保留的旧任务',
      'note': '',
      'category': '工作',
      'created_at': now,
      'sort_order': 0,
    });
    await legacy.insert('memos', {
      'content': '保留的旧备忘录',
      'category': '紧急+重要+必须',
      'created_at': now,
      'updated_at': now,
      'sort_order': 0,
    });
    await legacy.close();

    final migrated = await DatabaseProvider().openAtPath(path);
    addTearDown(migrated.close);
    expect(await migrated.getVersion(), 23);
    expect((await migrated.query('tasks')).single['title'], '保留的旧任务');
    expect((await migrated.query('memos')).single['content'], '保留的旧备忘录');
    expect((await migrated.query('categories')).single['name'], '工作');
    expect(
      (await migrated.query('memo_categories')).single['name'],
      '紧急+重要+必须',
    );
    expect((await migrated.query('sync_outbox')).length, 4);
  });

  test(
    'JSON import merges records, remaps relations and keeps local data',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final tempDir = await Directory.systemTemp.createTemp('todo_json_merge_');
      addTearDown(() => tempDir.delete(recursive: true));
      final db = await DatabaseProvider().openAtPath(
        p.join(tempDir.path, 'target.db'),
      );
      addTearDown(db.close);

      final repository = TaskRepository(db);
      await repository.insert(Task(title: '本地保留任务'));
      final now = DateTime.now();
      final remoteTask = Task(
        id: 101,
        title: '电脑导入任务',
        syncId: '11111111-1111-4111-8111-111111111111',
        updatedAt: now,
      ).toMap();
      final remoteMemo = Memo(
        id: 201,
        content: '电脑导入备忘录',
        syncId: '22222222-2222-4222-8222-222222222222',
        updatedAt: now,
      ).toMap();
      final backup = jsonEncode({
        'format_version': 2,
        'exported_at': now.toIso8601String(),
        'tasks': [remoteTask],
        'subtasks': [
          {
            'id': 301,
            'task_id': 101,
            'parent_id': null,
            'level': 0,
            'title': '导入子任务',
            'is_done': 0,
            'sort_order': 0,
            'sync_id': '33333333-3333-4333-8333-333333333333',
            'updated_at': now.toIso8601String(),
            'revision': 1,
          },
        ],
        'categories': [],
        'memos': [remoteMemo],
        'memo_categories': [],
        'task_memo_links': [
          {
            'id': 401,
            'task_id': 101,
            'memo_id': 201,
            'sync_id': '44444444-4444-4444-8444-444444444444',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'revision': 1,
          },
        ],
        'settings': [
          {'key': 'daily_effort_limit', 'value': '9'},
        ],
      });

      final result = await DatabaseProvider().importAllJsonMerge(
        backup,
        targetDatabase: db,
        safetyDirectory: tempDir.path,
      );
      expect(File(result.safetyBackupPath).existsSync(), isTrue);
      expect((await db.query('tasks')).length, 2);
      final importedTask = (await db.query(
        'tasks',
        where: 'sync_id = ?',
        whereArgs: ['11111111-1111-4111-8111-111111111111'],
      )).single;
      final importedMemo = (await db.query(
        'memos',
        where: 'sync_id = ?',
        whereArgs: ['22222222-2222-4222-8222-222222222222'],
      )).single;
      final importedSubtask = (await db.query('subtasks')).single;
      final importedLink = (await db.query('task_memo_links')).single;
      expect(importedSubtask['task_id'], importedTask['id']);
      expect(importedLink['task_id'], importedTask['id']);
      expect(importedLink['memo_id'], importedMemo['id']);
      expect(
        (await db.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['daily_effort_limit'],
        )).single['value'],
        '9',
      );
    },
  );

  test(
    'legacy desktop JSON imports once without losing Android data',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final tempDir = await Directory.systemTemp.createTemp(
        'todo_legacy_json_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final db = await DatabaseProvider().openAtPath(
        p.join(tempDir.path, 'target.db'),
      );
      addTearDown(db.close);
      await TaskRepository(db).insert(Task(title: '手机原任务'));

      const exportedAt = '2026-07-31T23:41:33.883173';
      final backup = jsonEncode({
        'exported_at': exportedAt,
        'tasks': [
          {
            'id': 7,
            'title': 'Windows Release 任务',
            'note': '',
            'category': '默认',
            'created_at': exportedAt,
            'completed_at': null,
            'deleted_at': null,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'sort_order': 0,
          },
        ],
        'subtasks': [
          {
            'id': 9,
            'task_id': 7,
            'parent_id': null,
            'level': 0,
            'title': '旧版子任务',
            'is_done': 0,
            'sort_order': 0,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'deleted_at': null,
          },
        ],
        'categories': [],
        'memos': [
          {
            'id': 11,
            'parent_id': null,
            'level': 0,
            'content': 'Windows Release 备忘录',
            'category': '紧急+重要+必须',
            'sort_order': 0,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'deleted_at': null,
            'created_at': exportedAt,
            'updated_at': exportedAt,
          },
        ],
        'memo_categories': [],
      });

      await DatabaseProvider().importAllJsonMerge(
        backup,
        targetDatabase: db,
        safetyDirectory: tempDir.path,
      );
      await DatabaseProvider().importAllJsonMerge(
        backup,
        targetDatabase: db,
        safetyDirectory: tempDir.path,
      );

      expect((await db.query('tasks')).length, 2);
      expect((await db.query('memos')).length, 1);
      expect((await db.query('subtasks')).length, 1);
      expect(
        (await db.query('tasks')).map((row) => row['title']),
        containsAll(['手机原任务', 'Windows Release 任务']),
      );
    },
  );

  test('configured desktop JSON imports into an isolated copy', () async {
    final sourcePath = Platform.environment['TODO_JSON_SOURCE'];
    if (sourcePath == null || !File(sourcePath).existsSync()) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final jsonText = await File(sourcePath).readAsString();
    final preview = DatabaseProvider().previewBackup(jsonText);
    final tempDir = await Directory.systemTemp.createTemp('todo_real_json_');
    addTearDown(() => tempDir.delete(recursive: true));
    final db = await DatabaseProvider().openAtPath(
      p.join(tempDir.path, 'target.db'),
    );
    addTearDown(db.close);
    await TaskRepository(db).insert(Task(title: '手机本地保留校验'));

    await DatabaseProvider().importAllJsonMerge(
      jsonText,
      targetDatabase: db,
      safetyDirectory: tempDir.path,
    );
    final firstTaskCount = (await db.query('tasks')).length;
    final firstMemoCount = (await db.query('memos')).length;
    await DatabaseProvider().importAllJsonMerge(
      jsonText,
      targetDatabase: db,
      safetyDirectory: tempDir.path,
    );

    expect((await db.query('tasks')).length, firstTaskCount);
    expect((await db.query('memos')).length, firstMemoCount);
    expect(firstTaskCount, greaterThanOrEqualTo(preview.counts['tasks']! + 1));
    expect(firstMemoCount, greaterThanOrEqualTo(preview.counts['memos']!));
    expect(
      (await db.query('tasks')).map((row) => row['title']),
      contains('手机本地保留校验'),
    );
  });

  test(
    'opening lists no longer permanently removes old deleted tasks',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      addTearDown(db.close);
      final repository = TaskRepository(db);
      final oldDeleted = Task(
        title: '仍可恢复的旧任务',
        deletedAt: DateTime.now().subtract(const Duration(days: 60)),
      );
      await repository.insert(oldDeleted);
      expect((await repository.getDeleted()).single.title, '仍可恢复的旧任务');
      expect((await db.query('tasks')).length, 1);
    },
  );

  test(
    'configured desktop database copy migrates without record loss',
    () async {
      final sourcePath = Platform.environment['TODO_MIGRATION_SOURCE'];
      if (sourcePath == null || !File(sourcePath).existsSync()) return;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final tempDir = await Directory.systemTemp.createTemp(
        'todo_real_migration_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final copyPath = p.join(tempDir.path, 'todo_list.db');
      await File(sourcePath).copy(copyPath);
      final beforeDb = await databaseFactory.openDatabase(copyPath);
      const tables = [
        'tasks',
        'subtasks',
        'memos',
        'categories',
        'memo_categories',
        'task_memo_links',
      ];
      final before = <String, int>{};
      for (final table in tables) {
        before[table] =
            (await beforeDb.rawQuery(
                  'SELECT COUNT(*) AS count FROM $table',
                )).single['count']
                as int;
      }
      await beforeDb.close();

      final migrated = await DatabaseProvider().openAtPath(copyPath);
      addTearDown(migrated.close);
      expect(await migrated.getVersion(), 23);
      for (final table in tables) {
        expect(
          (await migrated.rawQuery(
            'SELECT COUNT(*) AS count FROM $table',
          )).single['count'],
          before[table],
          reason: '$table 迁移前后数量应一致',
        );
      }
      final columns = await migrated.rawQuery("PRAGMA table_info('tasks')");
      expect(
        columns.map((row) => row['name']),
        contains('companion_stashed_at'),
      );
    },
  );
}
