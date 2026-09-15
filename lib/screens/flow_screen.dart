import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sub_task.dart';
import '../models/task.dart';
import '../services/task_service.dart';

typedef MoveArrangementTask = Future<void> Function(Task task, String mode);
typedef AddArrangementTask = Future<void> Function(String mode);
typedef ReorderArrangementTasks =
    Future<void> Function(String mode, int oldIndex, int newIndex);
typedef ArrangementCollapseChanged = void Function(Set<String> modes);
typedef AddWeeklyTask = Future<void> Function(DateTime date);
typedef ReorderWeeklyTasks =
    Future<void> Function(DateTime day, int oldIndex, int newIndex);
typedef MoveWeeklyTask = Future<void> Function(Task task, DateTime day);

enum ArrangementViewMode { stage, week }

class TaskArrangementView extends StatefulWidget {
  const TaskArrangementView({
    super.key,
    required this.nowTasks,
    required this.nextTasks,
    required this.laterTasks,
    required this.doneNowTasks,
    required this.doneNextTasks,
    required this.doneLaterTasks,
    required this.unplannedTasks,
    required this.onToggleTask,
    required this.onOpenTask,
    required this.onMoveTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTask,
    required this.onReorder,
    this.allUndoneTasks = const <Task>[],
    this.allTasks,
    this.onReorderWeekDay,
    this.onMoveToWeekDay,
    this.onSyncStage,
    this.onSyncToday,
    this.initialMode = ArrangementViewMode.stage,
    this.onModeChanged,
    this.onAddWeeklyTask,
    this.onClearWeeklyCompleted,
    this.today,
    this.onClearCompleted,
    this.collapsedModes = const <String>{},
    this.onCollapsedModesChanged,
  });

  final List<Task> nowTasks;
  final List<Task> nextTasks;
  final List<Task> laterTasks;
  final List<Task> doneNowTasks;
  final List<Task> doneNextTasks;
  final List<Task> doneLaterTasks;
  final List<Task> unplannedTasks;
  final ValueChanged<Task> onToggleTask;
  final ValueChanged<Task> onOpenTask;
  final MoveArrangementTask onMoveTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;
  final AddArrangementTask onAddTask;
  final ReorderArrangementTasks onReorder;
  final List<Task> allUndoneTasks;
  final List<Task>? allTasks;
  final ReorderWeeklyTasks? onReorderWeekDay;
  final MoveWeeklyTask? onMoveToWeekDay;
  final ValueChanged<Task>? onSyncStage;
  final ValueChanged<Task>? onSyncToday;
  final ArrangementViewMode initialMode;
  final ValueChanged<ArrangementViewMode>? onModeChanged;
  final AddWeeklyTask? onAddWeeklyTask;
  final VoidCallback? onClearWeeklyCompleted;
  final DateTime? today;
  final VoidCallback? onClearCompleted;
  final Set<String> collapsedModes;
  final ArrangementCollapseChanged? onCollapsedModesChanged;

  @override
  State<TaskArrangementView> createState() => _TaskArrangementViewState();
}

class _TaskArrangementViewState extends State<TaskArrangementView> {
  int _weekOffset = 0;
  ArrangementViewMode _viewMode = ArrangementViewMode.stage;
  bool _adjustingDates = false;
  Timer? _midnightTimer;
  Timer? _dragScrollTimer;
  Offset? _dragGlobalPosition;
  final ScrollController _weekScrollController = ScrollController();
  final GlobalKey _weekListKey = GlobalKey();
  Set<String> _collapsedModes = <String>{};
  final Set<int> _collapsedWeekdays = <int>{};
  final Set<int> _expandedEmptyWeekdays = <int>{};

