import '../models/memo.dart';
import '../repositories/memo_repository.dart';
import '../repositories/memo_category_repository.dart';

/// 备忘录业务编排
class MemoService {
  final MemoRepository _repo;
  final MemoCategoryRepository _catRepo;

  final void Function()? _onChanged;

  MemoService(this._repo, this._catRepo, {void Function()? onChanged})
    : _onChanged = onChanged;

  Future<T> _withSync<T>(Future<T> operation) async {
    final result = await operation;
    _onChanged?.call();
    return result;
  }

  Future<Memo> create(String content, {String category = '紧急+重要+必须'}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError('备忘录内容不能为空');
    final memo = Memo(content: trimmed, category: category);
    final id = await _repo.insert(memo);
    _onChanged?.call();
    return memo.copyWith(id: id);
  }

  Future<Memo> createChild(
    String content,
    int parentId,
    int level, {
    String category = '紧急+重要+必须',
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError('子备忘录内容不能为空');
    final memo = Memo(content: trimmed, level: level, category: category);
    final id = await _repo.insertChild(memo, parentId);
    _onChanged?.call();
    return memo.copyWith(id: id);
  }

  Future<void> update(Memo memo) async {
    await _repo.update(memo);
    _onChanged?.call();
  }

  Future<void> softDelete(int id) => _withSync(_repo.softDelete(id));

  Future<void> restore(int id) => _withSync(_repo.restore(id));

  Future<void> permanentlyDelete(int id) =>
      _withSync(_repo.permanentlyDelete(id));

  Future<List<Memo>> getRoots() => _repo.getRoots();

  Future<List<Memo>> getDeleted() => _repo.getDeleted();

  Future<Memo?> getById(int id) => _repo.getById(id);

  Future<List<Memo>> getArchived() => _repo.getArchived();

  Future<void> setPinned(int id, bool pinned) async {
    await _repo.setPinned(id, pinned);
    _onChanged?.call();
  }

  Future<void> setArchived(int id, bool archived) async {
    await _repo.setArchived(id, archived);
    _onChanged?.call();
  }

  Future<List<Memo>> getChildren(int parentId) => _repo.getChildren(parentId);

  Future<List<int?>> promote(int id) => _withSync(_repo.promote(id));

  Future<List<int?>> demote(int id) => _withSync(_repo.demote(id));

  Future<void> moveUp(int id) => _withSync(_repo.moveUp(id));

  Future<void> moveDown(int id) => _withSync(_repo.moveDown(id));

  Future<void> updateSortOrder(int id, int order) =>
      _withSync(_repo.updateSortOrder(id, order));

  // ── Category ──

  Future<List<Map<String, dynamic>>> getCategories() => _catRepo.getAll();

  Future<int> addCategory(String name, String color) =>
      _withSync(_catRepo.add(name, color));

  Future<void> updateCategory(int id, String name, String color) =>
      _withSync(_catRepo.update(id, name, color));

  Future<void> deleteCategory(int id) => _withSync(_catRepo.delete(id));
}
