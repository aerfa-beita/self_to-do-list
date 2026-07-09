import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/sub_task.dart';
import '../services/task_service.dart';
import '../services/notification_service.dart';
import '../widgets/todo_item.dart';
import '../widgets/add_todo_dialog.dart';
import 'task_detail_screen.dart';

class TodoScreen extends StatefulWidget {
  final TaskService taskService;
  final NotificationService notificationService;

  const TodoScreen({super.key, required this.taskService, required this.notificationService});

  @override
  State<TodoScreen> createState() => TodoScreenState();
}

class TodoScreenState extends State<TodoScreen> {
  List<Task> _activeUndone = [];
  List<Task> _activeDone = [];
  List<Task> _deleted = [];
  Map<int, ({int total, int done})> _progress = {};
  String _filter = '全部';
  String _searchQuery = '';
  List<Map<String, dynamic>> _categories = [];
  bool _showCompleted = false;
  bool _showDeleted = false;
  final Set<int> _cardExpanded = {};
  final Map<int, List<SubTask>> _cardSubTasks = {};
  final _quickInputController = TextEditingController();
  final _quickInputFocus = FocusNode();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  // 批量选择
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  List<String> get _categoryNames => ['全部', ..._categories.map((c) => c['name'] as String)];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _quickInputController.dispose();
    _quickInputFocus.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _quickCreate() async {
    final title = _quickInputController.text.trim();
    if (title.isEmpty) return;
    await widget.taskService.insertTask(Task(title: title));
    _quickInputController.clear();
    _quickInputFocus.requestFocus();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final active = await widget.taskService.getActiveTasks();
    final deleted = await widget.taskService.getDeletedTasks();
    final categories = await widget.taskService.getCategories();
    final progress = <int, ({int total, int done})>{};
    for (final t in [...active, ...deleted]) {
      progress[t.id!] = await widget.taskService.getSubTaskProgress(t.id!);
    }
    for (final t in active.where((t) => !t.isCompleted)) {
      _scheduleReminder(t);
    }
    if (!mounted) return;
    setState(() {
      _activeUndone = active.where((t) => !t.isCompleted).toList();
      _activeDone = active.where((t) => t.isCompleted).toList();
      _deleted = deleted;
      _categories = categories;
      _progress = progress;
    });
  }

  Future<void> _softDelete(Task task) async {
    await _cancelReminder(task);
    await widget.taskService.softDeleteTask(task.id!);
    _loadAll();
  }

  Future<void> _restore(Task task) async {
    await widget.taskService.restoreTask(task.id!);
    await _scheduleReminder(task);
    _loadAll();
  }

  Future<void> _permDelete(Task task) async {
    await _cancelReminder(task);
    await widget.taskService.permanentlyDeleteTask(task.id!);
    _loadAll();
  }

  Future<void> _moveTaskUp(Task task) async {
    await widget.taskService.moveTaskUp(task.id!);
    _loadAll();
  }

  Future<void> _moveTaskDown(Task task) async {
    await widget.taskService.moveTaskDown(task.id!);
    _loadAll();
  }

  void _toggleCardExpand(int taskId) async {
    if (_cardExpanded.contains(taskId)) {
      _cardExpanded.remove(taskId);
      if (mounted) setState(() {});
      return;
    }
    final roots = await widget.taskService.getRootSubTasks(taskId);
    if (!mounted) return;
    _cardExpanded.add(taskId);
    _cardSubTasks[taskId] = roots;
    if (mounted) setState(() {});
  }

  Future<void> _toggleCardSubTask(SubTask st) async {
    final updated = st.copyWith(isDone: !st.isDone);
    final list = _cardSubTasks[st.taskId];
    if (list != null) {
      final idx = list.indexWhere((s) => s.id == st.id);
      if (idx != -1) { list[idx] = updated; }
    }
    if (mounted) setState(() {});
    await widget.taskService.updateSubTask(updated);
    await widget.taskService.checkTaskCompletion(st.taskId);
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(st.taskId);
    _loadAll();
  }

  Future<void> _moveCardSubTaskUp(SubTask st) async {
    await widget.taskService.moveSubTaskUp(st.id!);
    await widget.taskService.checkTaskCompletion(st.taskId);
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(st.taskId);
    if (mounted) setState(() {});
    _loadAll();
  }

