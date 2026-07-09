# 2026-07-09 Windows 通知 + UI 统一 + 时间显示修复

## 做了什么
1. Windows 闹钟方案改为 app 内弹窗（零依赖）
2. 备忘录卡片边框统一到 Todo 卡片标准
3. 日期时间显示从"今天"改为"今天 00:36"含具体分钟
4. 子任务弹窗加时间选择器

## 为什么
- `local_notifier` 需要开发者模式，改用纯 Flutter ValueNotifier+AlertDialog
- 各类条目边框不统一，备忘录比 Todo 窄
- 时间只显示"今天"看不到具体几点，闹钟设了看不出

## 怎么做的
- `notification_service.dart`：Windows Timer 到点后设 `pendingNotification.value`，MainScreen 监听弹 AlertDialog
- `memo_item.dart`：加 Card(margin:16,6)+padding(16,14,10,14)，字号 14→16
- `task_detail_screen.dart`：子任务 contentPadding 8→12，visualDensity compact→standard
- `utils/date_utils.dart`：加 `fmtDateTime(date, time)` 输出"今天 14:30"
- `_addChild`/`_editSubTask`：加 `showTimePicker` 时间选择器
- 移除 `local_notifier` 依赖，清理由 `pubspec.yaml`

## 涉及文件
- `lib/services/notification_service.dart`
- `lib/main.dart`
- `lib/utils/date_utils.dart`
- `lib/widgets/memo_item.dart`
- `lib/widgets/todo_item.dart`
- `lib/screens/task_detail_screen.dart`
- `pubspec.yaml`

## 用户能看懂的总结
- 闹钟到点 app 内弹提醒窗（Windows 上 zer 依赖，不需要开发者模式）
- 所有卡片边框统一，备忘录和任务一样大
- 时间不再只写"今天"，显示"今天 14:30"
- 子任务也能选具体时间了

## 相关文档
- [2026-07-08-soft-delete-and-ui.md](2026-07-08-soft-delete-and-ui.md)
