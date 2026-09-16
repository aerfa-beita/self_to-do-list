# to-do_list — 项目结构

> 最后更新：2026-09-16

---

## 目录树

```
MY_Project/to-do_list/
├── README.md                         # GitHub 首页 🆕
├── CLAUDE.md                         # 核心交接文档
├── DESIGN.md                         # 当前项目视觉与交互事实
├── pubspec.yaml
├── .gitignore
├── assets/
│   ├── config/                       # Supabase 示例 + 本地忽略配置
│   ├── fonts/msyh.ttc
│   ├── mascot/
│   │   ├── todolist-mascot.webp      # 透明 3D 小精灵运行资源
│   │   ├── companion_dialogues.json  # 本地随机对话语料
│   │   └── 2_5d/                     # 三方向 45 拆件 + rig/action 配置
│   └── scripts/show_toast.ps1        # Windows toast 通知脚本 🆕
├── docs/                             # 按日期记录功能、架构、验证与交接
│   └── assets/
│       ├── chibi-companion-model-sheet.png # Q版人物建模设定稿
│       ├── 安排与桌面小部件方案.svg/.png # 已确认的应用与小部件设计图
│       └── mascot_2_5d/              # 最终组装/编号/动作验收图
├── project-docs/                     # 索引/结构/统计 🆕
├── lib/
│   ├── main.dart                     # 入口 + DI + Todo/备忘录自适应导航
│   ├── database/database.dart        # DB v22 + 升级前备份 + 稳定Windows路径/迁移 + 同步队列
│   ├── models/  (3个: task/sub_task/memo)  # 同步元数据/状态来源/心力/置顶归档
│   ├── repositories/  (6个)
│   │   └── task_memo_repository.dart # Todo/备忘录关联
│   ├── services/
│   │   ├── android_widget_service.dart # Flutter → Android 小部件刷新桥
│   │   ├── task_service.dart          # CRUD、列表/阶段/本周独立排序、安排折叠设置
│   │   ├── memo_service.dart
│   │   ├── task_memo_service.dart    # 转Todo/按行生成/关联
│   │   ├── backup_file_service.dart  # Windows/Android JSON文件读写
│   │   ├── companion_dialogue_service.dart # 小精灵本地语料/冷却/去重
│   │   ├── companion_rig_service.dart # 2.5D rig 解析/缓存/锚点
│   │   └── notification_service.dart # 通知队列 + schtasks + repeat 🆕
│   ├── sync/
│   │   ├── sync_config.dart
│   │   ├── sync_gateway.dart
│   │   ├── supabase_sync_gateway.dart # Auth + REST + Realtime
│   │   ├── sync_engine.dart           # outbox / pull / conflict
│   │   ├── sync_coordinator.dart      # 生命周期/防抖/周期
│   │   └── sync_status.dart
│   ├── screens/
│   │   ├── todo_screen.dart          # 来源状态视图 + 历史事件倒序 + 页面记忆与批量操作
│   │   ├── flow_screen.dart          # 阶段/固定七天本周 + 长按排序 + 跨日/同步菜单
│   │   ├── task_detail_screen.dart   # 子任务主详情 + 顶部编辑 + 闹钟/重复选择器
│   │   └── memo_screen.dart          # 当前分类标题 + 弹窗创建 + 批量选择 + 搜索
│   ├── widgets/
│   │   ├── deleted_task_card.dart    # 最近删除专用响应式卡片 + 恢复/永久删除入口
│   │   ├── memo_detail_panel.dart    # 自适应备忘录详情/自动保存
│   │   ├── workload_companion.dart   # 五状态/48dp边缘探头/随机互动/双手搬任务
│   │   ├── rigged_companion.dart     # 分层组装/步态/抓握/锚点任务卡
│   │   ├── schedule_prompt_dialog.dart # Todo/备忘录创建后的时间向导
│   │   ├── todo_item.dart            # 选择/左滑操作/右键 + 最近删除日期 + 统一三点
│   │   ├── memo_item.dart            # +选择模式 + 分类 chip 🆕
│   │   ├── add_todo_dialog.dart      # +重复选择器 + Enter提交 🆕
│   │   └── date_time_picker.dart     # +时间记忆 🆕
│   └── utils/
│       ├── date_utils.dart
│       └── sync_id.dart
├── supabase/schema.sql               # 云表/RLS/Realtime
├── test/
│   ├── core_features_test.dart       # DB v22/升级前备份/来源迁移/JSON合并/关联/解析
│   ├── flow_screen_test.dart          # 安排模式三列/共用已完成捷径/行菜单/空态
│   ├── todo_arrangement_test.dart     # 来源状态隔离/历史事件排序/本周历史/菜单与恢复
│   ├── deleted_task_card_test.dart    # 最近删除 320/360/412dp 与危险菜单边界
│   ├── sync_engine_test.dart         # 多批次上传/关系修复/旧云任务来源推断
│   ├── sync_gateway_encoding_test.dart # 中文 payload 推送 utf8 编码回归（本地 HTTP）🆕
│   ├── sync_config_test.dart         # 本地公共配置回退
│   ├── database_location_test.dart   # Windows旧库复制到稳定路径
│   ├── mobile_layout_test.dart       # 手机输入栏/工具栏/筛选面板/右侧探头；runAsync隔离原生SQLite
│   ├── arrangement_collapse_sort_test.dart # 固定七天、历史完成、独立排序、收起和窄屏边界
│   ├── stage_week_visual_test.dart   # 390×844 阶段/本周真实组件视觉回归
│   ├── goldens/                      # 阶段/本周手机端视觉基准 PNG
│   ├── workload_companion_test.dart  # 五状态/探头/本地对话/跨屏吞任务
│   ├── companion_rig_test.dart       # 三方向/15部件/独立方向资源
│   └── schedule_prompt_dialog_test.dart # 时间向导今天/跳过流程
├── windows/                          # Windows runner (C++)
└── android/                          # Android (Kotlin)
    └── app/src/main/
        ├── kotlin/com/xiaohua/todo_list/
        │   ├── TaskWidgetProvider.kt / TaskWidgetService.kt
        │   ├── WidgetTaskStore.kt / WidgetActionReceiver.kt
        │   └── WidgetQuickTaskActivity.kt / WidgetContract.kt # Intent kind 贯穿小部件操作
        └── res/                      # 小部件布局、兼容勾选图标、颜色与 provider 配置
```

