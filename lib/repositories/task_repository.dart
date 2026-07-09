import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/task.dart';

/// tasks 表数据访问——纯 SQL，无业务逻辑
class TaskRepository {
  final Database _db;

  TaskRepository(this._db);

  Future<int> insert(Task task) async {
    final maxOrder = await _db.rawQuery('SELECT COALESCE(MAX(sort_order), -1) as m FROM tasks');
    final nextOrder = ((maxOrder.first['m'] as int?) ?? -1) + 1;
    final map = task.toMap()..remove('id');
    map['sort_order'] = nextOrder;
    return await _db.insert('tasks', map);
  }

  Future<int> update(Task task) async {
    return await _db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> softDelete(int taskId) async {
    await _db.update('tasks', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [taskId]);
  }

  Future<void> restore(int taskId) async {
    await _db.update('tasks', {'deleted_at': null}, where: 'id = ?', whereArgs: [taskId]);
  }

  Future<void> permanentlyDelete(int taskId) async {
    await _db.delete('subtasks', where: 'task_id = ?', whereArgs: [taskId]);
    await _db.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
  }

  Future<void> moveUp(int taskId) async {
    final self = await _db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
    if (self.isEmpty) return;
    final myOrder = self.first['sort_order'] as int;
    final above = await _db.query('tasks',
        where: 'deleted_at IS NULL AND sort_order < ?',
        whereArgs: [myOrder], orderBy: 'sort_order DESC', limit: 1);
    if (above.isEmpty) return;
    final aboveOrder = above.first['sort_order'] as int;
    final aboveId = above.first['id'] as int;
    await _db.update('tasks', {'sort_order': aboveOrder}, where: 'id = ?', whereArgs: [taskId]);
    await _db.update('tasks', {'sort_order': myOrder}, where: 'id = ?', whereArgs: [aboveId]);
  }

  Future<void> moveDown(int taskId) async {
    final self = await _db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
    if (self.isEmpty) return;
    final myOrder = self.first['sort_order'] as int;
    final below = await _db.query('tasks',
        where: 'deleted_at IS NULL AND sort_order > ?',
        whereArgs: [myOrder], orderBy: 'sort_order ASC', limit: 1);
    if (below.isEmpty) return;
    final belowOrder = below.first['sort_order'] as int;
    final belowId = below.first['id'] as int;
    await _db.update('tasks', {'sort_order': belowOrder}, where: 'id = ?', whereArgs: [taskId]);
    await _db.update('tasks', {'sort_order': myOrder}, where: 'id = ?', whereArgs: [belowId]);
  }

  Future<void> cleanupOldDeleted() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 15)).toIso8601String();
    final old = await _db.query('tasks',
        where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [cutoff]);
    for (final t in old) {
      await _db.delete('subtasks', where: 'task_id = ?', whereArgs: [t['id']]);
    }
    await _db.delete('tasks', where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [cutoff]);
  }

  Future<List<Task>> getActive() async {
    await cleanupOldDeleted();
    final maps = await _db.query('tasks',
        where: 'deleted_at IS NULL', orderBy: 'sort_order ASC, created_at DESC');
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<List<Task>> getDeleted() async {
    await cleanupOldDeleted();
    final maps = await _db.query('tasks',
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<void> setCompletedAt(int taskId, DateTime? time) async {
    await _db.update('tasks',
        {'completed_at': time?.toIso8601String()},
        where: 'id = ?', whereArgs: [taskId]);
  }
}
