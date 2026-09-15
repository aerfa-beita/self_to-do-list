enum SyncPhase { disabled, signedOut, idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus({
    required this.phase,
    required this.pendingCount,
    this.lastSyncedAt,
    this.message,
  });

  const SyncStatus.disabled()
    : phase = SyncPhase.disabled,
      pendingCount = 0,
      lastSyncedAt = null,
      message = '同步未配置';

  const SyncStatus.signedOut()
    : phase = SyncPhase.signedOut,
      pendingCount = 0,
      lastSyncedAt = null,
      message = '登录后同步';

  final SyncPhase phase;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? message;
}
