import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/memo.dart';
import '../models/task.dart';
import '../utils/sync_id.dart';

class TaskMemoRepository {
  TaskMemoRepository(this._db);

  final Database _db;

  Future<void> link(int taskId, int memoId) async {
    final now = DateTime.now().toIso8601String();
    await _db.insert('task_memo_links', {
      'task_id': taskId,
      'memo_id': memoId,
      'sync_id': SyncId.generate(),
      'created_at': now,
      'updated_at': now,
      'revision': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> unlink(int taskId, int memoId) async {
    await _db.delete(
      'task_memo_links',
      where: 'task_id = ? AND memo_id = ?',
      whereArgs: [taskId, memoId],
    );
  }

  Future<List<Memo>> getMemosForTask(int taskId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT m.*
      FROM memos m
      INNER JOIN task_memo_links l ON l.memo_id = m.id
      WHERE l.task_id = ? AND m.deleted_at IS NULL
      ORDER BY m.pinned_at IS NULL, m.updated_at DESC
    ''',
      [taskId],
    );
    return rows.map(Memo.fromMap).toList();
  }

  Future<List<Task>> getTasksForMemo(int memoId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT t.*
      FROM tasks t
      INNER JOIN task_memo_links l ON l.task_id = t.id
      WHERE l.memo_id = ? AND t.deleted_at IS NULL
      ORDER BY t.completed_at IS NOT NULL, t.sort_order ASC
    ''',
      [memoId],
    );
    return rows.map(Task.fromMap).toList();
  }
}