  Future<void> _moveCardSubTaskDown(SubTask st) async {
    await widget.taskService.moveSubTaskDown(st.id!);
    await widget.taskService.checkTaskCompletion(st.taskId);
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(st.taskId);
    if (mounted) setState(() {});
    _loadAll();
  }

  Future<void> _deleteCardSubTask(SubTask st) async {
    if (st.isDeleted) {
      await widget.taskService.restoreSubTask(st.id!);
    } else {
      await widget.taskService.softDeleteSubTask(st.id!);
    }
    await widget.taskService.checkTaskCompletion(st.taskId);
    if (!mounted) return;
    _cardSubTasks[st.taskId] = await widget.taskService.getRootSubTasks(st.taskId);
    if (mounted) setState(() {});
    _loadAll();
  }

  DateTime? _parseDate(String? s) => s != null && s.isNotEmpty ? DateTime.parse(s) : null;

  Future<void> _scheduleReminder(Task task) async {
    if (task.reminderTime != null && task.dueDate != null) {
      final remindAt = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day,
          task.reminderTime!.hour, task.reminderTime!.minute);
      if (remindAt.isAfter(DateTime.now())) {
        await widget.notificationService.scheduleReminder(
          id: task.id! + 10000,
          title: '📌 ${task.title}',
          body: '截止日期到了',
          scheduledTime: remindAt,
          repeatType: task.repeatType,
        );
      }
    }
  }

  Future<void> _cancelReminder(Task task) async {
    await widget.notificationService.cancelReminder(task.id! + 10000);
  }

  void focusSearch() => _searchFocus.requestFocus();

  Future<void> showAddDialog() async {
    final cats = _categoryNames.where((c) => c != '全部').toList();
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => AddTaskDialog(categories: cats.isEmpty ? ['默认'] : cats),
    );
    if (result != null) {
      final task = Task(
        title: result['title']!,
        note: result['note'] ?? '',
        category: result['category']!,
        dueDate: _parseDate(result['due_date']),
        reminderTime: _parseDate(result['reminder_time']),
        repeatType: result['repeat_type'],
      );
      final newId = await widget.taskService.insertTask(task);
      final savedTask = task.copyWith(id: newId);
      await _scheduleReminder(savedTask);
      _loadAll();
    }
  }

  Future<void> _showEditDialog(Task task) async {
    final cats = _categoryNames.where((c) => c != '全部').toList();
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => AddTaskDialog(
        initialTitle: task.title,
        initialNote: task.note,
        initialCategory: task.category,
        initialDueDate: task.dueDate,
        initialReminderTime: task.reminderTime,
        initialRepeatType: task.repeatType,
        categories: cats.isEmpty ? ['默认'] : cats,
      ),
    );
    if (result != null) {
      await _cancelReminder(task);
      final updated = task.copyWith(
        title: result['title']!,
        note: result['note'] ?? '',
        category: result['category']!,
        dueDate: _parseDate(result['due_date']),
        reminderTime: _parseDate(result['reminder_time']),
        clearDueDate: result['due_date'] == null,
        clearReminderTime: result['reminder_time'] == null,
        repeatType: result['repeat_type'],
        clearRepeatType: result['repeat_type'] == null,
      );
      await widget.taskService.updateTask(updated);
      await _scheduleReminder(updated);
      _loadAll();
    }
  }

  void _openDetail(Task task) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TaskDetailScreen(
        task: task,
        taskService: widget.taskService,
        notificationService: widget.notificationService,
      )),
    );
    _loadAll();
  }

  List<Task> _filterTasks(List<Task> tasks) {
    var result = tasks;
    if (_filter != '全部') result = result.where((t) => t.category == _filter).toList();
    if (_searchQuery.isNotEmpty) {
      result = result.where((t) =>
        t.title.contains(_searchQuery) || t.note.contains(_searchQuery)
      ).toList();
    }
    return result;
  }

  // ── 批量操作 ──

  void _toggleSelectMode() => setState(() { _selectMode = !_selectMode; _selectedIds.clear(); });

  void _toggleSelect(int id) => setState(() {
    if (_selectedIds.contains(id)) { _selectedIds.remove(id); } else { _selectedIds.add(id); }
  });

  Future<void> _batchComplete() async {
    for (final id in _selectedIds.toList()) {
      await widget.taskService.updateTask((_activeUndone.firstWhere((t) => t.id == id)).copyWith(completedAt: DateTime.now()));
    }
    _selectedIds.clear();
    _selectMode = false;
    _loadAll();
  }

  Future<void> _batchDelete() async {
    for (final id in _selectedIds.toList()) {
      await widget.taskService.softDeleteTask(id);
    }
    _selectedIds.clear();
    _selectMode = false;
    _loadAll();
  }

  Future<void> _showCategoryManager() async {
    final TextEditingController nameCtrl = TextEditingController();

    Future<void> refreshCats() async {
      final cats = await widget.taskService.getCategories();
      if (mounted) setState(() => _categories = cats);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('管理分类', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _categories.length,
                      itemBuilder: (_, i) {
                        final cat = _categories[i];
                        final name = cat['name'] as String;
                        final color = Color(int.parse((cat['color'] as String).replaceFirst('#', '0xFF')));
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: color, radius: 14),
                          title: Text(name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (name != '默认')
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () async {
                                    nameCtrl.text = name;
                                    final result = await showDialog<Map<String, String>>(
                                      context: ctx,
                                      builder: (_) => AlertDialog(
                                        title: const Text('编辑分类'),
                                        content: TextField(
                                          controller: nameCtrl,
                                          decoration: const InputDecoration(hintText: '分类名称', border: OutlineInputBorder()),
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                                          FilledButton(
                                            onPressed: () {
                                              final n = nameCtrl.text.trim();
                                              if (n.isEmpty) return;
                                              Navigator.pop(ctx, {'name': n});
                                            },
                                            child: const Text('保存'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (result != null) {
                                      await widget.taskService.updateCategory(cat['id'] as int, result['name']!, cat['color'] as String);
                                      if (_filter == name) _filter = result['name']!;
                                      await refreshCats();
                                      setSheetState(() {});
                                    }
                                  },
                                ),
                              if (name != '默认')
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed: () async {
                                    await widget.taskService.deleteCategory(cat['id'] as int);
                                    if (_filter == name) _filter = '全部';
                                    await refreshCats();
                                    setSheetState(() {});
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(hintText: '新分类名称', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          final hash = name.codeUnits.fold<int>(0, (s, c) => s + c) % 12;
                          const palette = ['#607D8B', '#2196F3', '#4CAF50', '#FF9800', '#F44336', '#9C27B0', '#009688', '#3F51B5', '#FFC107', '#00BCD4', '#E91E63', '#795548'];
                          await widget.taskService.addCategory(name, palette[hash]);
                          nameCtrl.clear();
                          await refreshCats();
                          setSheetState(() {});
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    _loadAll();
  }

  Widget _sectionHeader(String title, int count, bool expanded, VoidCallback toggle, {Color color = Colors.indigo}) {
    return InkWell(
      onTap: toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: color),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(fontSize: 12, color: color)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredUndone = _filterTasks(_activeUndone);
    final filteredDone = _filterTasks(_activeDone);
    final filteredDeleted = _filterTasks(_deleted);
    final totalSubtasks = [..._activeUndone, ..._activeDone, ..._deleted]
        .fold<int>(0, (s, t) => s + (_progress[t.id!]?.total ?? 0));
    final doneSubtasks = [..._activeUndone, ..._activeDone, ..._deleted]
        .fold<int>(0, (s, t) => s + (_progress[t.id!]?.done ?? 0));

    return Scaffold(
      body: Column(
        children: [
          // 分类过滤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _categoryNames.map((label) {
                final selected = _filter == label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label, style: TextStyle(fontSize: 13)),
                    selected: selected,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onSelected: (_) => setState(() => _filter = label),
                  ),
                );
              }).toList(),
            ),
          ),
          // 搜索
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: '搜索任务...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // 统计
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text('$doneSubtasks/$totalSubtasks 项完成', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const Spacer(),
              InkWell(
                onTap: _toggleSelectMode,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_selectMode ? Icons.check_box : Icons.check_box_outline_blank, size: 16),
                  const SizedBox(width: 4),
                  Text(_selectMode ? '取消' : '多选', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ]),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _showCategoryManager,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.label_outline, size: 16),
                  const SizedBox(width: 4),
                  Text('分类', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          // 主体
          Expanded(
            child: filteredUndone.isEmpty && filteredDone.isEmpty && filteredDeleted.isEmpty
                ? Center(child: Text('还没有任务，点右下角创建', style: TextStyle(color: Colors.grey.shade400)))
                : ListView(
                    children: [
                      ...filteredUndone.asMap().entries.map((e) {
                        final i = e.key;
                        final task = e.value;
                        final p = _progress[task.id!] ?? (total: 0, done: 0);
                        final len = filteredUndone.length;
                        return TaskItem(
                          task: task, doneCount: p.done, totalCount: p.total,
                          selectMode: _selectMode,
                          isSelected: _selectedIds.contains(task.id),
                          onSelectToggle: () => _toggleSelect(task.id!),
                          onTap: () => _openDetail(task),
                          onDelete: () => _softDelete(task),
                          onEdit: () => _showEditDialog(task),
                          onMoveUp: () => _moveTaskUp(task),
                          onMoveDown: () => _moveTaskDown(task),
                          canMoveUp: i > 0,
                          canMoveDown: i < len - 1,
                          isExpanded: _cardExpanded.contains(task.id),
                          onToggleExpand: () => _toggleCardExpand(task.id!),
                          subTasks: _cardSubTasks[task.id] ?? [],
                          onToggleSubTask: (st) => _toggleCardSubTask(st),
                          onDeleteSubTask: (st) => _deleteCardSubTask(st),
                          onMoveSubTaskUp: (st) => _moveCardSubTaskUp(st),
                          onMoveSubTaskDown: (st) => _moveCardSubTaskDown(st),
                        );
                      }),
                      if (filteredDone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _sectionHeader('已完成', filteredDone.length, _showCompleted,
                            () => setState(() => _showCompleted = !_showCompleted), color: Colors.green),
                        if (_showCompleted)
                          ...filteredDone.map((task) {
                            final p = _progress[task.id!] ?? (total: 0, done: 0);
                            return TaskItem(
                              task: task, doneCount: p.done, totalCount: p.total,
                              onTap: () => _openDetail(task),
                              onDelete: () => _softDelete(task),
                              onEdit: () => _showEditDialog(task),
                              isExpanded: _cardExpanded.contains(task.id),
                              onToggleExpand: () => _toggleCardExpand(task.id!),
                              subTasks: _cardSubTasks[task.id] ?? [],
                              onToggleSubTask: (st) => _toggleCardSubTask(st),
                              onDeleteSubTask: (st) => _deleteCardSubTask(st),
                              onMoveSubTaskUp: (st) => _moveCardSubTaskUp(st),
                              onMoveSubTaskDown: (st) => _moveCardSubTaskDown(st),
                            );
                          }),
                      ],
                      if (filteredDeleted.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _sectionHeader('最近删除', filteredDeleted.length, _showDeleted,
                            () => setState(() => _showDeleted = !_showDeleted), color: Colors.red),
                        if (_showDeleted)
                          ...filteredDeleted.map((task) {
                            final p = _progress[task.id!] ?? (total: 0, done: 0);
                            return TaskItem(
                              task: task, doneCount: p.done, totalCount: p.total,
                              onTap: () {},
                              onDelete: () {},
                              onEdit: () {},
                              onRestore: () => _restore(task),
                              onPermanentDelete: () => _permDelete(task),
                            );
                          }),
                      ],
                    ],
                  ),
          ),
          // ── 批量操作栏 ──
          if (_selectMode && _selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -1))],
              ),
              child: Row(children: [
                Text('已选 ${_selectedIds.length} 项', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _batchComplete,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('完成'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _batchDelete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ]),
            ),
          // ── 底部快速创建栏 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -1))
              ],
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _quickInputController,
                  focusNode: _quickInputFocus,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '输入标题，按 Enter 快速创建...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => _quickCreate(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _quickCreate, icon: const Icon(Icons.add)),
            ]),
          ),
        ],
      ),
    );
  }
}
