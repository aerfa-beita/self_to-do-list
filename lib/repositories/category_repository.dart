import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// categories 表数据访问——纯 SQL，无业务逻辑
class CategoryRepository {
  final Database _db;

  CategoryRepository(this._db);

  Future<List<Map<String, dynamic>>> getAll() async {
    return _db.query('categories', orderBy: 'sort_order ASC, id ASC');
  }

  Future<int> add(String name, String color) async {
    final maxOrder = await _db.rawQuery('SELECT MAX(sort_order) as m FROM categories');
    final nextOrder = ((maxOrder.first['m'] as int?) ?? 0) + 1;
    return _db.insert('categories', {'name': name, 'color': color, 'sort_order': nextOrder});
  }

  Future<void> update(int id, String name, String color) async {
    final old = await _db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (old.isEmpty) return;
    final oldName = old.first['name'] as String;
    await _db.update('categories', {'name': name, 'color': color},
        where: 'id = ?', whereArgs: [id]);
    if (oldName != name) {
      await _db.update('tasks', {'category': name},
          where: 'category = ?', whereArgs: [oldName]);
    }
  }

  Future<void> delete(int id) async {
    final cat = await _db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (cat.isEmpty) return;
    final name = cat.first['name'] as String;
    await _db.update('tasks', {'category': '默认'},
        where: 'category = ?', whereArgs: [name]);
    await _db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
