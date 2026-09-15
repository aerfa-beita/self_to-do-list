import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/task.dart';
import 'sync_gateway.dart';

class SyncEngine {
  SyncEngine(this._db, this._gateway);

  final Database _db;
  final SyncGateway _gateway;

  static const _tables = {
    'task': 'tasks',
    'subtask': 'subtasks',
    'memo': 'memos',
    'category': 'categories',
    'memo_category': 'memo_categories',
    'task_memo_link': 'task_memo_links',
  };

  Future<int> pendingCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_outbox',
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> syncNow() async {
    await _pushPending();
    return _pullRemote();
  }

  Future<void> _pushPending() async {
    while (true) {
      final rows = await _db.query(
        'sync_outbox',
        orderBy: 'changed_at ASC',
        limit: 100,
      );
      if (rows.isEmpty) return;
      final changes = <CloudChange>[];
      for (final row in rows) {
        changes.add(await _toCloudChange(row));
      }
      try {
        await _gateway.push(changes);
        final ids = rows.map((row) => row['id']).toList();
        await _db.delete(
          'sync_outbox',
          where: 'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        );
      } catch (error) {
        for (final row in rows) {
          await _db.update(
            'sync_outbox',
            {
              'attempt_count': ((row['attempt_count'] as int?) ?? 0) + 1,
              'error_message': '$error',
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        rethrow;
      }
    }
  }

  Future<CloudChange> _toCloudChange(Map<String, Object?> outbox) async {
    final entityType = outbox['entity_type'] as String;
    final syncId = outbox['entity_sync_id'] as String;
    final operation = outbox['operation'] as String;
    var payload = <String, dynamic>{};
    var revision = 1;
    if (operation != 'delete') {
      final table = _tables[entityType]!;
      final rows = await _db.query(
        table,
        where: 'sync_id = ?',
        whereArgs: [syncId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        payload = Map<String, dynamic>.from(rows.first)..remove('id');
        revision = payload['revision'] as int? ?? 1;
        await _replaceForeignIdsWithSyncIds(entityType, payload);
      }
    }
    return CloudChange(
      entityType: entityType,
      entityId: syncId,
      operation: operation,
      payload: payload,
      revision: revision,
      updatedAt: DateTime.parse(outbox['changed_at'] as String).toUtc(),
    );
  }

  Future<void> _replaceForeignIdsWithSyncIds(
    String entityType,
    Map<String, dynamic> payload,
  ) async {
    if (entityType == 'memo') {
      payload['parent_sync_id'] = await _syncIdFor(
        'memos',
        payload.remove('parent_id'),
      );
    } else if (entityType == 'subtask') {
      payload['task_sync_id'] = await _syncIdFor(
        'tasks',
        payload.remove('task_id'),
      );
      payload['parent_sync_id'] = await _syncIdFor(
        'subtasks',
        payload.remove('parent_id'),
      );
    } else if (entityType == 'task_memo_link') {
      payload['task_sync_id'] = await _syncIdFor(
        'tasks',
        payload.remove('task_id'),
      );
      payload['memo_sync_id'] = await _syncIdFor(
        'memos',
        payload.remove('memo_id'),
      );
    }
  }

  Future<String?> _syncIdFor(String table, Object? id) async {
    if (id == null) return null;
    final rows = await _db.query(
      table,
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['sync_id'] as String?;
  }

  Future<int> _pullRemote() async {
    // 数据量较小，完整拉取可避免两台设备时钟不一致造成增量游标漏数据。
    final changes = await _gateway.pull();
    const priority = {
      'category': 0,
      'memo_category': 0,
      'task': 1,
      'memo': 2,
      'subtask': 3,
      'task_memo_link': 4,
    };
    changes.sort((a, b) {
      final typeOrder = (priority[a.entityType] ?? 99).compareTo(
        priority[b.entityType] ?? 99,
      );
      return typeOrder != 0 ? typeOrder : a.updatedAt.compareTo(b.updatedAt);
    });
    await _db.update('sync_runtime', {
      'is_applying_remote': 1,
    }, where: 'id = 1');
    try {
      for (final change in changes) {
        await _applyRemote(change);
      }
      // 同类型记录的更新时间不保证父级先于子级；第二遍只修复外键关系。
      for (final change in changes.where(
        (item) =>
            item.operation != 'delete' &&
            (item.entityType == 'memo' ||
                item.entityType == 'subtask' ||
                item.entityType == 'task_memo_link'),
      )) {
        await _repairRemoteRelations(change);
      }
    } finally {
      await _db.update('sync_runtime', {
        'is_applying_remote': 0,
      }, where: 'id = 1');
    }
    await _db.insert('sync_state', {
      'key': 'last_pull_at',
      'value': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return changes.length;
  }

  Future<void> _repairRemoteRelations(CloudChange change) async {
    final table = _tables[change.entityType];
    if (table == null) return;
    final payload = Map<String, dynamic>.from(change.payload);
    await _replaceSyncIdsWithForeignIds(change.entityType, payload);
    final relationValues = switch (change.entityType) {
      'memo' => <String, Object?>{'parent_id': payload['parent_id']},
      'subtask' => <String, Object?>{
        'task_id': payload['task_id'],
        'parent_id': payload['parent_id'],
      },
      'task_memo_link' => <String, Object?>{
        'task_id': payload['task_id'],
        'memo_id': payload['memo_id'],
      },
      _ => const <String, Object?>{},
    };
    if (relationValues.isEmpty) return;
    await _db.update(
      table,
      relationValues,
      where: 'sync_id = ?',
      whereArgs: [change.entityId],
    );
  }

  Future<void> _applyRemote(CloudChange change) async {
    final table = _tables[change.entityType];
    if (table == null) return;
    final pending = await _db.query(
      'sync_outbox',
      where: 'entity_type = ? AND entity_sync_id = ?',
      whereArgs: [change.entityType, change.entityId],
      limit: 1,
    );
    final local = await _db.query(
      table,
      where: 'sync_id = ?',
      whereArgs: [change.entityId],
      limit: 1,
    );
    if (pending.isNotEmpty && local.isNotEmpty) {
      await _db.insert('sync_conflicts', {
        'entity_type': change.entityType,
        'entity_sync_id': change.entityId,
        'local_payload': jsonEncode(local.first),
        'remote_payload': jsonEncode(change.payload),
        'created_at': DateTime.now().toIso8601String(),
      });
      return;
    }
    if (change.operation == 'delete') {
      await _db.delete(
        table,
        where: 'sync_id = ?',
        whereArgs: [change.entityId],
      );
      return;
    }
    final payload = Map<String, dynamic>.from(change.payload)
      ..remove('id')
      ..['sync_id'] = change.entityId
      ..['revision'] = change.revision;
    if (change.entityType == 'task' &&
        !payload.containsKey('week_sort_order')) {
      payload['week_sort_order'] = local.isEmpty
          ? (payload['sort_order'] ?? 0)
          : (local.first['week_sort_order'] ?? payload['sort_order'] ?? 0);
    }
    if (change.entityType == 'task') {
      final inferredScope = Task.inferActionScope(
        taskMode: payload['task_mode'] as String?,
        dueDate: payload['due_date'],
      );
      if (payload['completed_at'] != null &&
          Task.normalizeActionScope(payload['completed_scope'] as String?) ==
              null) {
        payload['completed_scope'] = inferredScope;
      }
      if (payload['deleted_at'] != null &&
          Task.normalizeActionScope(payload['deleted_scope'] as String?) ==
              null) {
        payload['deleted_scope'] = inferredScope;
      }
    }
    await _replaceSyncIdsWithForeignIds(change.entityType, payload);
    if (local.isEmpty) {
      await _db.insert(
        table,
        payload,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await _db.update(
        table,
        payload,
        where: 'sync_id = ?',
        whereArgs: [change.entityId],
      );
    }
  }

  Future<void> _replaceSyncIdsWithForeignIds(
    String entityType,
    Map<String, dynamic> payload,
  ) async {
    if (entityType == 'memo') {
      payload['parent_id'] = await _idFor(
        'memos',
        payload.remove('parent_sync_id'),
      );
    } else if (entityType == 'subtask') {
      payload['task_id'] = await _idFor(
        'tasks',
        payload.remove('task_sync_id'),
      );
      payload['parent_id'] = await _idFor(
        'subtasks',
        payload.remove('parent_sync_id'),
      );
    } else if (entityType == 'task_memo_link') {
      payload['task_id'] = await _idFor(
        'tasks',
        payload.remove('task_sync_id'),
      );
      payload['memo_id'] = await _idFor(
        'memos',
        payload.remove('memo_sync_id'),
      );
    }
  }

  Future<int?> _idFor(String table, Object? syncId) async {
    if (syncId == null) return null;
    final rows = await _db.query(
      table,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }
}
