import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_list/database/database.dart';
import 'package:todo_list/models/task.dart';
import 'package:todo_list/repositories/task_repository.dart';
import 'package:todo_list/sync/sync_engine.dart';
import 'package:todo_list/sync/sync_gateway.dart';

class _FakeSyncGateway implements SyncGateway {
  _FakeSyncGateway([this.remoteChanges = const []]);

  final List<CloudChange> remoteChanges;
  final List<List<CloudChange>> pushedBatches = [];
  final List<DateTime?> pullCursors = [];

  @override
  Future<List<CloudChange>> pull({DateTime? changedAfter}) async {
    pullCursors.add(changedAfter);
    return List<CloudChange>.from(remoteChanges);
  }

  @override
  Future<void> push(List<CloudChange> changes) async {
    pushedBatches.add(List<CloudChange>.from(changes));
  }

  @override
  Stream<void> watchRemoteChanges() => const Stream<void>.empty();
}

CloudChange _change({
  required String type,
  required String id,
  required Map<String, dynamic> payload,
  required DateTime updatedAt,
}) {
  return CloudChange(
    entityType: type,
    entityId: id,
    operation: 'upsert',
    payload: payload,
    revision: 1,
    updatedAt: updatedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'full cloud pull restores memo and subtask parent relationships',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.delete('sync_outbox');

      final base = DateTime.utc(2026, 8, 16, 8);
      const taskSyncId = '11111111-1111-4111-8111-111111111111';
      const parentMemoSyncId = '22222222-2222-4222-8222-222222222222';
      const childMemoSyncId = '33333333-3333-4333-8333-333333333333';
      const parentSubtaskSyncId = '44444444-4444-4444-8444-444444444444';
      const childSubtaskSyncId = '55555555-5555-4555-8555-555555555555';

      final gateway = _FakeSyncGateway([
        _change(
          type: 'memo',
          id: childMemoSyncId,
          updatedAt: base,
          payload: {
            'parent_sync_id': parentMemoSyncId,
            'level': 1,
            'content': '子备忘录',
            'category': '紧急+重要+必须',
            'sort_order': 0,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'deleted_at': null,
            'created_at': base.toIso8601String(),
            'updated_at': base.toIso8601String(),
            'pinned_at': null,
            'archived_at': null,
            'sync_id': childMemoSyncId,
            'revision': 1,
          },
        ),
        _change(
          type: 'memo',
          id: parentMemoSyncId,
          updatedAt: base.add(const Duration(seconds: 1)),
          payload: {
            'parent_sync_id': null,
            'level': 0,
            'content': '父备忘录',
            'category': '紧急+重要+必须',
            'sort_order': 0,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'deleted_at': null,
            'created_at': base.toIso8601String(),
            'updated_at': base.toIso8601String(),
            'pinned_at': null,
            'archived_at': null,
            'sync_id': parentMemoSyncId,
            'revision': 1,
          },
        ),
        _change(
          type: 'task',
          id: taskSyncId,
          updatedAt: base,
          payload: {
            ...Task(
              title: '跨端任务',
              taskMode: Task.flowMode,
              syncId: taskSyncId,
              createdAt: base,
              updatedAt: base,
            ).toMap()..remove('id'),
          },
        ),
        _change(
          type: 'subtask',
          id: childSubtaskSyncId,
          updatedAt: base,
          payload: {
            'task_sync_id': taskSyncId,
            'parent_sync_id': parentSubtaskSyncId,
            'level': 1,
            'title': '子任务',
            'is_done': 0,
            'sort_order': 0,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'deleted_at': null,
            'sync_id': childSubtaskSyncId,
            'updated_at': base.toIso8601String(),
            'revision': 1,
          },
        ),
        _change(
          type: 'subtask',
          id: parentSubtaskSyncId,
          updatedAt: base.add(const Duration(seconds: 1)),
          payload: {
            'task_sync_id': taskSyncId,
            'parent_sync_id': null,
            'level': 0,
            'title': '父任务',
            'is_done': 0,
            'sort_order': 0,
            'due_date': null,
            'reminder_time': null,
            'repeat_type': null,
            'deleted_at': null,
            'sync_id': parentSubtaskSyncId,
            'updated_at': base.toIso8601String(),
            'revision': 1,
          },
        ),
      ]);

      final pulled = await SyncEngine(db, gateway).syncNow();

      final parentMemo = (await db.query(
        'memos',
        where: 'sync_id = ?',
        whereArgs: [parentMemoSyncId],
      )).single;
      final childMemo = (await db.query(
        'memos',
        where: 'sync_id = ?',
        whereArgs: [childMemoSyncId],
      )).single;
      final parentSubtask = (await db.query(
        'subtasks',
        where: 'sync_id = ?',
        whereArgs: [parentSubtaskSyncId],
      )).single;
      final childSubtask = (await db.query(
        'subtasks',
        where: 'sync_id = ?',
        whereArgs: [childSubtaskSyncId],
      )).single;
      final pulledTask = (await db.query(
        'tasks',
        where: 'sync_id = ?',
        whereArgs: [taskSyncId],
      )).single;

      expect(pulled, 5);
      expect(gateway.pullCursors, [isNull]);
      expect(childMemo['parent_id'], parentMemo['id']);
      expect(childSubtask['parent_id'], parentSubtask['id']);
      expect(childSubtask['task_id'], parentSubtask['task_id']);
      expect(pulledTask['task_mode'], Task.flowMode);
      expect(await db.query('sync_outbox'), isEmpty);
    },
  );

  test('one sync drains every pending batch', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.delete('sync_outbox');
    final repository = TaskRepository(db);
    for (var i = 0; i < 205; i++) {
      await repository.insert(Task(title: '任务 $i'));
    }
    final gateway = _FakeSyncGateway();

    await SyncEngine(db, gateway).syncNow();

    expect(gateway.pushedBatches.map((batch) => batch.length), [100, 100, 5]);
    expect(await db.query('sync_outbox'), isEmpty);
  });

  test(
    'legacy cloud tasks infer missing completion and deletion scopes',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await DatabaseProvider().openAtPath(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.delete('sync_outbox');

      final base = DateTime.utc(2026, 9, 15, 8);
      final stagePayload =
          Task(
              title: '旧云阶段已完成',
              taskMode: Task.planNextMode,
              completedAt: base,
              syncId: '66666666-6666-4666-8666-666666666666',
              createdAt: base,
              updatedAt: base,
            ).toMap()
            ..remove('id')
            ..remove('completed_scope')
            ..remove('deleted_scope');
      final weekPayload =
          Task(
              title: '旧云本周已删除',
              dueDate: DateTime.utc(2026, 9, 16),
              deletedAt: base,
              syncId: '77777777-7777-4777-8777-777777777777',
              createdAt: base,
              updatedAt: base,
            ).toMap()
            ..remove('id')
            ..remove('completed_scope')
            ..remove('deleted_scope');
      final gateway = _FakeSyncGateway([
        _change(
          type: 'task',
          id: stagePayload['sync_id']! as String,
          payload: stagePayload,
          updatedAt: base,
        ),
        _change(
          type: 'task',
          id: weekPayload['sync_id']! as String,
          payload: weekPayload,
          updatedAt: base,
        ),
      ]);

      await SyncEngine(db, gateway).syncNow();

    final tasks = (await db.query('tasks')).map(Task.fromMap).toList();
      final stage = tasks.singleWhere((task) => task.title == '旧云阶段已完成');
      final week = tasks.singleWhere((task) => task.title == '旧云本周已删除');
      expect(stage.completedScope, Task.actionScopeStage);
      expect(week.deletedScope, Task.actionScopeWeek);
      expect(await db.query('sync_outbox'), isEmpty);
    },
  );
}
