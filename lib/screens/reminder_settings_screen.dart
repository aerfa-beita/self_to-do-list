import 'dart:io';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/reminder_coordinator.dart';
import '../services/reminder_settings_service.dart';

class ReminderSettingsScreen extends StatefulWidget {
  ReminderSettingsScreen({
    super.key,
    required this.settingsService,
    required this.notificationService,
    required this.reminderCoordinator,
    bool? androidPlatform,
  }) : androidPlatform = androidPlatform ?? Platform.isAndroid;

  final ReminderSettingsService settingsService;
  final NotificationService notificationService;
  final ReminderCoordinator reminderCoordinator;
  final bool androidPlatform;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen>
    with WidgetsBindingObserver {
  ReminderSettings? _settings;
  bool _fullScreenAllowed = false;
  bool _requestingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPermission();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.load();
    final allowed = await widget.notificationService.canUseFullScreenIntent();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _fullScreenAllowed = allowed;
    });
  }

  Future<void> _loadPermission() async {
    final allowed = await widget.notificationService.canUseFullScreenIntent();
    if (mounted) setState(() => _fullScreenAllowed = allowed);
  }

  Future<void> _requestPermission() async {
    if (_requestingPermission) return;
    setState(() => _requestingPermission = true);
    await widget.notificationService.requestFullScreenIntentPermission();
    await _loadPermission();
    if (mounted) setState(() => _requestingPermission = false);
  }

  Future<void> _save(ReminderSettings value) async {
    final normalized = value.normalized();
    setState(() => _settings = normalized);
    await widget.settingsService.save(normalized);
    await widget.reminderCoordinator.refreshNow();
  }

  Future<void> _pickReminderWindow() async {
    final settings = _settings;
    if (settings == null) return;
    final start = await showTimePicker(
      context: context,
      helpText: '巡检开始时间',
      initialTime: TimeOfDay(
        hour: settings.startMinutes ~/ 60,
        minute: settings.startMinutes % 60,
      ),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: '巡检结束时间',
      initialTime: TimeOfDay(
        hour: settings.endMinutes ~/ 60,
        minute: settings.endMinutes % 60,
      ),
    );
    if (end == null || !mounted) return;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    await _save(
      settings.copyWith(startMinutes: startMinutes, endMinutes: endMinutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _SectionLabel('权限'),
                    _SurfaceCard(
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                            title: const Text(
                              '全屏提醒权限',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              widget.androidPlatform
                                  ? '锁屏时显示整屏，使用中显示持续悬浮提醒'
                                  : '全屏提醒仅在 Android 使用',
                            ),
                            trailing: widget.androidPlatform
                                ? _fullScreenAllowed
                                      ? const _StatusLabel(
                                          text: '已开启',
                                          icon: Icons.check_circle_outline,
                                        )
                                      : FilledButton.tonal(
                                          key: const Key(
                                            'request-full-screen-permission',
                                          ),
                                          onPressed: _requestingPermission
                                              ? null
                                              : _requestPermission,
                                          child: Text(
                                            _requestingPermission
                                                ? '处理中'
                                                : '去开启',
                                          ),
                                        )
                                : null,
                          ),
                          const Divider(height: 24),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '任务到点提醒',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: _StatusLabel(
                              text: '始终开启',
                              icon: Icons.alarm_on_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel('今日任务巡检'),
                    _SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile.adaptive(
                            key: const Key('daily-review-switch'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '定时提醒今日未完成任务',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text('关闭后，任务设定时间的全屏提醒仍会保留'),
                            value: settings.dailyReviewEnabled,
                            onChanged: (value) => _save(
                              settings.copyWith(dailyReviewEnabled: value),
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: settings.dailyReviewEnabled ? 1 : 0.45,
                            duration: const Duration(milliseconds: 180),
                            child: IgnorePointer(
                              ignoring: !settings.dailyReviewEnabled,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 12),
                                  const Text(
                                    '提醒间隔',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SegmentedButton<int>(
                                    key: const Key('daily-review-interval'),
                                    showSelectedIcon: false,
                                    segments: const [
                                      ButtonSegment(
                                        value: 30,
                                        label: Text('30 分钟'),
                                      ),
                                      ButtonSegment(
                                        value: 60,
                                        label: Text('1 小时'),
                                      ),
                                      ButtonSegment(
                                        value: 120,
                                        label: Text('2 小时'),
                                      ),
                                    ],
                                    selected: {settings.intervalMinutes},
                                    onSelectionChanged: (value) => _save(
                                      settings.copyWith(
                                        intervalMinutes: value.first,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 32),
                                  ListTile(
                                    key: const Key('daily-review-window'),
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      '提醒时段',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${settings.formatMinutes(settings.startMinutes)}'
                                          ' — '
                                          '${settings.formatMinutes(settings.endMinutes)}',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.expand_more),
                                      ],
                                    ),
                                    onTap: _pickReminderWindow,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel('提醒规则'),
                    const _SurfaceCard(
                      child: Column(
                        children: [
                          _RuleTile(
                            title: '只提醒今日未完成任务',
                            subtitle: '任务全部完成后自动停止',
                          ),
                          Divider(height: 1),
                          _RuleTile(title: '到点任务优先', subtitle: '与巡检同时触发时只显示一次'),
                          Divider(height: 1),
                          _RuleTile(
                            title: '夜间保持安静',
                            subtitle: '任务自行设定的时间不受时段限制',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '系统限制',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 6),
                          Text('若系统不允许全屏，Stride 会自动改为持续悬浮提醒。'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: Theme.of(context).hintColor),
    ),
  );
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: child,
    ),
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 5),
      Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      Icons.check_circle_outline,
      color: Theme.of(context).colorScheme.tertiary,
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
  );
}