## DB 版本历史

v14 → v15 (subtasks.deleted_at) → v16 (repeat_type) → v17 (settings 表)
→ v18 (sync 元数据、effort、pin/archive、task_memo_links、outbox/conflicts)
→ v19 (tasks.companion_stashed_at，精灵窝暂存状态)
→ v20 (tasks.task_mode，Todo 列表/安排互转与三段分组)
→ v21 (tasks.week_sort_order，本周同日排序独立于列表/阶段排序)
→ v22 (tasks.completed_scope / deleted_scope，按操作来源显示归档与恢复)

打开现有 v20 文件库前会创建同目录 `.pre-v21` 备份；打开 v21 文件库前创建 `.pre-v22` 备份。v22 旧任务按阶段优先、其次日期、最后收件箱推断状态来源。

`settings` 保存 Android 页面位置与安排折叠状态；这些设备本地偏好不进入云同步。

本周继续按 `due_date` 派生；阶段继续按 `task_mode` 派生。移动只更新同一任务对应属性，不复制任务；完成和删除全局生效，由来源字段决定归档入口。

Android 小部件直接访问应用沙盒内 `todo_list.db`；原生写入同步更新 `revision` 和 stage/week 来源，由既有触发器进入 outbox，无第二份任务库；本周查询优先使用 `week_sort_order`，旧库回退 `sort_order`。

`WidgetTaskStore.kt` 向 Android SQLite 绑定混合类型参数时必须使用 `arrayOf<Any?>`，避免 Kotlin 把 `String`、`Long` 与 `null` 推断成交叉类型并阻断 Release 编译。

Android 小部件集合行使用 `ImageButton` + 状态图标实现勾选，避免在最低 API 24 的 `RemoteViews` 中使用仅 API 31+ 支持的 `CheckBox`。

小部件来源参数必须沿 `WidgetContract` Intent → `WidgetQuickTaskActivity` / `WidgetActionReceiver` → `WidgetTaskStore` 传递，新增操作后必须用 Android Release 编译覆盖 Kotlin 调用链。

## 同步分层

UI → Service → Repository → SQLite/Outbox → SyncEngine → Supabase Gateway

Realtime 只触发增量同步；应用启动、回前台、编辑防抖、5 分钟周期和手动同步负责兜底。

## Android 构建环境

- Flutter 通过 `D:\EXE_Download\android\jbr` 使用 JBR 21.0.10，Gradle Wrapper 使用本地 `D:\EXE_Download\gradle-9.1.0-all.zip`。
- Codex Windows 子进程环境可能让 JBR 的 NIO Selector 在 AF_UNIX 内部管道处报 `Unable to establish loopback connection`；普通 PowerShell 同命令可成功。
- 出现该固定堆栈时不改项目、不清缓存、不重置网络；改用普通 PowerShell/Android Studio 构建，Codex 校验 APK 结构与签名。
