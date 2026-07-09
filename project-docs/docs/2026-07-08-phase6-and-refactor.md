# 2026-07-08 Phase 6 独立备忘录 + 全项目重构

## 做了什么
1. 新增独立备忘录分区（底部 Tab 切换 Todo List | 备忘录）
2. 备忘录支持 Enter 快速连续创建、删除
3. 全项目架构重构：单向依赖、高内聚低耦合

## 为什么重构
旧架构问题：
- `database_helper.dart` 477行塞了 3 张表的所有 CRUD + 迁移
- `home_screen.dart` 505行混合 UI + 业务逻辑 + 直接调 DB
- 两个 Screen 直接用 `DatabaseHelper()` 全局单例
- 无 Service/Repository 中间层

## 怎么做的

### 新架构
```
UI (screens/widgets) → Service → Repository → DatabaseProvider → SQLite
```
所有依赖通过构造函数注入，零全局单例。

### 文件变更

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `models/memo.dart` | Memo 数据模型 |
| 新建 | `database/database.dart` | DatabaseProvider：v9 迁移 + memos 表 |
| 新建 | `repositories/task_repository.dart` | tasks 表纯 SQL |
| 新建 | `repositories/subtask_repository.dart` | subtasks 表纯 SQL |
| 新建 | `repositories/category_repository.dart` | categories 表纯 SQL |
| 新建 | `repositories/memo_repository.dart` | memos 表纯 SQL |
| 新建 | `services/task_service.dart` | 任务业务编排 |
| 新建 | `services/memo_service.dart` | 备忘录业务编排 |
| 新建 | `screens/todo_screen.dart` | Todo 主页（重构自 home_screen） |
| 新建 | `screens/memo_screen.dart` | 备忘录页面 |
| 新建 | `widgets/memo_item.dart` | 备忘录卡片组件 |
| 修改 | `main.dart` | DI 链 + TabBar（MainScreen） |
| 修改 | `task_detail_screen.dart` | 注入 TaskService |
| 重命名 | `todo.dart` → `task.dart` | 模型文件名统一 |
| 删除 | `database_helper.dart` | 拆为 DatabaseProvider + 4 Repository |
| 删除 | `home_screen.dart` | TodoScreen 替代 |

### DI 链
```dart
final db = await DatabaseProvider().database;
final taskService = TaskService(TaskRepository(db), SubTaskRepository(db), CategoryRepository(db));
final memoService = MemoService(MemoRepository(db));
final notificationService = NotificationService();
await notificationService.init();
// → MainScreen(taskService, memoService, notificationService)
```

## 用户能看懂的总结

1. **备忘录分区**：App 底部有两个 Tab——"Todo List"和"备忘录"。切换到备忘录后，输入内容按 Enter 就创建一条便签，继续输入继续创建，适合快速记录。
2. **架构重构**：把以前一个大文件拆成了多层——数据模型、数据库操作、业务逻辑、UI 页面，每层只管自己的事。以后加功能或修 bug 只需要改对应的文件，不会牵一发动全身。

## 相关文档
- [2026-07-08-task-sort-and-notification.md](2026-07-08-task-sort-and-notification.md) — 上次的排序+通知改动
