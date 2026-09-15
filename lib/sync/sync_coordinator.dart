import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sync_config.dart';
import 'sync_engine.dart';
import 'sync_gateway.dart';
import 'sync_status.dart';

class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator({
    required SyncConfig config,
    required SyncEngine engine,
    required SyncGateway gateway,
    required bool Function() isAuthenticated,
  }) : _config = config,
       _engine = engine,
       _gateway = gateway,
       _isAuthenticated = isAuthenticated,
       status = ValueNotifier(
         !config.isBackendConfigured
             ? const SyncStatus.disabled()
             : isAuthenticated()
             ? const SyncStatus(phase: SyncPhase.idle, pendingCount: 0)
             : const SyncStatus.signedOut(),
       );

  final SyncConfig _config;
  final SyncEngine _engine;
  final SyncGateway _gateway;
  final bool Function() _isAuthenticated;
  final ValueNotifier<SyncStatus> status;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  StreamSubscription<void>? _realtimeSubscription;
  bool _running = false;
  bool _observing = false;

  void start() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (!_config.isBackendConfigured || !_isAuthenticated()) {
      status.value = _config.isBackendConfigured
          ? const SyncStatus.signedOut()
          : const SyncStatus.disabled();
      return;
    }
    unawaited(syncNow());
    _periodicTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(syncNow()),
    );
    if (_config.realtimeEnabled && _realtimeSubscription == null) {
      _realtimeSubscription = _gateway.watchRemoteChanges().listen(
        (_) => scheduleSync(delay: const Duration(milliseconds: 500)),
        onError: (_) => scheduleSync(delay: const Duration(seconds: 5)),
      );
    }
  }

  void scheduleSync({Duration delay = const Duration(seconds: 4)}) {
    if (!_config.isBackendConfigured || !_isAuthenticated()) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (!_config.isBackendConfigured || !_isAuthenticated() || _running) return;
    _running = true;
    final pending = await _engine.pendingCount();
    status.value = SyncStatus(phase: SyncPhase.syncing, pendingCount: pending);
    try {
      await _engine.syncNow();
      status.value = SyncStatus(
        phase: SyncPhase.idle,
        pendingCount: await _engine.pendingCount(),
        lastSyncedAt: DateTime.now(),
        message: '同步完成',
      );
    } on SyncAuthenticationException catch (error) {
      status.value = SyncStatus(
        phase: SyncPhase.signedOut,
        pendingCount: await _engine.pendingCount(),
        message: error.message,
      );
    } catch (error) {
      status.value = SyncStatus(
        phase: SyncPhase.offline,
        pendingCount: await _engine.pendingCount(),
        message: '同步失败，修改已保存在本机：$error',
      );
    } finally {
      _running = false;
    }
  }

  Future<void> handleSignedOut() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer?.cancel();
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    status.value = const SyncStatus.signedOut();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncNow());
  }

  Future<void> dispose() async {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    await _realtimeSubscription?.cancel();
    status.dispose();
  }
}
