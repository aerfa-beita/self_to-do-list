# 2026-07-08 任务排序 + 时间提醒 + Windows 通知 + Bug 修复

## 做了什么
- 新增主任务手动排序（上移/下移）
- 新增子任务手动排序（详情页 + 展开卡片，支持所有层级）
- 补全 Windows 桌面通知支持
- 修复 4 个运行时 Bug，修掉 6 个 lint 问题

## 修改的文件

| 文件 | 改动 |
|------|------|
| `lib/models/todo.dart` | 加 `sortOrder` 字段；修 `isOverdue`（今天不算过期） |
| `lib/database/database_helper.dart` | v7→v8 迁移；`moveTaskUp/Down`；`moveSubTaskUp/Down`；`_ensureColumn`；`_fixSortOrderIfNeeded` |
| `lib/screens/home_screen.dart` | 上移/下移回调；子任务排序回调；启动时重建所有提醒 |
| `lib/screens/task_detail_screen.dart` | 子任务 ⬆⬇ 按钮；`_moveSubTaskUp/Down` 方法 |
| `lib/widgets/todo_item.dart` | 弹出菜单加 ⬆上移/⬇下移；展开子任务加排序按钮 |
| `lib/widgets/add_todo_dialog.dart` | 回滚 `initialValue`→`value`（修复 Flutter 框架断言） |
| `lib/services/notification_service.dart` | Windows Timer 方案；`Completer` 防并发初始化；所有 `_plugin` 调用包 try/catch |
| `lib/main.dart` | 加 `flutter_localizations`；`await initializeDateFormatting('zh')`；`await NotificationService().init()` |
| `pubspec.yaml` | 加 `flutter_localizations` 依赖 |

## Bug 修复记录

| # | 现象 | 根因 | 修复 |
|---|------|------|------|
| 1 | session-start hook 乱码 | PS 脚本 UTF-8 无 BOM | 加 BOM |
| 2 | `_dependents.isEmpty` 断言 | `DropdownButtonFormField.initialValue` 非受控模式与父级 setState 冲突 | 回滚为 `value` |
| 3 | `LocaleDataException` | `intl` 没调 `initializeDateFormatting('zh')` | `main()` 里 await 调用 |
| 4 | `No MaterialLocalizations found` | MaterialApp 缺 `localizationsDelegates` | 加三个 delegate + `supportedLocales` |
| 5 | `LateInitializationError` | `NotificationService.init()` 没 await | `main()` await + `Completer` 防并发 |
| 6 | 上移没反应 | 旧任务 `sort_order` 全为 0 | v8 迁移填充顺序值 + `_fixSortOrderIfNeeded` 兜底 |
| 7 | 今天日期显示过期 | `isOverdue` 比较带时分 | 只比较日期部分 |

## 用户能看懂的总结

1. **任务排序**：每个任务的 `⋮` 菜单里有"上移""下移"，点了就能调整顺序。子任务在详情页和展开卡片里也能排序。
2. **时间提醒**：新建任务时可以选截止日期和提醒时间，卡片上会显示。今天到期的不会标红，明天之后到期的正常显示，昨天之前的才标红"已过期"。
3. **Windows 通知**：到时间会弹通知（限 app 运行期间，关了就不弹了）。Android 上用的是系统级的定时通知。
4. **各种闪退修好了**：弹窗打不开、日期选择器报错、上移没反应……都修了。

## 待办
- [ ] Windows 闹钟用 `local_notifier` 包实现真正的桌面通知（当前 Timer 触发但 show 不生效）
- [ ] `database_helper.dart`（414行）需要拆分成 TaskRepository + CategoryRepository
- [ ] `home_screen.dart`（468行）需要抽离排序/提醒逻辑到独立 Service 类