  @override
  void initState() {
    super.initState();
    _collapsedModes = _validCollapsedModes(widget.collapsedModes);
    _viewMode = widget.initialMode;
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    if (widget.today != null) return;
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextDay.difference(now) + const Duration(milliseconds: 200),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleMidnightRefresh();
      },
    );
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _dragScrollTimer?.cancel();
    _weekScrollController.dispose();
    super.dispose();
  }

  void _trackWeekDrag(DragUpdateDetails details) {
    _dragGlobalPosition = details.globalPosition;
    _dragScrollTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_weekScrollController.hasClients || _dragGlobalPosition == null) {
        return;
      }
      final box = _weekListKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final y = box.globalToLocal(_dragGlobalPosition!).dy;
      final delta = y < 72 ? -18.0 : (y > box.size.height - 72 ? 18.0 : 0.0);
      if (delta == 0) return;
      final position = _weekScrollController.position;
      _weekScrollController.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _stopWeekDrag() {
    _dragGlobalPosition = null;
    _dragScrollTimer?.cancel();
    _dragScrollTimer = null;
  }

  @override
  void didUpdateWidget(covariant TaskArrangementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _validCollapsedModes(widget.collapsedModes);
    if (!_sameModes(_collapsedModes, next)) {
      _collapsedModes = next;
    }
    if (widget.initialMode != oldWidget.initialMode) {
      _viewMode = widget.initialMode;
    }
  }

  Set<String> _validCollapsedModes(Iterable<String> modes) =>
      modes.where(Task.arrangementModes.contains).toSet();

  bool _sameModes(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  bool get _allStagesCollapsed =>
      Task.arrangementModes.every(_collapsedModes.contains);

  void _toggleStage(String mode) {
    final next = Set<String>.from(_collapsedModes);
    if (!next.add(mode)) next.remove(mode);
    setState(() => _collapsedModes = next);
    widget.onCollapsedModesChanged?.call(Set.unmodifiable(next));
  }

  void _toggleAllStages() {
    final next = _allStagesCollapsed
        ? <String>{}
        : Set<String>.from(Task.arrangementModes);
    setState(() => _collapsedModes = next);
    widget.onCollapsedModesChanged?.call(Set.unmodifiable(next));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('todo-arrangement-view'),
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final switcher = Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SizedBox(
            width: compact ? double.infinity : 360,
            child: SegmentedButton<ArrangementViewMode>(
              key: const Key('arrangement-view-mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ArrangementViewMode.stage,
                  label: Text('阶段'),
                ),
                ButtonSegment(
                  value: ArrangementViewMode.week,
                  label: Text('本周'),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selection) {
                setState(() {
                  _viewMode = selection.first;
                  _adjustingDates = false;
                });
                widget.onModeChanged?.call(selection.first);
              },
            ),
          ),
        );
        if (_viewMode == ArrangementViewMode.week) {
          return Column(
            key: const Key('arrangement-week-view'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              switcher,
              Expanded(child: _weekView(compact)),
            ],
          );
        }
        if (compact) {
          return Column(
            children: [
              switcher,
              Expanded(
                child: ListView(
                  key: const Key('arrangement-mobile'),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    _ArrangementHint(
                      compact: true,
                      allCollapsed: _allStagesCollapsed,
                      onToggleAll: _toggleAllStages,
                    ),
                    const SizedBox(height: 10),
                    _stage(
                      Task.planNowMode,
                      '现在',
                      widget.nowTasks,
                      compact,
                      collapsed: _collapsedModes.contains(Task.planNowMode),
                      onToggleCollapsed: () => _toggleStage(Task.planNowMode),
                    ),
                    const SizedBox(height: 10),
                    _stage(
                      Task.planNextMode,
                      '接下来',
                      widget.nextTasks,
                      compact,
                      collapsed: _collapsedModes.contains(Task.planNextMode),
                      onToggleCollapsed: () => _toggleStage(Task.planNextMode),
                    ),
                    const SizedBox(height: 10),
                    _stage(
                      Task.planLaterMode,
                      '稍后',
                      widget.laterTasks,
                      compact,
                      collapsed: _collapsedModes.contains(Task.planLaterMode),
                      onToggleCollapsed: () => _toggleStage(Task.planLaterMode),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          key: const Key('arrangement-desktop'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switcher,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  children: [
                    const _ArrangementHint(),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _stage(
                              Task.planNowMode,
                              '现在',
                              widget.nowTasks,
                              compact,
                              fillHeight: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _stage(
                              Task.planNextMode,
                              '接下来',
                              widget.nextTasks,
                              compact,
                              fillHeight: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _stage(
                              Task.planLaterMode,
                              '稍后',
                              widget.laterTasks,
                              compact,
                              fillHeight: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  DateTime get _today {
    final value = widget.today ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  DateTime get _weekStart => _today
      .subtract(Duration(days: _today.weekday - 1))
      .add(Duration(days: _weekOffset * 7));

  bool _sameDay(DateTime? value, DateTime day) =>
      value != null &&
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  List<Task> _tasksForDay(DateTime day) {
    final isPast = day.isBefore(_today);
    final tasks = (widget.allTasks ?? widget.allUndoneTasks)
        .where(
          (task) =>
              !task.isDeleted &&
              _sameDay(task.dueDate, day) &&
              (isPast || !task.isCompleted),
        )
        .toList();
    tasks.sort((a, b) {
      final order = a.weekSortOrder.compareTo(b.weekSortOrder);
      return order != 0 ? order : (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return tasks;
  }

  String _weekdayLabel(DateTime day) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final label = labels[day.weekday - 1];
    return _sameDay(day, _today) ? '今天 · $label' : label;
  }

  String _weekRangeLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year && start.month == end.month) {
      return '${start.month}月${start.day}日—${end.day}日';
    }
    return '${start.month}月${start.day}日—${end.month}月${end.day}日';
  }

  Widget _weekView(bool compact) {
    final days = List<DateTime>.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    return KeyedSubtree(
      key: const Key('arrangement-week-list'),
      child: ListView(
        controller: _weekScrollController,
        key: _weekListKey,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _WeekNavigator(
            label: _weekRangeLabel(_weekStart),
            isCurrentWeek: _weekOffset == 0,
            onPrevious: () => setState(() => _weekOffset--),
            onCurrent: () => setState(() => _weekOffset = 0),
            onNext: () => setState(() => _weekOffset++),
            adjustingDates: _adjustingDates,
            onToggleAdjust: () =>
                setState(() => _adjustingDates = !_adjustingDates),
          ),
          if (_adjustingDates)
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text('拖动未完成任务到目标日期'),
            ),
          const SizedBox(height: 10),
          for (final day in days) ...[
            _WeekdayPanel(
              day: day,
              title: _weekdayLabel(day),
              tasks: _tasksForDay(day),
              collapsed: _tasksForDay(day).isEmpty
                  ? !_expandedEmptyWeekdays.contains(day.weekday)
                  : _collapsedWeekdays.contains(day.weekday),
              onToggleCollapsed: () => setState(() {
                final set = _tasksForDay(day).isEmpty
                    ? _expandedEmptyWeekdays
                    : _collapsedWeekdays;
                if (!set.add(day.weekday)) {
                  set.remove(day.weekday);
                }
              }),
              onAddTask: widget.onAddWeeklyTask,
              onToggleTask: widget.onToggleTask,
              onOpenTask: widget.onOpenTask,
              onMoveTask: widget.onMoveTask,
              onEditTask: widget.onEditTask,
              onDeleteTask: widget.onDeleteTask,
              onSyncStage: widget.onSyncStage,
              adjustingDates: _adjustingDates,
              onReorder: widget.onReorderWeekDay == null
                  ? null
                  : (oldIndex, newIndex) =>
                        widget.onReorderWeekDay!(day, oldIndex, newIndex),
              onMoveToDay: widget.onMoveToWeekDay,
              onDragUpdate: _trackWeekDrag,
              onDragEnd: _stopWeekDrag,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _stage(
    String mode,
    String title,
    List<Task> tasks,
    bool compact, {
    bool fillHeight = false,
    bool collapsed = false,
    VoidCallback? onToggleCollapsed,
  }) {
    return _ArrangementStagePanel(
      key: Key('arrangement-stage-$mode'),
      mode: mode,
      title: title,
      tasks: tasks,
      compact: compact,
      fillHeight: fillHeight,
      collapsed: compact && collapsed,
      onToggleCollapsed: onToggleCollapsed,
      onToggleTask: widget.onToggleTask,
      onOpenTask: widget.onOpenTask,
      onMoveTask: widget.onMoveTask,
      onEditTask: widget.onEditTask,
      onDeleteTask: widget.onDeleteTask,
      onSyncToday: widget.onSyncToday,
      onAddTask: widget.onAddTask,
      onReorder: widget.onReorder,
    );
  }
}

class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({
    required this.label,
    required this.isCurrentWeek,
    required this.onPrevious,
    required this.onCurrent,
    required this.onNext,
    required this.adjustingDates,
    required this.onToggleAdjust,
  });

  final String label;
  final bool isCurrentWeek;
  final VoidCallback onPrevious;
  final VoidCallback onCurrent;
  final VoidCallback onNext;
  final bool adjustingDates;
  final VoidCallback onToggleAdjust;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: Row(
        children: [
          IconButton(
            key: const Key('week-previous'),
            tooltip: '上一周',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: TextButton(
              key: const Key('week-current'),
              onPressed: isCurrentWeek ? null : onCurrent,
              child: Text(isCurrentWeek ? '本周 · $label' : label),
            ),
          ),
          TextButton(
            key: const Key('week-adjust-dates'),
            onPressed: onToggleAdjust,
            child: Text(adjustingDates ? '完成' : '调整日期'),
          ),
          IconButton(
            key: const Key('week-next'),
            tooltip: '下一周',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _ArrangementHint extends StatelessWidget {
  const _ArrangementHint({
    this.compact = false,
    this.allCollapsed = false,
    this.onToggleAll,
  });

  final bool compact;
  final bool allCollapsed;
  final VoidCallback? onToggleAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            compact ? '分组按安排顺序排列' : '分组只表示安排顺序，所有任务都可以直接开始',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        if (compact && onToggleAll != null)
          TextButton.icon(
            key: const Key('arrangement-toggle-all'),
            onPressed: onToggleAll,
            icon: Icon(
              allCollapsed ? Icons.unfold_more : Icons.unfold_less,
              size: 18,
            ),
            label: Text(allCollapsed ? '全部展开' : '全部收起'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }
}

class _WeekdayPanel extends StatelessWidget {
  const _WeekdayPanel({
    required this.day,
    required this.title,
    required this.tasks,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onAddTask,
    required this.onToggleTask,
    required this.onOpenTask,
    required this.onMoveTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onSyncStage,
    required this.adjustingDates,
    required this.onReorder,
    required this.onMoveToDay,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final DateTime day;
  final String title;
  final List<Task> tasks;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final AddWeeklyTask? onAddTask;
  final ValueChanged<Task> onToggleTask;
  final ValueChanged<Task> onOpenTask;
  final MoveArrangementTask onMoveTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;
  final ValueChanged<Task>? onSyncStage;
  final bool adjustingDates;
  final ReorderCallback? onReorder;
  final MoveWeeklyTask? onMoveToDay;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final panel = Material(
      key: Key('week-day-${day.weekday}'),
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleCollapsed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 48,
                      child: Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tasks.isEmpty ? title : '$title · ${tasks.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed && tasks.isNotEmpty)
            Divider(height: 1, color: colors.outlineVariant),
          if (!collapsed && tasks.isNotEmpty && !adjustingDates)
            ReorderableListView.builder(
              key: Key('week-reorder-${day.toIso8601String()}'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: tasks.length,
              onReorderItem: onReorder ?? (_, _) {},
              itemBuilder: (_, index) => Padding(
                key: ValueKey('week-task-${tasks[index].id}'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _taskRow(index, draggable: onReorder != null),
              ),
            ),
          if (!collapsed && adjustingDates)
            for (var index = 0; index < tasks.length; index++)
              Padding(
                key: ValueKey('week-task-${tasks[index].id}'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: tasks[index].isCompleted
                    ? _taskRow(index)
                    : LongPressDraggable<Task>(
                        data: tasks[index],
                        onDragUpdate: onDragUpdate,
                        onDragEnd: (_) => onDragEnd(),
                        onDraggableCanceled: (_, _) => onDragEnd(),
                        onDragCompleted: onDragEnd,
                        feedback: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 250,
                            child: ListTile(title: Text(tasks[index].title)),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: .35,
                          child: _taskRow(index),
                        ),
                        child: _taskRow(index),
                      ),
              ),
          if (!collapsed) ...[
            if (tasks.isNotEmpty) const SizedBox(height: 8),
            Divider(height: 1, color: colors.outlineVariant),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: TextButton.icon(
                key: Key('week-add-${day.weekday}'),
                onPressed: onAddTask == null ? null : () => onAddTask!(day),
                icon: const Icon(Icons.add, size: 18),
                label: Text(title.startsWith('今天') ? '添加到今天' : '添加到$title'),
              ),
            ),
          ],
        ],
      ),
    );
    if (!adjustingDates || onMoveToDay == null) return panel;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) =>
          !details.data.isCompleted &&
          details.data.dueDate != null &&
          !(details.data.dueDate!.year == day.year &&
              details.data.dueDate!.month == day.month &&
              details.data.dueDate!.day == day.day),
      onAcceptWithDetails: (details) => onMoveToDay!(details.data, day),
      builder: (_, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: candidates.isEmpty
              ? null
              : Border.all(color: colors.primary, width: 2),
        ),
        child: panel,
      ),
    );
  }

  Widget _taskRow(int index, {bool draggable = false}) => _ArrangementTaskRow(
    task: tasks[index],
    index: index,
    currentMode: Task.normalizeMode(tasks[index].taskMode),
    compact: true,
    draggable: draggable,
    weekRow: true,
    onToggleTask: onToggleTask,
    onOpenTask: onOpenTask,
    onMoveTask: onMoveTask,
    onEditTask: onEditTask,
    onDeleteTask: onDeleteTask,
    onSyncStage: onSyncStage,
  );
}

class _ArrangementStagePanel extends StatelessWidget {
  const _ArrangementStagePanel({
    super.key,
    required this.mode,
    required this.title,
    required this.tasks,
    required this.compact,
    required this.fillHeight,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onToggleTask,
    required this.onOpenTask,
    required this.onMoveTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onSyncToday,
    required this.onAddTask,
    required this.onReorder,
  });

  final String mode;
  final String title;
  final List<Task> tasks;
  final bool compact;
  final bool fillHeight;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final ValueChanged<Task> onToggleTask;
  final ValueChanged<Task> onOpenTask;
  final MoveArrangementTask onMoveTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;
  final ValueChanged<Task>? onSyncToday;
  final AddArrangementTask onAddTask;
  final ReorderArrangementTasks onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final list = tasks.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text('暂无未完成任务', style: TextStyle(color: colors.outline)),
            ),
          )
        : ReorderableListView.builder(
            shrinkWrap: !fillHeight,
            physics: fillHeight
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            itemCount: tasks.length,
            onReorderItem: (oldIndex, newIndex) =>
                onReorder(mode, oldIndex, newIndex),
            itemBuilder: (_, index) => _ArrangementTaskRow(
              key: ValueKey('arrangement-task-${tasks[index].id}'),
              task: tasks[index],
              index: index,
              currentMode: mode,
              compact: compact,
              draggable: true,
              onToggleTask: onToggleTask,
              onOpenTask: onOpenTask,
              onMoveTask: onMoveTask,
              onEditTask: onEditTask,
              onDeleteTask: onDeleteTask,
              onSyncToday: onSyncToday,
            ),
          );
    final panel = Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          InkWell(
            onTap: compact ? onToggleCollapsed : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title · ${tasks.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!compact)
                      Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: colors.outline,
                      ),
                    if (compact)
                      Semantics(
                        button: true,
                        label: collapsed ? '展开$title' : '收起$title',
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Icon(
                              collapsed ? Icons.expand_more : Icons.expand_less,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            Divider(height: 1, color: colors.outlineVariant),
            if (fillHeight) Expanded(child: list) else list,
            Divider(height: 1, color: colors.outlineVariant),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton.icon(
                key: Key('arrangement-add-$mode'),
                onPressed: () => onAddTask(mode),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('同时任务'),
              ),
            ),
          ],
        ],
      ),
    );
    if (!compact) return panel;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: panel,
    );
  }
}

class _ArrangementTaskRow extends StatelessWidget {
  const _ArrangementTaskRow({
    super.key,
    required this.task,
    required this.index,
    required this.currentMode,
    required this.compact,
    required this.draggable,
    required this.onToggleTask,
    required this.onOpenTask,
    required this.onMoveTask,
    required this.onEditTask,
    required this.onDeleteTask,
    this.onSyncStage,
    this.onSyncToday,
    this.weekRow = false,
  });

  static const _editValue = 'edit';
  static const _deleteValue = 'delete';
  static const _syncStageValue = 'sync_stage';
  static const _syncTodayValue = 'sync_today';

  final Task task;
  final int index;
  final String currentMode;
  final bool compact;
  final bool draggable;
  final ValueChanged<Task> onToggleTask;
  final ValueChanged<Task> onOpenTask;
  final MoveArrangementTask onMoveTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;
  final ValueChanged<Task>? onSyncStage;
  final ValueChanged<Task>? onSyncToday;
  final bool weekRow;

  void _handleMenu(String value) {
    if (value == _editValue) {
      onEditTask(task);
    } else if (value == _deleteValue) {
      onDeleteTask(task);
    } else if (value == _syncStageValue) {
      onSyncStage?.call(task);
    } else if (value == _syncTodayValue) {
      onSyncToday?.call(task);
    } else {
      onMoveTask(task, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final card = Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpenTask(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: task.isCompleted,
                onChanged: (_) => onToggleTask(task),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.isCompleted ? colors.outline : null,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('arrangement-menu-${task.id}'),
                tooltip: '任务操作',
                icon: const Icon(Icons.more_vert),
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onSelected: _handleMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _editValue, child: Text('编辑')),
                  if (weekRow)
                    const PopupMenuItem(
                      value: _syncStageValue,
                      child: Text('同步阶段'),
                    ),
                  if (!weekRow) ...[
                    if (currentMode != Task.planNowMode)
                      const PopupMenuItem(
                        value: Task.planNowMode,
                        child: Text('移到现在'),
                      ),
                    if (currentMode != Task.planNextMode)
                      const PopupMenuItem(
                        value: Task.planNextMode,
                        child: Text('移到接下来'),
                      ),
                    if (currentMode != Task.planLaterMode)
                      const PopupMenuItem(
                        value: Task.planLaterMode,
                        child: Text('移到稍后'),
                      ),
                    if (currentMode != Task.normalMode)
                      const PopupMenuItem(
                        value: Task.normalMode,
                        child: Text('移回列表'),
                      ),
                    if (!task.isCompleted)
                      const PopupMenuItem(
                        value: _syncTodayValue,
                        child: Text('同步今日'),
                      ),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _deleteValue,
                    child: Text(
                      '删除',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              if (draggable && !compact)
                Listener(
                  onPointerDown: (_) => HapticFeedback.selectionClick(),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle, size: 20),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (draggable && compact) {
      return ReorderableDelayedDragStartListener(index: index, child: card);
    }
    return card;
  }
}

class FlowScreen extends StatefulWidget {
  const FlowScreen({super.key, required this.taskService});

  final TaskService taskService;

  @override
  State<FlowScreen> createState() => FlowScreenState();
}

class FlowScreenState extends State<FlowScreen> {
  List<Task> _flows = const [];
  final Map<int, List<SubTask>> _steps = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final flows = await widget.taskService.getFlowTasks();
    final steps = <int, List<SubTask>>{};
    for (final flow in flows) {
      steps[flow.id!] = (await widget.taskService.getRootSubTasks(
        flow.id!,
      )).where((step) => !step.isDeleted).toList();
    }
    if (!mounted) return;
    setState(() {
      _flows = flows;
      _steps
        ..clear()
        ..addAll(steps);
      _loading = false;
    });
  }

  Future<void> showAddDialog() async {
    final titleController = TextEditingController();
    final stepsController = TextEditingController();
    String? error;
    final result = await showDialog<({String title, List<String> steps})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('创建流程'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '流程名称',
                    hintText: '例如：完成课程论文',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: stepsController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '步骤',
                    hintText: '每行一个步骤\n准备资料\n撰写初稿\n检查修改\n提交论文',
                    helperText: '保存后按从上到下的顺序执行',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  setDialogState(() => error = '请输入流程名称');
                  return;
                }
                final steps = stepsController.text
                    .split(RegExp(r'\r?\n'))
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList();
                Navigator.pop(dialogContext, (title: title, steps: steps));
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    stepsController.dispose();
    if (result == null) return;

    final draft = Task(title: result.title, taskMode: Task.flowMode);
    final id = await widget.taskService.insertTask(draft);
    final saved = draft.copyWith(
      id: id,
      revision: draft.revision,
      updatedAt: draft.updatedAt,
    );
    for (final step in result.steps) {
      await widget.taskService.addFlowStep(saved, step);
    }
    await refresh();
  }

  Future<String?> _askForText({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final text = value.trim();
              if (text.isEmpty) {
                setDialogState(() => error = '内容不能为空');
              } else {
                Navigator.pop(dialogContext, text);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  setDialogState(() => error = '内容不能为空');
                  return;
                }
                Navigator.pop(dialogContext, text);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addStep(Task task) async {
    final title = await _askForText(title: '添加步骤', label: '步骤名称');
    if (title == null) return;
    await widget.taskService.addFlowStep(task, title);
    await refresh();
  }

  Future<void> _editStep(Task task, SubTask step) async {
    final title = await _askForText(
      title: '编辑步骤',
      label: '步骤名称',
      initialValue: step.title,
    );
    if (title == null) return;
    await widget.taskService.updateSubTask(step.copyWith(title: title));
    await refresh();
  }

  Future<void> _deleteStep(Task task, SubTask step) async {
    await widget.taskService.softDeleteSubTask(step.id!);
    await widget.taskService.checkTaskCompletion(task.id!);
    await refresh();
  }

  Future<void> _editFlow(Task task) async {
    final title = await _askForText(
      title: '编辑流程',
      label: '流程名称',
      initialValue: task.title,
    );
    if (title == null) return;
    await widget.taskService.updateTask(task.copyWith(title: title));
    await refresh();
  }

  Future<void> _toggleStep(Task task, SubTask step) async {
    final changed = await widget.taskService.toggleSubTaskForTask(task, step);
    if (!changed && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先完成当前步骤；退回时只能从最后完成的步骤开始')));
    }
    await refresh();
  }

  Future<void> _convertToList(Task task) async {
    await widget.taskService.setTaskMode(task, Task.normalMode);
    await refresh();
  }

  Future<void> _deleteFlow(Task task) async {
    await widget.taskService.softDeleteTask(task.id!);
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_flows.isEmpty) {
      return Center(
        key: const Key('flow-screen-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 68,
              color: Theme.of(context).colorScheme.primary.withAlpha(150),
            ),
            const SizedBox(height: 16),
            const Text('还没有流程'),
            const SizedBox(height: 6),
            Text(
              '把需要按步骤完成的事情放在这里',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('flow-add-button'),
              onPressed: showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('创建流程'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        key: const Key('flow-screen'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
        itemCount: _flows.length,
        itemBuilder: (_, index) {
          final task = _flows[index];
          return _FlowTaskCard(
            key: ValueKey('flow-task-${task.id}'),
            task: task,
            steps: _steps[task.id] ?? const [],
            onToggleStep: (step) => _toggleStep(task, step),
            onAddStep: () => _addStep(task),
            onEditStep: (step) => _editStep(task, step),
            onDeleteStep: (step) => _deleteStep(task, step),
            onEditFlow: () => _editFlow(task),
            onConvertToList: () => _convertToList(task),
            onDeleteFlow: () => _deleteFlow(task),
          );
        },
      ),
    );
  }
}

class _FlowTaskCard extends StatelessWidget {
  const _FlowTaskCard({
    super.key,
    required this.task,
    required this.steps,
    required this.onToggleStep,
    required this.onAddStep,
    required this.onEditStep,
    required this.onDeleteStep,
    required this.onEditFlow,
    required this.onConvertToList,
    required this.onDeleteFlow,
  });

  final Task task;
  final List<SubTask> steps;
  final ValueChanged<SubTask> onToggleStep;
  final VoidCallback onAddStep;
  final ValueChanged<SubTask> onEditStep;
  final ValueChanged<SubTask> onDeleteStep;
  final VoidCallback onEditFlow;
  final VoidCallback onConvertToList;
  final VoidCallback onDeleteFlow;

  @override
  Widget build(BuildContext context) {
    final done = steps.where((step) => step.isDone).length;
    final currentIndex = steps.indexWhere((step) => !step.isDone);
    final progress = steps.isEmpty ? 0.0 : done / steps.length;
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.account_tree_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps.isEmpty
                            ? '还没有步骤'
                            : currentIndex < 0
                            ? '$done/${steps.length} 已完成 · 流程完成'
                            : '$done/${steps.length} 已完成 · 当前第 ${currentIndex + 1} 步',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  iconSize: 22,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') onEditFlow();
                    if (value == 'list') onConvertToList();
                    if (value == 'delete') onDeleteFlow();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑流程名称')),
                    PopupMenuItem(value: 'list', child: Text('转为普通 Todo')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('删除流程')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
            ),
            const SizedBox(height: 18),
            if (steps.isEmpty)
              OutlinedButton.icon(
                onPressed: onAddStep,
                icon: const Icon(Icons.add),
                label: const Text('添加第一个步骤'),
              )
            else if (compact)
              _VerticalFlow(
                steps: steps,
                currentIndex: currentIndex,
                onToggleStep: onToggleStep,
                onEditStep: onEditStep,
                onDeleteStep: onDeleteStep,
              )
            else
              _HorizontalFlow(
                steps: steps,
                currentIndex: currentIndex,
                onToggleStep: onToggleStep,
                onEditStep: onEditStep,
                onDeleteStep: onDeleteStep,
              ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAddStep,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加步骤'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HorizontalFlow extends StatelessWidget {
  const _HorizontalFlow({
    required this.steps,
    required this.currentIndex,
    required this.onToggleStep,
    required this.onEditStep,
    required this.onDeleteStep,
  });

  final List<SubTask> steps;
  final int currentIndex;
  final ValueChanged<SubTask> onToggleStep;
  final ValueChanged<SubTask> onEditStep;
  final ValueChanged<SubTask> onDeleteStep;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('flow-layout-horizontal'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            _FlowStepNode(
              step: steps[index],
              index: index,
              currentIndex: currentIndex,
              onToggle: () => onToggleStep(steps[index]),
              onEdit: () => onEditStep(steps[index]),
              onDelete: () => onDeleteStep(steps[index]),
            ),
            if (index < steps.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _VerticalFlow extends StatelessWidget {
  const _VerticalFlow({
    required this.steps,
    required this.currentIndex,
    required this.onToggleStep,
    required this.onEditStep,
    required this.onDeleteStep,
  });

  final List<SubTask> steps;
  final int currentIndex;
  final ValueChanged<SubTask> onToggleStep;
  final ValueChanged<SubTask> onEditStep;
  final ValueChanged<SubTask> onDeleteStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('flow-layout-vertical'),
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          _FlowStepNode(
            step: steps[index],
            index: index,
            currentIndex: currentIndex,
            onToggle: () => onToggleStep(steps[index]),
            onEdit: () => onEditStep(steps[index]),
            onDelete: () => onDeleteStep(steps[index]),
            wide: true,
          ),
          if (index < steps.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Icon(
                Icons.arrow_downward_rounded,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
        ],
      ],
    );
  }
}

class _FlowStepNode extends StatelessWidget {
  const _FlowStepNode({
    required this.step,
    required this.index,
    required this.currentIndex,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.wide = false,
  });

  final SubTask step;
  final int index;
  final int currentIndex;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final isCurrent = index == currentIndex;
    final isLocked = !step.isDone && currentIndex >= 0 && index > currentIndex;
    final scheme = Theme.of(context).colorScheme;
    final color = step.isDone
        ? Colors.green
        : isCurrent
        ? scheme.primary
        : scheme.outline;
    final background = step.isDone
        ? Colors.green.withAlpha(18)
        : isCurrent
        ? scheme.primaryContainer.withAlpha(90)
        : scheme.surfaceContainerLow;

    return SizedBox(
      key: ValueKey('flow-step-${step.id}'),
      width: wide ? double.infinity : 180,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color, width: isCurrent ? 2 : 1),
        ),
        child: InkWell(
          onTap: isLocked ? null : onToggle,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withAlpha(step.isDone ? 220 : 35),
                  foregroundColor: step.isDone ? Colors.white : color,
                  child: step.isDone
                      ? const Icon(Icons.check, size: 18)
                      : isLocked
                      ? const Icon(Icons.lock_outline, size: 16)
                      : Text('${index + 1}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isLocked ? scheme.outline : null,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(height: 3),
                        Text(
                          '当前步骤',
                          style: TextStyle(fontSize: 11, color: scheme.primary),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert),
                  iconSize: 22,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑步骤')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('删除步骤')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
