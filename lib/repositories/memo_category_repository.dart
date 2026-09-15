import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/sync_id.dart';

/// memo_categories 表数据访问
class MemoCategoryRepository {
  final Database _db;

  MemoCategoryRepository(this._db);

  Future<List<Map<String, dynamic>>> getAll() async {
    return _db.query('memo_categories', orderBy: 'sort_order ASC, id ASC');
  }

  Future<int> add(String name, String color) async {
    final maxOrder = await _db.rawQuery(
      'SELECT MAX(sort_order) as m FROM memo_categories',
    );
    final nextOrder = ((maxOrder.first['m'] as int?) ?? 0) + 1;
    return _db.insert('memo_categories', {
      'name': name,
      'color': color,
      'sort_order': nextOrder,
      'sync_id': SyncId.generate(),
      'updated_at': DateTime.now().toIso8601String(),
      'revision': 1,
    });
  }

  Future<void> update(int id, String name, String color) async {
    final old = await _db.query(
      'memo_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (old.isEmpty) return;
    final oldName = old.first['name'] as String;
    await _db.update(
      'memo_categories',
      {
        'name': name,
        'color': color,
        'updated_at': DateTime.now().toIso8601String(),
        'revision': ((old.first['revision'] as int?) ?? 1) + 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (oldName != name) {
      await _db.update(
        'memos',
        {'category': name},
        where: 'category = ?',
        whereArgs: [oldName],
      );
    }
  }

  Future<void> delete(int id) async {
    final cat = await _db.query(
      'memo_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (cat.isEmpty) return;
    final name = cat.first['name'] as String;
    await _db.update(
      'memos',
      {'category': '紧急+重要+必须'},
      where: 'category = ?',
      whereArgs: [name],
    );
    await _db.delete('memo_categories', where: 'id = ?', whereArgs: [id]);
  }
}
