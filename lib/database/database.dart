import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 数据库提供者——仅负责 DB 初始化、迁移、连接
class DatabaseProvider {
  DatabaseProvider._();
  static final DatabaseProvider _instance = DatabaseProvider._();
  factory DatabaseProvider() => _instance;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'todo_list.db');

    final db = await openDatabase(
      path,
      version: 17,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    await _fixSortOrderIfNeeded(db);
    return db;
  }

  // ── 建表 ──

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '默认',
        created_at TEXT NOT NULL,
        completed_at TEXT,
        deleted_at TEXT,
        due_date TEXT,
        reminder_time TEXT,
        repeat_type TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE subtasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        parent_id INTEGER,
        level INTEGER NOT NULL DEFAULT 0,
        title TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        reminder_time TEXT,
        repeat_type TEXT,
        deleted_at TEXT,
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE memos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        level INTEGER NOT NULL DEFAULT 0,
        content TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '紧急+重要+必须',
        sort_order INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        reminder_time TEXT,
        repeat_type TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE memo_categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _seedMemoCategories(db);
    await _seedCategories(db);
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ── 迁移链 ──

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS todos');
      await db.execute('DROP TABLE IF EXISTS subtasks');
      await db.execute('DROP TABLE IF EXISTS tasks');
      await db.execute('DROP TABLE IF EXISTS categories');
      await _onCreate(db, 5);
      return;
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await _seedCategories(db);
    }
    if (oldVersion < 4) {
      try { await db.execute('ALTER TABLE tasks ADD COLUMN completed_at TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE tasks ADD COLUMN deleted_at TEXT'); } catch (_) {}
    }
    if (oldVersion < 5) {
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN parent_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN level INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
    }
    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE tasks ADD COLUMN due_date TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE tasks ADD COLUMN reminder_time TEXT'); } catch (_) {}
    }
    if (oldVersion < 7) {
      try { await db.execute('ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update('tasks', {'sort_order': i}, where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }
    if (oldVersion < 8) {
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update('tasks', {'sort_order': i}, where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS memos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      try { await db.execute('ALTER TABLE memos ADD COLUMN parent_id INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE memos ADD COLUMN level INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE memos ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      final rows = await db.query('memos', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update('memos', {'sort_order': i}, where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }
    if (oldVersion < 11) {
      try { await db.execute('ALTER TABLE memos ADD COLUMN due_date TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE memos ADD COLUMN reminder_time TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN due_date TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN reminder_time TEXT'); } catch (_) {}
    }
    if (oldVersion < 12) {
      try { await db.execute('ALTER TABLE memos ADD COLUMN deleted_at TEXT'); } catch (_) {}
    }
    if (oldVersion < 13) {
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN deleted_at TEXT'); } catch (_) {}
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 16) {
      try { await db.execute('ALTER TABLE tasks ADD COLUMN repeat_type TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN repeat_type TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE memos ADD COLUMN repeat_type TEXT'); } catch (_) {}
    }
    if (oldVersion < 15) {
      try { await db.execute('ALTER TABLE subtasks ADD COLUMN deleted_at TEXT'); } catch (_) {}
    }
    if (oldVersion < 14) {
      try { await db.execute('ALTER TABLE memos ADD COLUMN category TEXT NOT NULL DEFAULT \'紧急+重要+必须\''); } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS memo_categories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await _seedMemoCategories(db);
    }
    await _ensureColumn(db, 'tasks', 'sort_order', 'INTEGER NOT NULL DEFAULT 0');
  }

  // ── 兜底工具 ──

  Future<void> _ensureColumn(Database db, String table, String column, String definition) async {
    final result = await db.rawQuery("PRAGMA table_info('$table')");
    final exists = result.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _fixSortOrderIfNeeded(Database db) async {
    final count = await db.rawQuery('SELECT COUNT(DISTINCT sort_order) as c FROM tasks');
    final distinct = (count.first['c'] as int?) ?? 0;
    final total = await db.rawQuery('SELECT COUNT(*) as c FROM tasks');
    final all = (total.first['c'] as int?) ?? 0;
    if (distinct <= 1 && all > 1) {
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update('tasks', {'sort_order': i}, where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }
  }

  Future<void> _seedMemoCategories(Database db) async {
    final defaults = [
      {'name': '紧急+重要+必须', 'color': '#F44336', 'sort_order': 0},
      {'name': '紧急+重要+不必须', 'color': '#FF5722', 'sort_order': 1},
      {'name': '紧急+不重要+必须', 'color': '#FF9800', 'sort_order': 2},
      {'name': '紧急+不重要+不必须', 'color': '#FFC107', 'sort_order': 3},
      {'name': '不紧急+重要+必须', 'color': '#4CAF50', 'sort_order': 4},
      {'name': '不紧急+重要+不必须', 'color': '#2196F3', 'sort_order': 5},
      {'name': '不紧急+不重要+必须', 'color': '#607D8B', 'sort_order': 6},
      {'name': '不紧急+不重要+不必须', 'color': '#9E9E9E', 'sort_order': 7},
    ];
    for (final cat in defaults) {
      await db.insert('memo_categories', cat, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _seedCategories(Database db) async {
    final defaults = [
      {'name': '默认', 'color': '#607D8B', 'sort_order': 0},
      {'name': '工作', 'color': '#2196F3', 'sort_order': 1},
      {'name': '学习', 'color': '#4CAF50', 'sort_order': 2},
      {'name': '生活', 'color': '#FF9800', 'sort_order': 3},
      {'name': '重要', 'color': '#F44336', 'sort_order': 4},
    ];
    for (final cat in defaults) {
      await db.insert('categories', cat, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 导出所有数据为 JSON 文件，返回文件路径
  Future<String> exportAllJson() async {
    final db = await database;
    final data = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'tasks': await db.query('tasks', orderBy: 'id ASC'),
      'subtasks': await db.query('subtasks', orderBy: 'id ASC'),
      'categories': await db.query('categories', orderBy: 'id ASC'),
      'memos': await db.query('memos', orderBy: 'id ASC'),
      'memo_categories': await db.query('memo_categories', orderBy: 'id ASC'),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final dir = Directory(join(
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.',
      'Documents',
    ));
    if (!await dir.exists()) await dir.create(recursive: true);
    final fileName = 'todo_list_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0]}.json';
    final file = File(join(dir.path, fileName));
    await file.writeAsString(jsonStr, encoding: utf8);
    return file.path;
  }
}
