# Android 全屏提醒与 Stride 更名

> 日期：2026-09-17  
> 版本：1.3.0+6 · DB v23

## 已完成内容

- Android 根任务按设定时间使用全屏提醒；界面支持完成任务、稍后 10 分钟和打开任务详情。
- 应用设置新增“提醒设置”。任务到点提醒保持开启；“今日任务巡检”默认关闭，开启后可选每 30 分钟、1 小时或 2 小时提醒，并可配置活跃时段，默认 08:00–22:00。
- 今日巡检只读取设备本地当天的未完成任务。巡检时间与具体任务时间相差不足 2 分钟时跳过巡检，让具体任务提醒优先。
- Android 和 Windows 产品名统一为 `Stride`。Android 包名、数据库路径与同步身份不变；Windows 保留 Flutter 内部目标 `todo_list`，通过 CMake `OUTPUT_NAME` 生成 `Stride.exe`。

## 当前架构

- `ReminderSettingsService` 把巡检开关、间隔和起止时间写入现有 `settings` 表，因此不升级数据库版本，也不进入云同步。
- `ReminderCoordinator` 监听任务与关联数据变化，并在启动、任务变化和同步完成后重排 Android 提醒。巡检一次预排未来 8 天，避免一次创建过多系统闹钟。
- `NotificationService` 负责全屏通知通道、payload、冷启动/点击分发、全屏特殊权限、稍后提醒和旧计划清理。备忘录与子任务继续使用普通通知。
- `FullScreenReminderScreen` 根据 payload 展示“任务到点”或“今日巡检”；打开今日安排会切回安排 > 本周。
- `MainActivity` 通过 `stride/full_screen_intent` 返回 Android 14+ 的全屏特殊权限状态。清单声明 `USE_FULL_SCREEN_INTENT`，主 Activity 支持锁屏上方显示和点亮屏幕。

## 视觉与交互

- 全屏提醒使用深墨蓝背景、暖白内容卡和低饱和薰衣草主按钮；无渐变、无玻璃效果，主要操作始终位于单手可触达区域。
- 任务提醒突出单一任务和完成动作；今日巡检最多展示 4 项，并引导进入本周处理。
- 设置页使用亮色 Material 3 卡片，明确区分系统通知权限、全屏特殊权限与巡检业务开关。
- 方向稿位于 `docs/assets/全屏提醒方案-*.png`；实际组件基准位于 `test/goldens/full_screen_*_mobile.png` 与 `reminder_settings_mobile.png`。

## 验证结果

- `dart analyze lib test`：无新增错误；保留项目原有 17 项提示（2 条 warning、15 条 info）。
- `flutter test --no-pub --concurrency=1`：加入稍后提醒持久化与铃声回归后 88/88 通过。
- Impeccable 静态设计规则：新增两个界面文件无命中项。
- Windows Release：通过，最终主程序为 `build/windows/x64/runner/Release/Stride.exe`，旧 `todo_list.exe` 不存在。
- Android Release：20:58 按小花先生明确授权单次重试，Gradle 在 855ms 内、Kotlin 编译前再次报 `java.io.IOException: Unable to establish loopback connection`。现有 19:49 APK 未被覆盖，且早于 20:17 的全屏提醒代码，不能作为本批验收包。

## 后续维护方式

- 调整巡检频率或默认时段时，同时更新 `ReminderSettings`、设置页选项和时间生成测试。
- 新增会触发全屏提醒的任务类型时，必须使用 `ReminderLaunch` payload，并确保完成或删除后由协调器取消旧计划。
- 若扩大 8 天预排窗口，需要同时评估系统待处理通知数量；更稳妥的长期方案是增加每日系统级重排任务。
- Android 14+ 的全屏权限由系统单独管理。未授权或设备处于解锁状态时，系统可能降级为高优先级横幅，这是系统行为。

## 潜在问题与下一步

1. 在普通 PowerShell 执行 `flutter build apk --release --no-pub`，确认新 APK 的生成时间晚于本次代码，并检查 `Stride` 名称、`USE_FULL_SCREEN_INTENT` 权限和正式签名。
2. 真机覆盖锁屏、亮屏、全屏权限拒绝三种状态；验证任务到点、巡检、时间重合、完成、稍后 10 分钟和打开今日安排。
3. 当前巡检预排 8 天。长期不打开应用时，第 9 天起不会自动新增巡检；后续可使用 Android WorkManager 做每日续排。
4. Android 桌面小部件直接修改数据库后不会立即进入 Flutter 协调器；下次打开应用会清理过期提醒。后续可让原生小部件操作同步触发重排。

## 可复用取舍

- 展示名、可执行文件名与内部构建目标应分开管理；Flutter 生成文件依赖内部目标名时，不应直接改 `BINARY_NAME`。
- 全屏提醒设计必须同时处理系统权限、锁屏状态和普通横幅降级，不能只完成应用内页面。
- 高频巡检不应复制任务；提醒触发时重新读取当天任务，才能避免展示已完成或已删除数据。
