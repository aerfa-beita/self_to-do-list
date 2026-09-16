import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/task.dart';

/// tasks 表数据访问——纯 SQL，无业务逻辑
class TaskRepository {
  static const arrangementCollapsedModesKey = 'arrangement_collapsed_modes';

  final Database _db;

  TaskRepository(this._db);

  Future<int> insert(Task task) async {
    final maxOrder = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) as m FROM tasks',
    );
    final nextOrder = ((maxOrder.first['m'] as int?) ?? -1) + 1;
    final map = task.toMap()..remove('id');
    map['sort_order'] = nextOrder;
    map['week_sort_order'] = nextOrder;
    return await _db.insert('tasks', map);
  }

  Future<int> update(Task task) async {
    return await _db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> softDelete(
    int taskId, {
    String source = Task.actionScopeInbox,
  }) async {
    final normalized =
        Task.normalizeActionScope(source) ?? Task.actionScopeInbox;
    await _db.update(
      'tasks',
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_scope': normalized,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<void> softDeleteMany(
    Iterable<int> taskIds, {
    String source = Task.actionScopeInbox,
  }) async {
    final ids = taskIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final deletedAt = DateTime.now().toIso8601String();
    final normalized =
        Task.normalizeActionScope(source) ?? Task.actionScopeInbox;
    await _db.transaction((txn) async {
      for (final taskId in ids) {
        await txn.update(
          'tasks',
          {
            'deleted_at': deletedAt,
            'deleted_scope': normalized,
            'updated_at': deletedAt,
          },
          where: 'id = ?',
          whereArgs: [taskId],
        );
      }
    });
  }

  Future<void> restore(int taskId) async {
    await _db.update(
      'tasks',
      {
        'deleted_at': null,
        'deleted_scope': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<void> permanentlyDelete(int taskId) async {
    await _db.transaction((txn) async {
      await txn.delete('subtasks', where: 'task_id = ?', whereArgs: [taskId]);
      await txn.delete(
        'task_memo_links',
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
      await txn.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
    });
  }

  Future<void> updateSortOrder(int taskId, int order) async {
    await _db.update(
      'tasks',
      {'sort_order': order},
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  /// Reorders only the supplied active task subset while preserving the
  /// positions and relative order of every hidden task.
  Future<void> reorderActiveSubset(List<int> orderedIds) async {
    final ids = List<int>.from(orderedIds);
    if (ids.length < 2 || ids.toSet().length != ids.length) return;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'tasks',
        where: 'deleted_at IS NULL',
        orderBy: 'sort_order ASC, id ASC',
      );
      final byId = <int, Map<String, dynamic>>{
        for (final row in rows) (row['id'] as num).toInt(): row,
      };
      if (ids.any((id) => !byId.containsKey(id))) return;

      final positions = <int>[];
      for (var index = 0; index < rows.length; index++) {
        final id = (rows[index]['id'] as num).toInt();
        if (ids.contains(id)) positions.add(index);
      }
      if (positions.length != ids.length) return;

      final targetOrders = [
        for (final position in positions)
          (rows[position]['sort_order'] as num?)?.toInt() ?? position,
      ];
      final changedIds = <int>[];
      for (var index = 0; index < ids.length; index++) {
        final current = byId[ids[index]]!;
        final currentOrder = (current['sort_order'] as num?)?.toInt() ?? 0;
        if (currentOrder != targetOrders[index]) {
          changedIds.add(ids[index]);
        }
      }
      if (changedIds.isEmpty) return;

      final maxOrder = rows.fold<int>(
        0,
        (max, row) => ((row['sort_order'] as num?)?.toInt() ?? 0) > max
            ? (row['sort_order'] as num).toInt()
            : max,
      );
      final temporaryBase = maxOrder + ids.length + 1;
      for (var index = 0; index < changedIds.length; index++) {
        await txn.update(
          'tasks',
          {'sort_order': temporaryBase + index},
          where: 'id = ?',
          whereArgs: [changedIds[index]],
        );
      }

      final updatedAt = DateTime.now().toIso8601String();
      for (var index = 0; index < ids.length; index++) {
        final id = ids[index];
        if (!changedIds.contains(id)) continue;
        final current = byId[id]!;
        final revision = (current['revision'] as num?)?.toInt() ?? 1;
        await txn.update(
          'tasks',
          {
            'sort_order': targetOrders[index],
            'updated_at': updatedAt,
            'revision': revision + 1,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  /// A day's weekly order is independent of the inbox/stage order.
  Future<void> reorderWeekDay(DateTime day, List<int> orderedIds) async {
    if (orderedIds.toSet().length != orderedIds.length ||
        orderedIds.length < 2) {
      return;
    }
    await _db.transaction((txn) async {
      final rows = await txn.query('tasks', where: 'deleted_at IS NULL');
      final byId = {for (final row in rows) (row['id'] as num).toInt(): row};
      if (orderedIds.any(
        (id) =>
            !byId.containsKey(id) ||
            !_sameDate(byId[id]!['due_date'] as String?, day),
      )) {
        return;
      }
      final orderedSet = orderedIds.toSet();
      final dayRows =
          rows
              .where((row) => _sameDate(row['due_date'] as String?, day))
              .toList()
            ..sort((a, b) {
              final order = ((a['week_sort_order'] as num?)?.toInt() ?? 0)
                  .compareTo((b['week_sort_order'] as num?)?.toInt() ?? 0);
              return order != 0
                  ? order
                  : (a['id'] as num).toInt().compareTo(
                      (b['id'] as num).toInt(),
                    );
            });
      final targetOrders = dayRows
          .where((row) => orderedSet.contains((row['id'] as num).toInt()))
          .map((row) => (row['week_sort_order'] as num?)?.toInt() ?? 0)
          .toList();
      if (targetOrders.length != orderedIds.length) return;
      final now = DateTime.now().toIso8601String();
      for (var i = 0; i < orderedIds.length; i++) {
        final row = byId[orderedIds[i]]!;
        if ((row['week_sort_order'] as num?)?.toInt() == targetOrders[i]) {
          continue;
        }
        await txn.update(
          'tasks',
          {
            'week_sort_order': targetOrders[i],
            'updated_at': now,
            'revision': ((row['revision'] as num?)?.toInt() ?? 1) + 1,
          },
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> moveToWeekDay(Task task, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final max = await _db.rawQuery(
      'SELECT COALESCE(MAX(week_sort_order), -1) AS value FROM tasks '
      'WHERE deleted_at IS NULL AND substr(due_date, 1, 10) = ?',
      [start.toIso8601String().substring(0, 10)],
    );
    await update(
      task.copyWith(
        dueDate: start,
        weekSortOrder: ((max.first['value'] as num?)?.toInt() ?? -1) + 1,
      ),
    );
  }

  bool _sameDate(String? raw, DateTime day) {
    if (raw == null) return false;
    final value = DateTime.tryParse(raw);
    return value != null &&
        value.year == day.year &&
        value.month == day.month &&
        value.day == day.day;
  }

  Future<int> getNextSortOrderForMode(String mode) async {
    final normalized = Task.normalizeMode(mode);
    final where = normalized == Task.planNowMode
        ? "task_mode IN (?, ?)"
        : 'task_mode = ?';
    final whereArgs = normalized == Task.planNowMode
        ? [Task.planNowMode, Task.legacyFlowMode]
        : [normalized];
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS value FROM tasks WHERE $where',
      whereArgs,
    );
    return ((rows.first['value'] as int?) ?? -1) + 1;
  }

  Future<void> moveUp(int taskId) async {
    final neighbor = await _findScopedNeighbor(taskId, moveUp: true);
    if (neighbor == null) return;
    await reorderActiveSubset([taskId, neighbor]);
  }

  Future<void> moveDown(int taskId) async {
    final neighbor = await _findScopedNeighbor(taskId, moveUp: false);
    if (neighbor == null) return;
    await reorderActiveSubset([neighbor, taskId]);
  }

  Future<int?> _findScopedNeighbor(int taskId, {required bool moveUp}) async {
    final rows = await _db.query(
      'tasks',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, id ASC',
    );
    final self = rows.where((row) => row['id'] == taskId).firstOrNull;
    if (self == null) return null;
    final selfOrder = (self['sort_order'] as num?)?.toInt() ?? 0;
    final selfMode = Task.normalizeMode(self['task_mode'] as String?);
    final selfCompleted = self['completed_at'] != null;
    final selfStashed = self['companion_stashed_at'] != null;
    final candidates = rows.where((row) {
      if (row['id'] == taskId) return false;
      if ((row['category'] as String?) != (self['category'] as String?)) {
        return false;
      }
      if ((row['completed_at'] != null) != selfCompleted) return false;
      if (Task.normalizeMode(row['task_mode'] as String?) != selfMode) {
        return false;
      }
      if ((row['companion_stashed_at'] != null) != selfStashed) return false;
      final order = (row['sort_order'] as num?)?.toInt() ?? 0;
      return moveUp ? order < selfOrder : order > selfOrder;
    }).toList();
    if (candidates.isEmpty) return null;
    final neighbor = moveUp ? candidates.last : candidates.first;
    return (neighbor['id'] as num).toInt();
  }

  Future<List<Task>> getActive() async {
    final maps = await _db.query(
      'tasks',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, created_at DESC',
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<List<Task>> getFlows() async {
    final maps = await _db.query(
      'tasks',
      where: "deleted_at IS NULL AND task_mode != ?",
      whereArgs: [Task.normalMode],
      orderBy: 'sort_order ASC, created_at DESC',
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<List<Task>> getDeleted() async {
    final maps = await _db.query(
      'tasks',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  Future<Task?> getById(int id) async {
    final maps = await _db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : Task.fromMap(maps.first);
  }

  Future<void> setCompletedAt(
    int taskId,
    DateTime? time, {
    String? source,
  }) async {
    await _db.update(
      'tasks',
      {
        'completed_at': time?.toIso8601String(),
        'completed_scope': time == null
            ? null
            : Task.normalizeActionScope(source) ?? Task.actionScopeInbox,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<int> getTodayEffort() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(effort_points), 0) AS total
      FROM tasks
      WHERE deleted_at IS NULL
        AND completed_at IS NULL
        AND companion_stashed_at IS NULL
        AND due_date >= ?
        AND due_date < ?
    ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> getDailyEffortLimit() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['daily_effort_limit'],
      limit: 1,
    );
    return rows.isEmpty
        ? 8
        : (int.tryParse(rows.first['value'] as String) ?? 8);
  }

  Future<void> setDailyEffortLimit(int value) async {
    await _db.insert('settings', {
      'key': 'daily_effort_limit',
      'value': value.clamp(1, 30).toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<({double x, double y})?> getCompanionPosition() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['companion_position'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final values = (rows.first['value'] as String).split(',');
    if (values.length != 2) return null;
    final x = double.tryParse(values[0]);
    final y = double.tryParse(values[1]);
    if (x == null || y == null) return null;
    return (x: x.clamp(0.0, 1.0).toDouble(), y: y.clamp(0.0, 1.0).toDouble());
  }

  Future<void> setCompanionPosition(double x, double y) async {
    await _db.insert('settings', {
      'key': 'companion_position',
      'value': '${x.clamp(0, 1)},${y.clamp(0, 1)}',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Set<String>> getArrangementCollapsedModes() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [arrangementCollapsedModesKey],
      limit: 1,
    );
    if (rows.isEmpty) return <String>{};
    final raw = rows.first['value'] as String?;
    if (raw == null || raw.trim().isEmpty) return <String>{};

    Iterable<String> values;
    try {
      final decoded = jsonDecode(raw);
      values = decoded is List ? decoded.whereType<String>() : const <String>[];
    } on FormatException {
      values = raw.split(RegExp(r'[,\\s]+')).where((value) => value.isNotEmpty);
    }
    return values.where(Task.arrangementModes.contains).toSet();
  }

  Future<void> setArrangementCollapsedModes(Set<String> modes) async {
    final value = Task.arrangementModes.where(modes.contains).join(',');
    await _db.insert('settings', {
      'key': arrangementCollapsedModesKey,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
