# 2026-07-08 软删除 + 右键菜单 + UI 调整

## 做了什么
1. 子任务/子备忘改为软删除（划线+移底+恢复）
2. 右键弹出操作菜单
3. 备忘录分类标签 UI 优化
4. 备忘录取代 Tab 排序

## 软删除

### 问题
之前子任务和子备忘直接硬删除，不符合主任务的"15天保留"逻辑。

### 实现
- SubTask 模型加 `deletedAt` 字段
- DB v13：`subtasks` 加 `deleted_at` 列
- `SubTaskRepository.softDelete`：标记 deleted_at + 移到同层 sort_order 末尾
- UI：已删除项显示**划线+灰色**，`⋮` 菜单显示"↩ 恢复"和"🗑 永久删除"
- MemoRepository 同步更新软删除逻辑
- 删除时子节点递归软删除

## 右键菜单

- `TaskDetailScreen._buildTree`：GestureDetector + onSecondaryTapUp → showMenu
- `MemoItem`：同理，右键弹出和 `⋮` 相同的菜单
- 提取 `_showContextMenu` 方法避免代码重复

## UI 调整

- 备忘录分类标签：从 SingleChildScrollView 水平滚动 → Wrap 自然换行
- 最终参数：h:10 / v:15，带细边框 `BorderSide(color.withAlpha(80))`
- Tab 顺序：备忘录在前，Todo List 在后
- 分类标签颜色区分

## 涉及文件
- `models/sub_task.dart` — 加 deletedAt
- `database/database.dart` — v13 迁移
- `repositories/subtask_repository.dart` — softDelete/restore/permanentlyDelete
- `repositories/memo_repository.dart` — 软删除移底
- `services/task_service.dart` — 加 softDeleteSubTask/restoreSubTask
- `screens/task_detail_screen.dart` — 软删除 UI + 右键菜单
- `screens/memo_screen.dart` — 分类标签 Wrap + h10v15
- `widgets/memo_item.dart` — 右键菜单
- `widgets/todo_item.dart` — 卡片子任务软删除 UI
- `main.dart` — Tab 顺序调整

## 用户能看懂的总结
- 子任务删除后不会消失，会像"已完成"一样划掉变灰，自动排到同层最底部。想恢复点"↩ 恢复"，彻底删点"🗑 永久删除"
- 右键点任何条目都能弹出操作菜单，不用去找 `⋮` 按钮
- 分类标签不再挤在一排横着滚，自然分行排列，标签比较大好点
