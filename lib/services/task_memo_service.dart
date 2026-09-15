import '../models/memo.dart';
import '../models/sub_task.dart';
import '../models/task.dart';
import '../repositories/subtask_repository.dart';
import '../repositories/task_memo_repository.dart';
import '../repositories/task_repository.dart';
import 'memo_service.dart';

class TaskMemoService {
  TaskMemoService(
    this._taskRepository,
    this._linkRepository,
    this._subTaskRepository,
    this._memoService, {
    void Function()? onChanged,
  }) : _onChanged = onChanged;

  final TaskRepository _taskRepository;
  final TaskMemoRepository _linkRepository;
  final SubTaskRepository _subTaskRepository;
  final MemoService _memoService;
  final void Function()? _onChanged;

  /// 递归收集备忘录子树(前序 DFS,父先于子),跳过已删除节点及其整棵子树
  Future<List<Memo>> collectSubtree(Memo memo) async {
    final result = <Memo>[memo];
    final children = await _memoService.getChildren(memo.id!);
    for (final child in children) {
      if (child.isDeleted) continue;
      result.addAll(await collectSubtree(child));
    }
    return result;
  }

  /// 将 memo 的子孙备忘录按原层级转成 SubTask 树,挂在 taskId 下
  Future<void> _createSubTaskTree(
    Memo memo,
    int taskId,
    int? parentSubTaskId,
  ) async {
    final children = await _memoService.getChildren(memo.id!);
    var order = 0;
    for (final child in children) {
      if (child.isDeleted) continue;
      final titles = extractTaskTitles(child.content);
      final title = titles.isEmpty ? child.content.trim() : titles.first;
      final subTask = SubTask(
        title: title,
        taskId: taskId,
        parentId: parentSubTaskId,
        level: child.level - 1,
        sortOrder: order++,
      );
      final id = await _subTaskRepository.insert(subTask);
      await _createSubTaskTree(child, taskId, id);
    }
  }

  Future<Task> createTaskFromMemo(
    Memo memo, {
    DateTime? dueDate,
    int effortPoints = 2,
  }) async {
    final titles = extractTaskTitles(memo.content);
    final title = titles.isEmpty ? memo.content.trim() : titles.first;
    if (title.isEmpty) throw ArgumentError('备忘录内容不能为空');
    final task = Task(
      title: title,
      note: '来自备忘录',
      dueDate: dueDate,
      effortPoints: effortPoints,
    );
    final id = await _taskRepository.insert(task);
    await _linkRepository.link(id, memo.id!);
    await _createSubTaskTree(memo, id, null);
    _onChanged?.call();
    return task.copyWith(
      id: id,
      updatedAt: task.updatedAt,
      revision: task.revision,
    );
  }

  Future<List<Task>> createTasksFromMemo(
    Memo memo, {
    DateTime? dueDate,
    int effortPoints = 2,
  }) async {
    // 有子备忘录时整体转成 1 个 Todo + 子任务树,不按行拆分
    final subtree = await collectSubtree(memo);
    if (subtree.length > 1) {
      final task = await createTaskFromMemo(
        memo,
        dueDate: dueDate,
        effortPoints: effortPoints,
      );
      return [task];
    }
    final titles = extractTaskTitles(memo.content);
    final created = <Task>[];
    for (final title in titles) {
      final task = Task(
        title: title,
        note: '来自备忘录',
        dueDate: dueDate,
        effortPoints: effortPoints,
      );
      final id = await _taskRepository.insert(task);
      await _linkRepository.link(id, memo.id!);
      created.add(
        task.copyWith(
          id: id,
          updatedAt: task.updatedAt,
          revision: task.revision,
        ),
      );
    }
    if (created.isNotEmpty) _onChanged?.call();
    return created;
  }

  Future<void> linkTaskToMemo(int taskId, int memoId) async {
    final memo = await _memoService.getById(memoId);
    if (memo != null) {
      // 级联:父备忘录 + 全部子孙备忘录都关联到该 Task
      for (final m in await collectSubtree(memo)) {
        await _linkRepository.link(taskId, m.id!);
      }
    } else {
      await _linkRepository.link(taskId, memoId);
    }
    _onChanged?.call();
  }

  Future<void> unlinkTaskFromMemo(int taskId, int memoId) async {
    await _linkRepository.unlink(taskId, memoId);
    _onChanged?.call();
  }

  Future<List<Memo>> getMemosForTask(int taskId) =>
      _linkRepository.getMemosForTask(taskId);

  Future<List<Task>> getTasksForMemo(int memoId) =>
      _linkRepository.getTasksForMemo(memoId);

  /// 兼容普通行、项目符号、编号和 `- [ ]`，但不启用 Markdown 编辑器。
  static List<String> extractTaskTitles(String content) {
    final result = <String>[];
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^[-*]\s*\[[xX]\]\s*').hasMatch(line)) continue;
      line = line
          .replaceFirst(RegExp(r'^[-*]\s*\[\s\]\s*'), '')
          .replaceFirst(RegExp(r'^[-*+]\s+'), '')
          .replaceFirst(RegExp(r'^\d+[.)、]\s*'), '')
          .trim();
      if (line.isNotEmpty && !result.contains(line)) result.add(line);
    }
    return result;
  }
}
