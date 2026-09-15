import '../models/task.dart';
import '../models/sub_task.dart';
import '../repositories/task_repository.dart';
import '../repositories/subtask_repository.dart';
import '../repositories/category_repository.dart';

/// 任务业务编排——协调 CRUD、完成检测、排序
class TaskService {
  final TaskRepository _taskRepo;
  final SubTaskRepository _subtaskRepo;
  final CategoryRepository _categoryRepo;

  final void Function()? _onChanged;

  TaskService(
    this._taskRepo,
    this._subtaskRepo,
    this._categoryRepo, {
    void Function()? onChanged,
  }) : _onChanged = onChanged;

  Future<T> _withSync<T>(Future<T> operation) async {
    final result = await operation;
    _onChanged?.call();
    return result;
  }

  // ── Task ──

  Future<int> insertTask(Task task) async {
    final id = await _taskRepo.insert(task);
    _onChanged?.call();
    return id;
  }

  Future<int> updateTask(Task task) async {
    final count = await _taskRepo.update(task);
    _onChanged?.call();
    return count;
  }

  Future<void> softDeleteTask(
    int taskId, {
    String source = Task.actionScopeInbox,
  }) async {
    await _taskRepo.softDelete(taskId, source: source);
    _onChanged?.call();
  }

  Future<void> softDeleteTasks(
    Iterable<int> taskIds, {
    String source = Task.actionScopeInbox,
  }) async {
    await _taskRepo.softDeleteMany(taskIds, source: source);
    _onChanged?.call();
  }

  Future<void> restoreTask(int taskId) async {
    await _taskRepo.restore(taskId);
    _onChanged?.call();
  }

  Future<void> setTaskCompleted(
    Task task, {
    required bool completed,
    required String source,
  }) async {
    await _taskRepo.setCompletedAt(
      task.id!,
      completed ? DateTime.now() : null,
      source: source,
    );
    _onChanged?.call();
  }

  Future<void> permanentlyDeleteTask(int taskId) async {
    await _taskRepo.permanentlyDelete(taskId);
    _onChanged?.call();
  }

  Future<void> moveTaskUp(int taskId) => _withSync(_taskRepo.moveUp(taskId));

  Future<void> moveTaskDown(int taskId) =>
      _withSync(_taskRepo.moveDown(taskId));

  Future<void> updateTaskSortOrder(int taskId, int order) =>
      _withSync(_taskRepo.updateSortOrder(taskId, order));

  Future<void> reorderTaskSubset(List<int> orderedIds) =>
      _withSync(_taskRepo.reorderActiveSubset(orderedIds));

  Future<void> reorderWeekDay(DateTime day, List<int> orderedIds) =>
      _withSync(_taskRepo.reorderWeekDay(day, orderedIds));

  Future<void> moveToWeekDay(Task task, DateTime day) =>
      _withSync(_taskRepo.moveToWeekDay(task, day));

  Future<List<Task>> getActiveTasks() => _taskRepo.getActive();

  Future<List<Task>> getFlowTasks() => _taskRepo.getFlows();

  Future<List<Task>> getDeletedTasks() => _taskRepo.getDeleted();

  Future<void> setTaskMode(Task task, String mode) async {
    final normalized = Task.normalizeMode(mode);
    final nextOrder = await _taskRepo.getNextSortOrderForMode(normalized);
    await _taskRepo.update(
      task.copyWith(taskMode: normalized, sortOrder: nextOrder),
    );
    _onChanged?.call();
  }

  Future<void> reorderTasks(List<Task> tasks) async {
    await reorderTaskSubset(
      tasks.map((task) => task.id).whereType<int>().toList(growable: false),
    );
  }

  Future<int> getTodayEffort() => _taskRepo.getTodayEffort();

  Future<int> getDailyEffortLimit() => _taskRepo.getDailyEffortLimit();

  Future<void> setDailyEffortLimit(int value) =>
      _taskRepo.setDailyEffortLimit(value);

  Future<({double x, double y})?> getCompanionPosition() =>
      _taskRepo.getCompanionPosition();

  Future<void> setCompanionPosition(double x, double y) =>
      _taskRepo.setCompanionPosition(x, y);

