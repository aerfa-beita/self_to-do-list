import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/memo.dart';

/// memos 表数据访问——纯 SQL，无业务逻辑
class MemoRepository {
  final Database _db;

  MemoRepository(this._db);

  Future<int> insert(Memo memo) async {
    final maxOrder = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) as m FROM memos WHERE parent_id IS NULL',
    );
    final nextOrder = ((maxOrder.first['m'] as int?) ?? -1) + 1;
    final map = memo.toMap()..remove('id');
    map['sort_order'] = nextOrder;
    return await _db.insert('memos', map);
  }

  Future<int> insertChild(Memo memo, int parentId) async {
    final maxOrder = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) as m FROM memos WHERE parent_id = ?',
      [parentId],
    );
    final nextOrder = ((maxOrder.first['m'] as int?) ?? -1) + 1;
    final map = memo.toMap()..remove('id');
    map['parent_id'] = parentId;
    map['sort_order'] = nextOrder;
    return await _db.insert('memos', map);
  }

  Future<int> update(Memo memo) async {
    return await _db.update(
      'memos',
      memo.toMap(),
      where: 'id = ?',
      whereArgs: [memo.id],
    );
  }

  Future<void> _softDeleteSubTree(int id) async {
    final children = await _db.query(
      'memos',
      where: 'parent_id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    for (final child in children) {
      await _softDeleteSubTree(child['id'] as int);
    }
    await _db.update(
      'memos',
      {'deleted_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDelete(int id) async {
    // 查父节点信息，用于移到底部
    final self = await _db.query('memos', where: 'id = ?', whereArgs: [id]);
    final parentId = self.isNotEmpty ? self.first['parent_id'] : null;
    await _softDeleteSubTree(id);
    // 移到同层末尾
    if (self.isNotEmpty) {
      final whereClause = parentId != null
          ? 'parent_id = ? AND deleted_at IS NULL'
          : 'parent_id IS NULL AND deleted_at IS NULL';
      final whereArg = parentId;
      final maxOrder = await _db.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) as m FROM memos WHERE $whereClause',
        whereArg != null ? [whereArg] : null,
      );
      final lastOrder = ((maxOrder.first['m'] as int?) ?? -1) + 1;
      await _db.update(
        'memos',
        {'sort_order': lastOrder},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> restore(int id) async {
    await _db.update(
      'memos',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> permanentlyDelete(int id) async {
    final children = await _db.query(
      'memos',
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    for (final child in children) {
      await permanentlyDelete(child['id'] as int);
    }
    await _db.delete('memos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cleanupOldDeleted() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 15))
        .toIso8601String();
    final old = await _db.query(
      'memos',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
    for (final m in old) {
      await permanentlyDelete(m['id'] as int);
    }
  }

  Future<List<Memo>> getRoots() async {
    final maps = await _db.query(
      'memos',
      where: 'parent_id IS NULL AND deleted_at IS NULL AND archived_at IS NULL',
      orderBy: 'pinned_at IS NULL, pinned_at DESC, sort_order ASC, id ASC',
    );
    return maps.map((m) => Memo.fromMap(m)).toList();
  }

  Future<List<Memo>> getArchived() async {
    final maps = await _db.query(
      'memos',
      where:
          'parent_id IS NULL AND deleted_at IS NULL AND archived_at IS NOT NULL',
      orderBy: 'archived_at DESC, id DESC',
    );
    return maps.map(Memo.fromMap).toList();
  }

  Future<void> setPinned(int id, bool pinned) async {
    await _db.update(
      'memos',
      {
        'pinned_at': pinned ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setArchived(int id, bool archived) async {
    await _db.update(
      'memos',
      {
        'archived_at': archived ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Memo>> getDeleted() async {
    final maps = await _db.query(
      'memos',
      where: 'parent_id IS NULL AND deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return maps.map((m) => Memo.fromMap(m)).toList();
  }

  Future<Memo?> getById(int id) async {
    final maps = await _db.query(
      'memos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : Memo.fromMap(maps.first);
  }

  Future<List<Memo>> getChildren(int parentId) async {
    final maps = await _db.query(
      'memos',
      where: 'parent_id = ? AND archived_at IS NULL',
      whereArgs: [parentId],
      orderBy: 'deleted_at IS NOT NULL, sort_order ASC, id ASC',
    );
    return maps.map((m) => Memo.fromMap(m)).toList();
  }

  Future<List<int?>> promote(int id) async {
    final self = await _db.query('memos', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return [];
    final st = self.first;
    final int? oldParent = st['parent_id'] as int?;
    if (oldParent == null) return [];
    final parent = await _db.query(
      'memos',
      where: 'id = ?',
      whereArgs: [oldParent],
    );
    if (parent.isEmpty) return [];
    final int? newParent = parent.first['parent_id'] as int?;
    final newLevel = parent.first['level'] as int;
    final parentSort = parent.first['sort_order'] as int;
    await _db.update(
      'memos',
      {'parent_id': newParent, 'level': newLevel, 'sort_order': parentSort + 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    return [oldParent, newParent];
  }

  Future<List<int?>> demote(int id) async {
    final self = await _db.query('memos', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return [];
    final st = self.first;
    final currentLevel = st['level'] as int;
    if (currentLevel >= 4) return [];
    final int? oldParent = st['parent_id'] as int?;
    final siblings = await _db.query(
      'memos',
      where: oldParent == null
          ? 'parent_id IS NULL AND deleted_at IS NULL'
          : 'parent_id = ? AND deleted_at IS NULL',
      whereArgs: oldParent == null ? null : [oldParent],
      orderBy: 'sort_order ASC',
    );
    int selfIdx = siblings.indexWhere((s) => s['id'] == id);
    if (selfIdx <= 0) return [];
    final prevSibling = siblings[selfIdx - 1];
    final int newParent = prevSibling['id'] as int;
    final children = await _db.query(
      'memos',
      where: 'parent_id = ?',
      whereArgs: [newParent],
    );
    final maxSort = children.fold<int>(
      0,
      (m, c) => (c['sort_order'] as int) > m ? c['sort_order'] as int : m,
    );
    await _db.update(
      'memos',
      {
        'parent_id': newParent,
        'level': currentLevel + 1,
        'sort_order': maxSort + 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return [oldParent, newParent];
  }

  Future<void> updateSortOrder(int id, int order) async {
    await _db.update(
      'memos',
      {'sort_order': order},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> moveUp(int id) async {
    final self = await _db.query('memos', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return;
    final st = self.first;
    final myOrder = st['sort_order'] as int;
    final parentId = st['parent_id'];
    final whereClause = parentId != null
        ? 'parent_id = ? AND deleted_at IS NULL'
        : 'parent_id IS NULL AND deleted_at IS NULL';
    final whereArg = parentId;
    final above = await _db.query(
      'memos',
      where: '$whereClause AND sort_order < ?',
      whereArgs: whereArg != null ? [whereArg, myOrder] : [myOrder],
      orderBy: 'sort_order DESC',
      limit: 1,
    );
    if (above.isEmpty) return;
    final aboveOrder = above.first['sort_order'] as int;
    final aboveId = above.first['id'] as int;
    await _db.update(
      'memos',
      {'sort_order': aboveOrder},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.update(
      'memos',
      {'sort_order': myOrder},
      where: 'id = ?',
      whereArgs: [aboveId],
    );
  }

  Future<void> moveDown(int id) async {
    final self = await _db.query('memos', where: 'id = ?', whereArgs: [id]);
    if (self.isEmpty) return;
    final st = self.first;
    final myOrder = st['sort_order'] as int;
    final parentId = st['parent_id'];
    final whereClause = parentId != null
        ? 'parent_id = ? AND deleted_at IS NULL'
        : 'parent_id IS NULL AND deleted_at IS NULL';
    final whereArg = parentId;
    final below = await _db.query(
      'memos',
      where: '$whereClause AND sort_order > ?',
      whereArgs: whereArg != null ? [whereArg, myOrder] : [myOrder],
      orderBy: 'sort_order ASC',
      limit: 1,
    );
    if (below.isEmpty) return;
    final belowOrder = below.first['sort_order'] as int;
    final belowId = below.first['id'] as int;
    await _db.update(
      'memos',
      {'sort_order': belowOrder},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.update(
      'memos',
      {'sort_order': myOrder},
      where: 'id = ?',
      whereArgs: [belowId],
    );
  }
}
