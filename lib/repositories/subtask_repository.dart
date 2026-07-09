import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/sub_task.dart';

/// subtasks 表数据访问——纯 SQL，无业务逻辑
class SubTaskRepository {
  final Database _db;

  SubTaskRepository(this._db);

  Future<int> insert(SubTask st) async {
    return await _db.insert('subtasks', st.toMap()..remove('id'));
  }

  Future<int> update(SubTask st) async {
    return await _db.update('subtasks', st.toMap(), where: 'id = ?', whereArgs: [st.id]);
  }

  /// 递归删除子树
  Future<void> delete(int id) async {
    await softDelete(id);
  }

  /// 软删除：标记 deleted_at + 移到底部（递归）
  Future<void> softDelete(int id) async {
    final self = await _db.query('subtasks', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return;
    final st = self.first;
    final parentId = st['parent_id'];
    final taskIdVal = st['task_id'];
    await _softDeleteSubTree(id);
    // 移到同层末尾
    final whereClause = parentId != null ? 'parent_id = ?' : 'task_id = ? AND parent_id IS NULL';
    final whereArg = parentId ?? taskIdVal;
    final maxOrder = await _db.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) as m FROM subtasks WHERE $whereClause', [whereArg]);
    final lastOrder = ((maxOrder.first['m'] as int?) ?? -1) + 1;
    await _db.update('subtasks', {'sort_order': lastOrder}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _softDeleteSubTree(int id) async {
    final children = await _db.query('subtasks',
        where: 'parent_id = ? AND deleted_at IS NULL', whereArgs: [id]);
    for (final child in children) {
      await _softDeleteSubTree(child['id'] as int);
    }
    await _db.update('subtasks', {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restore(int id) async {
    await _db.update('subtasks', {'deleted_at': null}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> permanentlyDelete(int id) async {
    await _deleteSubTree(id);
  }

  Future<void> _deleteSubTree(int id) async {
    final children = await _db.query('subtasks', where: 'parent_id = ?', whereArgs: [id]);
    for (final child in children) {
      await _deleteSubTree(child['id'] as int);
    }
    await _db.delete('subtasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SubTask>> getRoots(int taskId) async {
    final maps = await _db.query('subtasks',
        where: 'task_id = ? AND parent_id IS NULL',
        whereArgs: [taskId],
        orderBy: 'sort_order ASC, id ASC');
    return maps.map((m) => SubTask.fromMap(m)).toList();
  }

  Future<List<SubTask>> getChildren(int parentId) async {
    final maps = await _db.query('subtasks',
        where: 'parent_id = ?', whereArgs: [parentId],
        orderBy: 'sort_order ASC, id ASC');
    return maps.map((m) => SubTask.fromMap(m)).toList();
  }

  Future<List<int?>> promote(int id) async {
    final self = await _db.query('subtasks', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return [];
    final st = self.first;
    final int? oldParent = st['parent_id'] as int?;
    if (oldParent == null) return [];
    final parent = await _db.query('subtasks', where: 'id = ?', whereArgs: [oldParent]);
    if (parent.isEmpty) return [];
    final int? newParent = parent.first['parent_id'] as int?;
    final newLevel = parent.first['level'] as int;
    final parentSort = parent.first['sort_order'] as int;
    await _db.update('subtasks', {
      'parent_id': newParent, 'level': newLevel, 'sort_order': parentSort + 1,
    }, where: 'id = ?', whereArgs: [id]);
    return [oldParent, newParent];
  }

  Future<List<int?>> demote(int id) async {
    final self = await _db.query('subtasks', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return [];
    final st = self.first;
    final currentLevel = st['level'] as int;
    if (currentLevel >= 4) return [];
    final int? oldParent = st['parent_id'] as int?;
    final siblings = await _db.query('subtasks',
        where: oldParent == null ? 'task_id = ? AND parent_id IS NULL' : 'parent_id = ?',
        whereArgs: oldParent == null ? [st['task_id']] : [oldParent],
        orderBy: 'sort_order ASC');
    int selfIdx = siblings.indexWhere((s) => s['id'] == id);
    if (selfIdx <= 0) return [];
    final prevSibling = siblings[selfIdx - 1];
    final int newParent = prevSibling['id'] as int;
    final children = await _db.query('subtasks', where: 'parent_id = ?', whereArgs: [newParent]);
    final maxSort = children.fold<int>(0, (m, c) => (c['sort_order'] as int) > m ? c['sort_order'] as int : m);
    await _db.update('subtasks', {
      'parent_id': newParent, 'level': currentLevel + 1, 'sort_order': maxSort + 1,
    }, where: 'id = ?', whereArgs: [id]);
    return [oldParent, newParent];
  }

  Future<void> moveUp(int id) async {
    final self = await _db.query('subtasks', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return;
    final st = self.first;
    final myOrder = st['sort_order'] as int;
    final parentId = st['parent_id'];
    final taskId = st['task_id'];
    final whereClause = parentId != null ? 'parent_id = ?' : 'task_id = ? AND parent_id IS NULL';
    final whereArg = parentId ?? taskId;
    final above = await _db.query('subtasks',
        where: '$whereClause AND sort_order < ?',
        whereArgs: [whereArg, myOrder], orderBy: 'sort_order DESC', limit: 1);
    if (above.isEmpty) return;
    final aboveOrder = above.first['sort_order'] as int;
    final aboveId = above.first['id'] as int;
    await _db.update('subtasks', {'sort_order': aboveOrder}, where: 'id = ?', whereArgs: [id]);
    await _db.update('subtasks', {'sort_order': myOrder}, where: 'id = ?', whereArgs: [aboveId]);
  }

  Future<void> moveDown(int id) async {
    final self = await _db.query('subtasks', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return;
    final st = self.first;
    final myOrder = st['sort_order'] as int;
    final parentId = st['parent_id'];
    final taskId = st['task_id'];
    final whereClause = parentId != null ? 'parent_id = ?' : 'task_id = ? AND parent_id IS NULL';
    final whereArg = parentId ?? taskId;
    final below = await _db.query('subtasks',
        where: '$whereClause AND sort_order > ?',
        whereArgs: [whereArg, myOrder], orderBy: 'sort_order ASC', limit: 1);
    if (below.isEmpty) return;
    final belowOrder = below.first['sort_order'] as int;
    final belowId = below.first['id'] as int;
    await _db.update('subtasks', {'sort_order': belowOrder}, where: 'id = ?', whereArgs: [id]);
    await _db.update('subtasks', {'sort_order': myOrder}, where: 'id = ?', whereArgs: [belowId]);
  }

  Future<({int total, int done})> getProgress(int taskId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as total, COALESCE(SUM(is_done), 0) as done FROM subtasks WHERE task_id = ?',
      [taskId],
    );
    final row = result.first;
    return (total: (row['total'] as int?) ?? 0, done: (row['done'] as int?) ?? 0);
  }
}
