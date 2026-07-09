# 2026-07-08 备忘录分类系统

## 做了什么
给备忘录加了8个默认分类（紧急×重要×必须 四象限），支持分类过滤、创建时选分类、编辑时改分类。

## 为什么
备忘录功能要对齐 Todo List 的分类能力，方便用户按优先级整理笔记。

## 怎么做的

### 数据层
- Memo 模型加 `category` 字段（默认"紧急+重要+必须"）
- DB v14：`memos` 表加 `category` 列，新建 `memo_categories` 表
- `MemoCategoryRepository`：独立的分类 CRUD，复用 CategoryRepository 模式

### 业务层
- `MemoService` 注入 `MemoCategoryRepository`
- `create` / `createChild` 支持 `category` 参数
- 分类 CRUD 方法透传

### UI 层
- `MemoScreen`：
  - 顶部两排固定分类标签（第一排5个，第二排4个），选中高亮
  - 底部快速创建：自动使用当前选中分类
  - 编辑弹窗新增分类下拉框
- 主函数 DI 链：注入 `MemoCategoryRepository` → `MemoService`

## 用户能看懂的总结
备忘录现在有了8个默认分类，按紧急程度、重要性、必要性组合。点分类标签可以只看该分类的笔记，编辑时也能改分类。分类标签两排显示，第一排5个第二排4个，颜色不同。

## 相关文档
- [2026-07-08-phase6-and-refactor.md](2026-07-08-phase6-and-refactor.md) — Phase 6 + 重构
- [2026-07-08-memo-tree-and-align.md](2026-07-08-memo-tree-and-align.md) — 备忘5级嵌套
