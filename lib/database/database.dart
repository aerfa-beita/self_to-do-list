import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/sync_id.dart';
import '../models/task.dart';

class BackupPreview {
  const BackupPreview({required this.exportedAt, required this.counts});

  final DateTime? exportedAt;
  final Map<String, int> counts;
  int get total => counts.values.fold(0, (sum, count) => sum + count);
}

class BackupImportResult {
  const BackupImportResult({
    required this.safetyBackupPath,
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  final String safetyBackupPath;
  final int inserted;
  final int updated;
  final int skipped;
}

Future<String> resolveWindowsDatabasePath({
  required String legacyPath,
  required String localAppDataPath,
}) async {
  final stableDirectory = Directory(join(localAppDataPath, 'XiaohuaTodo'));
  if (!await stableDirectory.exists()) {
    await stableDirectory.create(recursive: true);
  }
  final stablePath = join(stableDirectory.path, 'todo_list.db');
  final stableFile = File(stablePath);
  if (await stableFile.exists()) return stablePath;

  final legacyFile = File(legacyPath);
  if (!await legacyFile.exists()) return stablePath;
  await legacyFile.copy(stablePath);
  for (final suffix in ['-wal', '-shm']) {
    final legacySidecar = File('$legacyPath$suffix');
    if (await legacySidecar.exists()) {
      await legacySidecar.copy('$stablePath$suffix');
    }
  }
  return stablePath;
}

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
    // Android 用平台 channel，Windows 用 FFI
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final legacyPath = join(dbPath, 'todo_list.db');
    final path = Platform.isWindows
        ? await resolveWindowsDatabasePath(
            legacyPath: legacyPath,
            localAppDataPath:
                Platform.environment['LOCALAPPDATA'] ??
                join(
                  Platform.environment['USERPROFILE'] ?? '.',
                  'AppData',
                  'Local',
                ),
          )
        : legacyPath;

    return openAtPath(path);
  }