  Future<Set<String>> getArrangementCollapsedModes() =>
      _taskRepo.getArrangementCollapsedModes();

  Future<void> setArrangementCollapsedModes(Set<String> modes) =>
      _taskRepo.setArrangementCollapsedModes(modes);

  // ── SubTask ──

  Future<int> insertSubTask(SubTask st) => _withSync(_subtaskRepo.insert(st));

  Future<int> addFlowStep(Task task, String title) async {
    final roots = await _subtaskRepo.getRoots(task.id!);
    final activeRoots = roots.where((item) => !item.isDeleted).toList();
    final nextOrder =
        activeRoots.fold<int>(
          -1,
          (current, item) =>
              item.sortOrder > current ? item.sortOrder : current,
        ) +
        1;
    final id = await _subtaskRepo.insert(
      SubTask(
        taskId: task.id!,
        title: title.trim(),
        level: 0,
        sortOrder: nextOrder,
      ),
    );
    await checkTaskCompletion(task.id!);
    _onChanged?.call();
    return id;
  }

  Future<int> updateSubTask(SubTask st) => _withSync(_subtaskRepo.update(st));

  Future<void> softDeleteSubTask(int id) =>
      _withSync(_subtaskRepo.softDelete(id));

  Future<void> restoreSubTask(int id) => _withSync(_subtaskRepo.restore(id));

  Future<void> permanentlyDeleteSubTask(int id) =>
      _withSync(_subtaskRepo.permanentlyDelete(id));

  Future<List<SubTask>> getRootSubTasks(int taskId) =>
      _subtaskRepo.getRoots(taskId);

  Future<List<SubTask>> getChildSubTasks(int parentId) =>
      _subtaskRepo.getChildren(parentId);

  Future<List<int?>> promoteSubTask(int id) =>
      _withSync(_subtaskRepo.promote(id));

  Future<List<int?>> demoteSubTask(int id) =>
      _withSync(_subtaskRepo.demote(id));

  Future<void> moveSubTaskUp(int id) => _withSync(_subtaskRepo.moveUp(id));

  Future<void> moveSubTaskDown(int id) => _withSync(_subtaskRepo.moveDown(id));

  Future<void> updateSubTaskSortOrder(int id, int order) =>
      _withSync(_subtaskRepo.updateSortOrder(id, order));

  Future<({int total, int done})> getSubTaskProgress(int taskId) =>
      _subtaskRepo.getProgress(taskId);

  Future<bool> toggleSubTaskForTask(
    Task task,
    SubTask subTask, {
    String source = Task.actionScopeInbox,
  }) async {
    await _subtaskRepo.update(subTask.copyWith(isDone: !subTask.isDone));
    await checkTaskCompletion(task.id!, source: source);
    _onChanged?.call();
    return true;
  }

  Future<void> reopenFlowTask(Task task) async {
    final roots = (await _subtaskRepo.getRoots(
      task.id!,
    )).where((item) => !item.isDeleted).toList();
    final lastDone = roots.lastIndexWhere((item) => item.isDone);
    if (lastDone >= 0) {
      final step = roots[lastDone];
      await _subtaskRepo.update(step.copyWith(isDone: false));
    }
    await _taskRepo.setCompletedAt(task.id!, null);
    _onChanged?.call();
  }

  /// 检查任务完成状态：所有子任务 done → 标记完成；否则取消完成
  Future<void> checkTaskCompletion(
    int taskId, {
    String source = Task.actionScopeInbox,
  }) async {
    final progress = await _subtaskRepo.getProgress(taskId);
    if (progress.total > 0 && progress.total == progress.done) {
      await _taskRepo.setCompletedAt(
        taskId,
        DateTime.now(),
        source: source,
      );
    } else {
      await _taskRepo.setCompletedAt(taskId, null);
    }
  }

  // ── Category ──

  Future<List<Map<String, dynamic>>> getCategories() => _categoryRepo.getAll();

  Future<int> addCategory(String name, String color) =>
      _withSync(_categoryRepo.add(name, color));

  Future<void> updateCategory(int id, String name, String color) =>
      _withSync(_categoryRepo.update(id, name, color));

  Future<void> deleteCategory(int id) => _withSync(_categoryRepo.delete(id));
}
