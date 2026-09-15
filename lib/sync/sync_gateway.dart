class SyncAuthenticationException implements Exception {
  const SyncAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudChange {
  const CloudChange({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.revision,
    required this.updatedAt,
  });

  factory CloudChange.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'];
    return CloudChange(
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      operation: map['operation'] as String? ?? 'upsert',
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      revision: map['revision'] as int? ?? 1,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final int revision;
  final DateTime updatedAt;

  Map<String, dynamic> toMap(String userId) => {
    'user_id': userId,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'payload': payload,
    'revision': revision,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

abstract class SyncGateway {
  Future<void> push(List<CloudChange> changes);

  Future<List<CloudChange>> pull({DateTime? changedAfter});

  Stream<void> watchRemoteChanges();
}