  /// 供迁移验证使用；不会替换应用正在使用的单例连接。
  Future<Database> openAtPath(String path) async {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    await _backupBeforeScopeMigration(path);
    final db = await openDatabase(
      path,
      version: 22,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    await _fixSortOrderIfNeeded(db);
    return db;
  }

  Future<void> _backupBeforeScopeMigration(String path) async {
    if (!await File(path).exists()) return;
    final existing = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );
    final version = (await existing.rawQuery(
      'PRAGMA user_version',
    )).first.values.first;
    await existing.close();
    if (version != 21) return;
    final backupPath = '$path.pre-v22';
    if (await File(backupPath).exists()) return;
    await File(path).copy(backupPath);
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$path$suffix');
      if (await sidecar.exists()) await sidecar.copy('$backupPath$suffix');
    }
  }

  // ── 建表 ──

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1
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
        completed_scope TEXT,
        deleted_at TEXT,
        deleted_scope TEXT,
        due_date TEXT,
        reminder_time TEXT,
        repeat_type TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        week_sort_order INTEGER NOT NULL DEFAULT 0,
        effort_points INTEGER NOT NULL DEFAULT 2,
        companion_stashed_at TEXT,
        task_mode TEXT NOT NULL DEFAULT 'normal',
        sync_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1
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
        sync_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
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
        updated_at TEXT NOT NULL,
        pinned_at TEXT,
        archived_at TEXT,
        sync_id TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE memo_categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1
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
    await _createSyncTables(db);
    await _createSyncTriggers(db);
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
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN completed_at TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN deleted_at TEXT');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE subtasks ADD COLUMN parent_id INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE subtasks ADD COLUMN level INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN due_date TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN reminder_time TEXT');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update(
          'tasks',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
      }
    }
    if (oldVersion < 8) {
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update(
          'tasks',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
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
      try {
        await db.execute('ALTER TABLE memos ADD COLUMN parent_id INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE memos ADD COLUMN level INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE memos ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      final rows = await db.query('memos', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update(
          'memos',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
      }
    }
    if (oldVersion < 11) {
      try {
        await db.execute('ALTER TABLE memos ADD COLUMN due_date TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE memos ADD COLUMN reminder_time TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE subtasks ADD COLUMN due_date TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE subtasks ADD COLUMN reminder_time TEXT');
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE memos ADD COLUMN deleted_at TEXT');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE subtasks ADD COLUMN deleted_at TEXT');
      } catch (_) {}
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 18) {
      await _migrateToSyncAndRelations(db);
    }
    if (oldVersion < 19) {
      await _ensureColumn(db, 'tasks', 'companion_stashed_at', 'TEXT');
      await _createSyncTriggers(db);
    }
    if (oldVersion < 20) {
      await _ensureColumn(
        db,
        'tasks',
        'task_mode',
        "TEXT NOT NULL DEFAULT 'normal'",
      );
    }
    if (oldVersion < 21) {
      await _ensureColumn(
        db,
        'tasks',
        'week_sort_order',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('UPDATE tasks SET week_sort_order = sort_order');
    }
    if (oldVersion < 22) {
      await _ensureColumn(db, 'tasks', 'completed_scope', 'TEXT');
      await _ensureColumn(db, 'tasks', 'deleted_scope', 'TEXT');
      const inferredScope = '''
        CASE
          WHEN task_mode != 'normal' THEN 'stage'
          WHEN due_date IS NOT NULL THEN 'week'
          ELSE 'inbox'
        END
      ''';
      await db.execute('''
        UPDATE tasks
        SET completed_scope = $inferredScope
        WHERE completed_at IS NOT NULL
          AND (completed_scope IS NULL OR completed_scope = '')
      ''');
      await db.execute('''
        UPDATE tasks
        SET deleted_scope = $inferredScope
        WHERE deleted_at IS NOT NULL
          AND (deleted_scope IS NULL OR deleted_scope = '')
      ''');
    }
    if (oldVersion < 16) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN repeat_type TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE subtasks ADD COLUMN repeat_type TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE memos ADD COLUMN repeat_type TEXT');
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        await db.execute('ALTER TABLE subtasks ADD COLUMN deleted_at TEXT');
      } catch (_) {}
    }
    if (oldVersion < 14) {
      try {
        await db.execute(
          'ALTER TABLE memos ADD COLUMN category TEXT NOT NULL DEFAULT \'紧急+重要+必须\'',
        );
      } catch (_) {}
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
    await _ensureColumn(
      db,
      'tasks',
      'sort_order',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToSyncAndRelations(Database db) async {
    final now = DateTime.now().toIso8601String();
    for (final table in const [
      'tasks',
      'subtasks',
      'memos',
      'categories',
      'memo_categories',
    ]) {
      await _ensureColumn(db, table, 'sync_id', 'TEXT');
      await _ensureColumn(db, table, 'updated_at', 'TEXT');
      await _ensureColumn(db, table, 'revision', 'INTEGER NOT NULL DEFAULT 1');
      final rows = await db.query(
        table,
        columns: [
          'id',
          'sync_id',
          'updated_at',
          if (table.contains('categories')) 'sort_order',
        ],
      );
      for (final row in rows) {
        final changes = <String, Object?>{};
        final syncId = row['sync_id'] as String?;
        final updatedAt = row['updated_at'] as String?;
        if (syncId == null || syncId.isEmpty) {
          changes['sync_id'] = table == 'categories'
              ? 'category-${row['sort_order']}'
              : table == 'memo_categories'
              ? 'memo-category-${row['sort_order']}'
              : SyncId.generate();
        }
        if (updatedAt == null || updatedAt.isEmpty) changes['updated_at'] = now;
        if (changes.isNotEmpty) {
          await db.update(
            table,
            changes,
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_sync_id ON $table(sync_id)',
      );
    }
    await _ensureColumn(
      db,
      'tasks',
      'effort_points',
      'INTEGER NOT NULL DEFAULT 2',
    );
    await _ensureColumn(db, 'memos', 'pinned_at', 'TEXT');
    await _ensureColumn(db, 'memos', 'archived_at', 'TEXT');
    await _createSyncTables(db);
    await _queueInitialSync(db);
    await _createSyncTriggers(db);
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_memo_links(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        memo_id INTEGER NOT NULL,
        sync_id TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        UNIQUE(task_id, memo_id),
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
        FOREIGN KEY (memo_id) REFERENCES memos(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_sync_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        changed_at TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        UNIQUE(entity_type, entity_sync_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_runtime(
        id INTEGER PRIMARY KEY CHECK(id = 1),
        is_applying_remote INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('sync_runtime', {
      'id': 1,
      'is_applying_remote': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_sync_id TEXT NOT NULL,
        local_payload TEXT NOT NULL,
        remote_payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _queueInitialSync(Database db) async {
    for (final entry in const {
      'tasks': 'task',
      'subtasks': 'subtask',
      'memos': 'memo',
      'categories': 'category',
      'memo_categories': 'memo_category',
      'task_memo_links': 'task_memo_link',
    }.entries) {
      await db.rawInsert(
        '''
        INSERT OR REPLACE INTO sync_outbox(
          entity_type, entity_sync_id, operation, changed_at
        )
        SELECT ?, sync_id, 'upsert', COALESCE(updated_at, ?)
        FROM ${entry.key}
        WHERE sync_id IS NOT NULL AND sync_id != ''
      ''',
        [entry.value, DateTime.now().toIso8601String()],
      );
    }
  }

  Future<void> _createSyncTriggers(Database db) async {
    for (final entry in const {
      'tasks': 'task',
      'subtasks': 'subtask',
      'memos': 'memo',
      'categories': 'category',
      'memo_categories': 'memo_category',
      'task_memo_links': 'task_memo_link',
    }.entries) {
      final table = entry.key;
      final entity = entry.value;
      for (final action in const ['INSERT', 'UPDATE', 'DELETE']) {
        final rowRef = action == 'DELETE' ? 'OLD' : 'NEW';
        final operation = action == 'DELETE' ? 'delete' : 'upsert';
        await db.execute(
          'DROP TRIGGER IF EXISTS sync_${table}_${action.toLowerCase()}',
        );
        await db.execute('''
          CREATE TRIGGER sync_${table}_${action.toLowerCase()}
          AFTER $action ON $table
          WHEN (SELECT is_applying_remote FROM sync_runtime WHERE id = 1) = 0
            AND $rowRef.sync_id IS NOT NULL
            AND $rowRef.sync_id != ''
          BEGIN
            INSERT OR REPLACE INTO sync_outbox(
              entity_type, entity_sync_id, operation, changed_at
            ) VALUES (
              '$entity',
              $rowRef.sync_id,
              '$operation',
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
            );
          END
        ''');
      }
    }
  }

  // ── 兜底工具 ──

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final result = await db.rawQuery("PRAGMA table_info('$table')");
    final exists = result.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _fixSortOrderIfNeeded(Database db) async {
    // ── tasks ──
    final tCount = await db.rawQuery(
      'SELECT COUNT(DISTINCT sort_order) as c FROM tasks',
    );
    final tDistinct = (tCount.first['c'] as int?) ?? 0;
    final tTotal = await db.rawQuery('SELECT COUNT(*) as c FROM tasks');
    final tAll = (tTotal.first['c'] as int?) ?? 0;
    if (tDistinct <= 1 && tAll > 1) {
      final rows = await db.query('tasks', orderBy: 'created_at DESC');
      for (int i = 0; i < rows.length; i++) {
        await db.update(
          'tasks',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
      }
    }
    // ── memos：按父级分组修复 ──
    await _fixGroupedSortOrder(db, 'memos');
    // ── subtasks：按父级分组修复 ──
    await _fixGroupedSortOrder(db, 'subtasks');
  }

  /// 按 parent 分组，每组内按 sort_order → id 重新编号
  Future<void> _fixGroupedSortOrder(Database db, String table) async {
    // 查所有有问题的分组：组内 sort_order 去重后 ≤1 且数量 >1
    final groups = await db.rawQuery('''
      SELECT ${table == 'subtasks' ? 'task_id,' : ''} COALESCE(parent_id, -1) as pid, COUNT(*) as cnt, COUNT(DISTINCT sort_order) as ds
      FROM $table
      GROUP BY pid${table == 'subtasks' ? ', task_id' : ''}
      HAVING ds <= 1 AND cnt > 1
    ''');
    for (final g in groups) {
      final pidRaw = g['pid'] as int;
      final String whereCol;
      final dynamic whereVal;
      if (table == 'subtasks') {
        final taskId = g['task_id'] as int;
        if (pidRaw == -1) {
          whereCol = 'parent_id IS NULL AND task_id = ?';
          whereVal = taskId;
        } else {
          whereCol = 'parent_id = ? AND task_id = ?';
          whereVal = [pidRaw, taskId];
        }
      } else {
        if (pidRaw == -1) {
          whereCol = 'parent_id IS NULL';
          whereVal = null;
        } else {
          whereCol = 'parent_id = ?';
          whereVal = pidRaw;
        }
      }
      final rows = await db.query(
        table,
        where: whereCol,
        whereArgs: whereVal is List
            ? whereVal
            : (whereVal != null ? [whereVal] : null),
        orderBy: 'sort_order ASC, id ASC',
      );
      for (int i = 0; i < rows.length; i++) {
        await db.update(
          table,
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
      }
    }
  }

  Future<void> _seedMemoCategories(Database db) async {
    final now = DateTime.now().toIso8601String();
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
      await db.insert('memo_categories', {
        ...cat,
        'sync_id': 'memo-category-${cat['sort_order']}',
        'updated_at': now,
        'revision': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _seedCategories(Database db) async {
    final now = DateTime.now().toIso8601String();
    final defaults = [
      {'name': '默认', 'color': '#607D8B', 'sort_order': 0},
      {'name': '工作', 'color': '#2196F3', 'sort_order': 1},
      {'name': '学习', 'color': '#4CAF50', 'sort_order': 2},
      {'name': '生活', 'color': '#FF9800', 'sort_order': 3},
      {'name': '重要', 'color': '#F44336', 'sort_order': 4},
    ];
    for (final cat in defaults) {
      await db.insert('categories', {
        ...cat,
        'sync_id': 'category-${cat['sort_order']}',
        'updated_at': now,
        'revision': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 导出所有数据为 JSON 文件，返回文件路径
  Future<String> exportAllJson() async {
    final jsonStr = await exportAllJsonString();
    final dir = Directory(
      join(
        Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            '.',
        'Documents',
      ),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(join(dir.path, _backupFileName()));
    await file.writeAsString(jsonStr, encoding: utf8);
    return file.path;
  }

  Future<String> exportAllJsonString() async {
    final db = await database;
    return _exportAllJsonStringFrom(db);
  }

  Future<String> _exportAllJsonStringFrom(Database db) async {
    final data = <String, dynamic>{
      'format_version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'tasks': await db.query('tasks', orderBy: 'id ASC'),
      'subtasks': await db.query('subtasks', orderBy: 'id ASC'),
      'categories': await db.query('categories', orderBy: 'id ASC'),
      'memos': await db.query('memos', orderBy: 'id ASC'),
      'memo_categories': await db.query('memo_categories', orderBy: 'id ASC'),
      'task_memo_links': await db.query('task_memo_links', orderBy: 'id ASC'),
      'settings': await db.query('settings', orderBy: 'key ASC'),
      'sync_conflicts': await db.query('sync_conflicts', orderBy: 'id ASC'),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  BackupPreview previewBackup(String jsonText) {
    final root = jsonDecode(jsonText);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('不是有效的 Todo List 备份文件');
    }
    const tables = [
      'tasks',
      'subtasks',
      'categories',
      'memos',
      'memo_categories',
      'task_memo_links',
      'settings',
    ];
    final counts = <String, int>{};
    for (final table in tables) {
      final rows = root[table];
      if (rows != null && rows is! List) {
        throw FormatException('$table 数据格式不正确');
      }
      counts[table] = (rows as List?)?.length ?? 0;
    }
    if (counts.values.every((count) => count == 0)) {
      throw const FormatException('备份文件中没有可导入的数据');
    }
    return BackupPreview(
      exportedAt: DateTime.tryParse(root['exported_at'] as String? ?? ''),
      counts: counts,
    );
  }

  Future<BackupImportResult> importAllJsonMerge(
    String jsonText, {
    Database? targetDatabase,
    String? safetyDirectory,
  }) async {
    previewBackup(jsonText);
    final root = jsonDecode(jsonText) as Map<String, dynamic>;
    final exportedAt = root['exported_at'] as String?;
    final importTimestamp =
        DateTime.tryParse(exportedAt ?? '')?.toIso8601String() ??
        DateTime.now().toIso8601String();
    final db = targetDatabase ?? await database;
    final safetyDir = Directory(
      safetyDirectory ?? join(dirname(db.path), 'backups'),
    );
    if (!await safetyDir.exists()) await safetyDir.create(recursive: true);
    final safetyFile = File(
      join(safetyDir.path, _backupFileName('pre-import')),
    );
    await safetyFile.writeAsString(
      await _exportAllJsonStringFrom(db),
      encoding: utf8,
    );

    var inserted = 0;
    var updated = 0;
    var skipped = 0;
    await db.transaction((txn) async {
      final columnCache = <String, Set<String>>{};
      Future<Set<String>> columnsFor(String table) async {
        if (columnCache[table] case final cached?) return cached;
        final info = await txn.rawQuery("PRAGMA table_info('$table')");
        final columns = info.map((row) => row['name'] as String).toSet();
        columnCache[table] = columns;
        return columns;
      }

      List<Map<String, dynamic>> rows(String table) =>
          ((root[table] as List?) ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();

      bool incomingIsNewer(
        Map<String, dynamic> incoming,
        Map<String, Object?> local,
      ) {
        final incomingRevision = (incoming['revision'] as num?)?.toInt() ?? 1;
        final localRevision = (local['revision'] as num?)?.toInt() ?? 1;
        if (incomingRevision != localRevision) {
          return incomingRevision > localRevision;
        }
        final incomingTime = DateTime.tryParse(
          incoming['updated_at'] as String? ?? '',
        );
        final localTime = DateTime.tryParse(
          local['updated_at'] as String? ?? '',
        );
        if (incomingTime == null) return false;
        return localTime == null || incomingTime.isAfter(localTime);
      }

      Future<int> mergeRow(
        String table,
        Map<String, dynamic> source, {
        String? alternateKey,
      }) async {
        final sourceId = source['id'];
        final allowed = await columnsFor(table);
        final row = Map<String, dynamic>.from(source)..remove('id');
        row.removeWhere((key, _) => !allowed.contains(key));
        if (allowed.contains('sync_id')) {
          final identity =
              sourceId ?? source[alternateKey] ?? jsonEncode(source);
          row['sync_id'] ??= SyncId.fromLegacy(
            '$importTimestamp:$table:$identity',
          );
        }
        if (allowed.contains('updated_at')) {
          row['updated_at'] ??= source['created_at'] ?? importTimestamp;
        }
        if (allowed.contains('revision')) {
          row['revision'] ??= 1;
        }
        List<Map<String, Object?>> existing = [];
        if (row['sync_id'] != null) {
          existing = await txn.query(
            table,
            where: 'sync_id = ?',
            whereArgs: [row['sync_id']],
            limit: 1,
          );
        }
        if (existing.isEmpty &&
            alternateKey != null &&
            row[alternateKey] != null) {
          existing = await txn.query(
            table,
            where: '$alternateKey = ?',
            whereArgs: [row[alternateKey]],
            limit: 1,
          );
        }
        if (table == 'tasks' && !row.containsKey('week_sort_order')) {
          row['week_sort_order'] = existing.isEmpty
              ? (row['sort_order'] ?? 0)
              : (existing.first['week_sort_order'] ?? row['sort_order'] ?? 0);
        }
        if (table == 'tasks') {
          final inferredScope = Task.inferActionScope(
            taskMode: source['task_mode'] as String?,
            dueDate: source['due_date'],
          );
          if (source['completed_at'] != null &&
              Task.normalizeActionScope(source['completed_scope'] as String?) ==
                  null) {
            row['completed_scope'] = inferredScope;
          }
          if (source['deleted_at'] != null &&
              Task.normalizeActionScope(source['deleted_scope'] as String?) ==
                  null) {
            row['deleted_scope'] = inferredScope;
          }
        }
        if (existing.isEmpty) {
          inserted++;
          return txn.insert(table, row);
        }
        final local = existing.first;
        if (incomingIsNewer(row, local)) {
          updated++;
          await txn.update(
            table,
            row,
            where: 'id = ?',
            whereArgs: [local['id']],
          );
        } else {
          skipped++;
        }
        return local['id'] as int? ?? (sourceId as num?)?.toInt() ?? 0;
      }

      for (final table in const ['categories', 'memo_categories']) {
        for (final row in rows(table)) {
          await mergeRow(table, row, alternateKey: 'name');
        }
      }

      final taskIds = <int, int>{};
      for (final row in rows('tasks')) {
        final sourceId = (row['id'] as num?)?.toInt();
        final localId = await mergeRow('tasks', row);
        if (sourceId != null) taskIds[sourceId] = localId;
      }

      final memoRows = rows('memos');
      final memoIds = <int, int>{};
      for (final row in memoRows) {
        final sourceId = (row['id'] as num?)?.toInt();
        final detached = Map<String, dynamic>.from(row)..['parent_id'] = null;
        final localId = await mergeRow('memos', detached);
        if (sourceId != null) memoIds[sourceId] = localId;
      }
      for (final row in memoRows) {
        final sourceId = (row['id'] as num?)?.toInt();
        final parentId = (row['parent_id'] as num?)?.toInt();
        if (sourceId != null && parentId != null && memoIds[parentId] != null) {
          await txn.update(
            'memos',
            {'parent_id': memoIds[parentId]},
            where: 'id = ?',
            whereArgs: [memoIds[sourceId]],
          );
        }
      }

      final subtaskRows = rows('subtasks');
      final subtaskIds = <int, int>{};
      for (final row in subtaskRows) {
        final sourceId = (row['id'] as num?)?.toInt();
        final sourceTaskId = (row['task_id'] as num?)?.toInt();
        final detached = Map<String, dynamic>.from(row)
          ..['task_id'] = taskIds[sourceTaskId]
          ..['parent_id'] = null;
        if (detached['task_id'] == null) {
          skipped++;
          continue;
        }
        final localId = await mergeRow('subtasks', detached);
        if (sourceId != null) subtaskIds[sourceId] = localId;
      }
      for (final row in subtaskRows) {
        final sourceId = (row['id'] as num?)?.toInt();
        final parentId = (row['parent_id'] as num?)?.toInt();
        if (sourceId != null &&
            parentId != null &&
            subtaskIds[parentId] != null) {
          await txn.update(
            'subtasks',
            {'parent_id': subtaskIds[parentId]},
            where: 'id = ?',
            whereArgs: [subtaskIds[sourceId]],
          );
        }
      }

      for (final row in rows('task_memo_links')) {
        final sourceTaskId = (row['task_id'] as num?)?.toInt();
        final sourceMemoId = (row['memo_id'] as num?)?.toInt();
        final mapped = Map<String, dynamic>.from(row)
          ..['task_id'] = taskIds[sourceTaskId]
          ..['memo_id'] = memoIds[sourceMemoId];
        if (mapped['task_id'] == null || mapped['memo_id'] == null) {
          skipped++;
          continue;
        }
        await mergeRow('task_memo_links', mapped);
      }

      for (final row in rows('settings')) {
        if (row['key'] == null || row['value'] == null) continue;
        await txn.insert('settings', {
          'key': row['key'],
          'value': row['value'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        updated++;
      }
    });
    return BackupImportResult(
      safetyBackupPath: safetyFile.path,
      inserted: inserted,
      updated: updated,
      skipped: skipped,
    );
  }

  String _backupFileName([String label = 'backup']) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return 'todo_list_${label}_$stamp.json';
  }
}
