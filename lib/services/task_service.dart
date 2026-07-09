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

  TaskService(this._taskRepo, this._subtaskRepo, this._categoryRepo);

  // ── Task ──

  Future<int> insertTask(Task task) => _taskRepo.insert(task);

  Future<int> updateTask(Task task) => _taskRepo.update(task);

  Future<void> softDeleteTask(int taskId) => _taskRepo.softDelete(taskId);

  Future<void> restoreTask(int taskId) => _taskRepo.restore(taskId);

  Future<void> permanentlyDeleteTask(int taskId) => _taskRepo.permanentlyDelete(taskId);

  Future<void> moveTaskUp(int taskId) => _taskRepo.moveUp(taskId);

  Future<void> moveTaskDown(int taskId) => _taskRepo.moveDown(taskId);

  Future<List<Task>> getActiveTasks() => _taskRepo.getActive();

  Future<List<Task>> getDeletedTasks() => _taskRepo.getDeleted();

  // ── SubTask ──

  Future<int> insertSubTask(SubTask st) => _subtaskRepo.insert(st);

  Future<int> updateSubTask(SubTask st) => _subtaskRepo.update(st);

  Future<void> softDeleteSubTask(int id) => _subtaskRepo.softDelete(id);

  Future<void> restoreSubTask(int id) => _subtaskRepo.restore(id);

  Future<void> permanentlyDeleteSubTask(int id) => _subtaskRepo.permanentlyDelete(id);

  Future<List<SubTask>> getRootSubTasks(int taskId) => _subtaskRepo.getRoots(taskId);

  Future<List<SubTask>> getChildSubTasks(int parentId) => _subtaskRepo.getChildren(parentId);

  Future<List<int?>> promoteSubTask(int id) => _subtaskRepo.promote(id);

  Future<List<int?>> demoteSubTask(int id) => _subtaskRepo.demote(id);

  Future<void> moveSubTaskUp(int id) => _subtaskRepo.moveUp(id);

  Future<void> moveSubTaskDown(int id) => _subtaskRepo.moveDown(id);

  Future<({int total, int done})> getSubTaskProgress(int taskId) =>
      _subtaskRepo.getProgress(taskId);

  /// 检查任务完成状态：所有子任务 done → 标记完成；否则取消完成
  Future<void> checkTaskCompletion(int taskId) async {
    final progress = await _subtaskRepo.getProgress(taskId);
    if (progress.total > 0 && progress.total == progress.done) {
      await _taskRepo.setCompletedAt(taskId, DateTime.now());
    } else {
      await _taskRepo.setCompletedAt(taskId, null);
    }
  }

  // ── Category ──

  Future<List<Map<String, dynamic>>> getCategories() => _categoryRepo.getAll();

  Future<int> addCategory(String name, String color) => _categoryRepo.add(name, color);

  Future<void> updateCategory(int id, String name, String color) =>
      _categoryRepo.update(id, name, color);

  Future<void> deleteCategory(int id) => _categoryRepo.delete(id);
}
