import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../services/notification_service.dart';
import '../services/reminder_coordinator.dart';
import '../services/reminder_settings_service.dart';
import '../services/task_service.dart';
import 'task_detail_screen.dart';

class FullScreenReminderScreen extends StatefulWidget {
  const FullScreenReminderScreen({
    super.key,
    required this.launch,
    required this.taskService,
    required this.notificationService,
    required this.reminderCoordinator,
    required this.settingsService,
    required this.onOpenToday,
  });

  final ReminderLaunch launch;
  final TaskService taskService;
  final NotificationService notificationService;
  final ReminderCoordinator reminderCoordinator;
  final ReminderSettingsService settingsService;
  final VoidCallback onOpenToday;

  @override
  State<FullScreenReminderScreen> createState() =>
      _FullScreenReminderScreenState();
}

class _FullScreenReminderScreenState extends State<FullScreenReminderScreen> {
  static const _ink = Color(0xFF151A2C);
  static const _inkSurface = Color(0xFF202741);
  static const _lavender = Color(0xFFD9D3FF);
  static const _paper = Color(0xFFFFFDFB);
  static const _mutedOnDark = Color(0xFFBBC1D2);
  static const _text = Color(0xFF151827);
  static const _muted = Color(0xFF6D7180);

  Task? _task;
  List<Task> _todayTasks = const [];
  ({int total, int done}) _progress = (total: 0, done: 0);
  ReminderSettings _settings = const ReminderSettings();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsService.load();
    if (widget.launch.kind == ReminderLaunchKind.task) {
      final taskId = widget.launch.taskId;
      final task = taskId == null
          ? null
          : await widget.taskService.getTaskById(taskId);
      if (task == null || task.isDeleted || task.isCompleted) {
        if (mounted) Navigator.maybePop(context);
        return;
      }
      final progress = await widget.taskService.getSubTaskProgress(task.id!);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _task = task;
        _progress = progress;
        _loading = false;
      });
      return;
    }

    final tasks = await widget.taskService.getActiveTasks();
    final now = DateTime.now();
    final today = tasks.where((task) {
      final due = task.dueDate;
      return !task.isDeleted &&
          !task.isCompleted &&
          due != null &&
          due.year == now.year &&
          due.month == now.month &&
          due.day == now.day;
    }).toList()..sort(_compareTodayTasks);
    if (today.isEmpty) {
      if (mounted) Navigator.maybePop(context);
      return;
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _todayTasks = today;
      _loading = false;
    });
  }

  int _compareTodayTasks(Task a, Task b) {
    final aTime = a.reminderTime;
    final bTime = b.reminderTime;
    if (aTime != null && bTime != null) {
      final compared = (aTime.hour * 60 + aTime.minute).compareTo(
        bTime.hour * 60 + bTime.minute,
      );
      if (compared != 0) return compared;
    } else if (aTime != null) {
      return -1;
    } else if (bTime != null) {
      return 1;
    }
    return a.weekSortOrder.compareTo(b.weekSortOrder);
  }

  Future<void> _completeTask() async {
    final task = _task;
    if (task == null || _busy) return;
    setState(() => _busy = true);
    await widget.taskService.setTaskCompleted(
      task,
      completed: true,
      source: Task.actionScopeWeek,
    );
    await widget.notificationService.cancelTaskReminder(task.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _snoozeTask() async {
    final task = _task;
    if (task == null || _busy) return;
    setState(() => _busy = true);
    final scheduled = await widget.reminderCoordinator.snoozeTask(
      task,
      const Duration(minutes: 10),
    );
    if (!mounted) return;
    if (scheduled) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('稍后提醒安排失败')));
    }
  }

  Future<void> _openTask() async {
    final task = _task;
    if (task == null) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          task: task,
          taskService: widget.taskService,
          notificationService: widget.notificationService,
          actionScope: Task.actionScopeWeek,
        ),
      ),
    );
  }

  void _openToday() {
    Navigator.pop(context);
    widget.onOpenToday();
  }

  String _timeText(DateTime? value) {
    final time = value ?? DateTime.now();
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _taskTime(Task task) {
    final value = task.reminderTime;
    if (value == null) return '无设定时间';
    return _timeText(value);
  }

  String _stageText(Task task) =>
      task.taskMode == Task.normalMode ? '未分阶段' : '阶段：${task.arrangementLabel}';

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: _ink,
        systemNavigationBarColor: _ink,
      ),
      child: Scaffold(
        backgroundColor: _ink,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _lavender))
              : LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                        child: widget.launch.kind == ReminderLaunchKind.task
                            ? _buildTaskReminder(context)
                            : _buildDailyReview(context),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(String subtitle) {
    return Row(
      children: [
        const _StrideMark(size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stride',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: _mutedOnDark, fontSize: 15),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: '关闭本次提醒',
          onPressed: () => Navigator.pop(context),
          style: IconButton.styleFrom(
            backgroundColor: _inkSurface,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _buildTaskReminder(BuildContext context) {
    final task = _task!;
    final scheduled = widget.launch.scheduledFor ?? task.reminderTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('任务时间到了'),
        const SizedBox(height: 42),
        Text(
          _timeText(scheduled),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 58,
            height: 1,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '现在，该专注这一件事',
          style: TextStyle(color: _mutedOnDark, fontSize: 20),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  task.category,
                  style: const TextStyle(
                    color: Color(0xFF6255B6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                task.title,
                style: const TextStyle(
                  color: _text,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '今天 · ${_taskTime(task)} · ${_stageText(task)}',
                style: const TextStyle(color: _muted, fontSize: 16),
              ),
              if (_progress.total > 0) ...[
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F2F7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('子任务进度', style: TextStyle(color: _muted)),
                          const Spacer(),
                          Text(
                            '${_progress.done} / ${_progress.total}',
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _progress.done / _progress.total,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ],
              if (task.note.trim().isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('备注', style: TextStyle(color: _muted)),
                const SizedBox(height: 6),
                Text(
                  task.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          key: const Key('full-screen-complete-task'),
          onPressed: _busy ? null : _completeTask,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: _lavender,
            foregroundColor: _text,
          ),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text(
            '完成任务',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('full-screen-snooze-task'),
          onPressed: _busy ? null : _snoozeTask,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF505A76)),
          ),
          icon: const Icon(Icons.schedule_outlined),
          label: const Text(
            '稍后 10 分钟',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('full-screen-open-task'),
          onPressed: _openTask,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: const Color(0xFFD5D9E5),
          ),
          child: const Text('打开任务详情'),
        ),
      ],
    );
  }

  Widget _buildDailyReview(BuildContext context) {
    final lead = _todayTasks.first;
    final rest = _todayTasks.skip(1).take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('今日任务巡检'),
        const SizedBox(height: 42),
        const Text('今天还有', style: TextStyle(color: _mutedOnDark, fontSize: 22)),
        Text(
          '${_todayTasks.length} 件事',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 50,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_timeText(widget.launch.scheduledFor)} · '
          '最早待处理 ${_taskTime(lead)}',
          style: const TextStyle(color: _mutedOnDark, fontSize: 16),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '优先处理',
                style: TextStyle(
                  color: Color(0xFF6255B6),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                lead.title,
                style: const TextStyle(
                  color: _text,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_taskTime(lead)} · ${lead.category} · ${_stageText(lead)}',
                style: const TextStyle(color: _muted),
              ),
              if (rest.isNotEmpty) const Divider(height: 32),
              for (final task in rest)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.radio_button_unchecked,
                          color: Color(0xFF858B9B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${task.category} · ${_taskTime(task)}',
                              style: const TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_todayTasks.length > 4)
                Text(
                  '另有 ${_todayTasks.length - 4} 件任务',
                  style: const TextStyle(color: _muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          key: const Key('full-screen-open-today'),
          onPressed: _openToday,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: _lavender,
            foregroundColor: _text,
          ),
          child: const Text(
            '打开今日安排',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('full-screen-dismiss-daily'),
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF505A76)),
          ),
          icon: const Icon(Icons.schedule_outlined),
          label: Text(
            '${_settings.intervalLabel}后再提醒',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFCBD0DE),
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('关闭本次提醒'),
        ),
      ],
    );
  }
}

class _StrideMark extends StatelessWidget {
  const _StrideMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _StrideMarkPainter()),
  );
}

class _StrideMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = const Color(0xFFE8EAF0);
    final accent = Paint()..color = const Color(0xFF8794B4);
    for (var index = 0; index < 6; index++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(index * 3.1415926535 / 3);
      final path = Path()
        ..moveTo(-4, -9)
        ..lineTo(0, -23)
        ..lineTo(8, -14)
        ..lineTo(7, -3)
        ..close();
      canvas.drawPath(path, index.isEven ? paint : accent);
      canvas.restore();
    }
    final core = Paint()
      ..color = const Color(0xFF202741)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, core);
    final tick = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final tickPath = Path()
      ..moveTo(center.dx - 4, center.dy)
      ..lineTo(center.dx - 1, center.dy + 3)
      ..lineTo(center.dx + 5, center.dy - 4);
    canvas.drawPath(tickPath, tick);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
