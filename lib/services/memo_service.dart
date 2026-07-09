import '../models/memo.dart';
import '../repositories/memo_repository.dart';
import '../repositories/memo_category_repository.dart';

/// 备忘录业务编排
class MemoService {
  final MemoRepository _repo;
  final MemoCategoryRepository _catRepo;

  MemoService(this._repo, this._catRepo);

  Future<Memo> create(String content, {String category = '紧急+重要+必须'}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError('备忘录内容不能为空');
    final memo = Memo(content: trimmed, category: category);
    final id = await _repo.insert(memo);
    return memo.copyWith(id: id);
  }

  Future<Memo> createChild(String content, int parentId, int level,
      {String category = '紧急+重要+必须'}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) throw ArgumentError('子备忘录内容不能为空');
    final memo = Memo(content: trimmed, level: level, category: category);
    final id = await _repo.insertChild(memo, parentId);
    return memo.copyWith(id: id);
  }

  Future<void> update(Memo memo) => _repo.update(memo);

  Future<void> softDelete(int id) => _repo.softDelete(id);

  Future<void> restore(int id) => _repo.restore(id);

  Future<void> permanentlyDelete(int id) => _repo.permanentlyDelete(id);

  Future<List<Memo>> getRoots() => _repo.getRoots();

  Future<List<Memo>> getDeleted() => _repo.getDeleted();

  Future<List<Memo>> getChildren(int parentId) => _repo.getChildren(parentId);

  Future<List<int?>> promote(int id) => _repo.promote(id);

  Future<List<int?>> demote(int id) => _repo.demote(id);

  Future<void> moveUp(int id) => _repo.moveUp(id);

  Future<void> moveDown(int id) => _repo.moveDown(id);

  // ── Category ──

  Future<List<Map<String, dynamic>>> getCategories() => _catRepo.getAll();

  Future<int> addCategory(String name, String color) => _catRepo.add(name, color);

  Future<void> updateCategory(int id, String name, String color) =>
      _catRepo.update(id, name, color);

  Future<void> deleteCategory(int id) => _catRepo.delete(id);
}
