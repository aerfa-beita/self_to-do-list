# todo_list — 项目规则与进度

> 最后更新：2026-07-09

---

## 技术栈
- Flutter 3.44.5 (Dart)
- SQLite 本地数据库（sqflite + sqflite_common_ffi）
- 状态管理：setState
- UI：Material 3

---

## ✅ 已完成

| 模块 | 说明 |
|------|------|
| 项目搭建 | Flutter project 创建，Windows + Android 双平台 |
| 数据模型 | Task（id, title, note, category, created_at, completed_at, deleted_at, due_date, reminder_time, sort_order） |
| 数据模型 | SubTask（5级嵌套 + due_date + deleted_at 软删除） |
| 数据库 | v14：tasks + subtasks + categories + memos + memo_categories 五表 |
| 主页 | Todo 三区视图 + 动态分类过滤 |
| 主页 | 卡片子任务进度 + 展开直接操作子任务 checkbox |
| 详情页 | 备注 + 树形子任务 checkbox + 添加/提升/降入 + 上下移 + 删除 |
| 弹窗 | 新建/编辑任务（标题 + 备注 + 分类下拉 + 截止日期 + 提醒时间） |
| 自定义分类 | 新增/编辑/删除分类，颜色自动生成，重命名联动更新任务 |
| 三区视图 | 未完成 / 已完成（可折叠）/ 最近删除（15天保留，恢复/永久删除） |
| 自动完成 | 所有子任务打勾后自动标记为已完成 |
| 无限嵌套 | 子任务 & 子备忘 5 级嵌套，递归展开/折叠，提升/降入 |
| 时间提醒 | due_date + reminder_time，Android zonedSchedule / Windows Timer |
| 排序 | 上移/下移（主任务 + 所有层级子任务 + 所有层级备忘录） |
| 备忘录分区 | Tab 切换，Enter 快速创建，5级子备忘 |
| 软删除 | 子任务/子备忘删除后划线+移底+可恢复，主任务/备忘录 15 天保留 |
| 右键菜单 | 详情页子任务 + 备忘录条目右键弹出操作菜单 |
| 备忘录分类 | 8 个默认分类（紧急×重要×必须）+ 自定义 + 分类过滤 |
| 架构重构 | 单向依赖（UI→Service→Repository→DB），构造函数 DI |
| 打包 | Windows exe 编译通过，Android apk 编译通过 |
| 搜索 | Todo + 备忘录全文搜索 |
| 深色模式 | 一键切换亮/暗主题（Material 3 + indigo seed） |
| 备忘录通知 | 到期提醒（Android zonedSchedule / Windows Timer） |
| MemoItem 分类 chip | 卡片上显示分类标签 |
| 备忘录分类管理 | 底部弹窗管理分类（新增/编辑/删除） |
| 数据导出 | JSON 全量导出到 Documents 目录 |
| Bug 修复 | AddTaskDialog 标题"备忘录"→"任务" |
| 代码去重 | categoryColor 抽到 utils、DateTimePicker 组件 |

---

## 🔲 待完成

| 模块 | 说明 |
|------|------|
| 单元测试 | widget_test.dart 只是模板，需实质性测试覆盖 |
| Screen 拆分 | 3 个 Screen 均超 400 行，可继续拆分（分类管理弹窗、子任务树、编辑对话框独立文件） |
| use_build_context_synchronously | 多处 async gap 用 BuildContext，可统一加 mounted 守卫 |
| DateTimePicker 替换 | 新建了复用组件，各 Screen 内 inline 日期选择器可逐步替换 |
| 批量操作 | 暂无多选/批量完成/批量删除 |
| 数据导入 | 有导出无导入，可加 JSON 导入恢复功能 |
| 重复提醒 | 目前仅单次提醒，无重复/周期性提醒 |
| 键盘快捷键 | 仅 Ctrl+N，可扩展 Ctrl+F 聚焦搜索等 |

---

## 实现顺序

```
Phase 1: 自定义分类管理      ← ✅
Phase 2: 三区视图            ← ✅
Phase 3: 无限嵌套子任务       ← ✅
Phase 4: 主页展开/收起子任务  ← ✅
Phase 5: 任务时间提醒         ← ✅
Phase 6: 独立备忘录分区       ← ✅
--- 2026-07-09 ---
Phase 7: 搜索/深色模式/通知/导出/去重 ← ✅
```

---

## 当前数据模型（v14）

```sql
CREATE TABLE categories(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE tasks(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '默认',
  created_at TEXT NOT NULL,
  completed_at TEXT,
  deleted_at TEXT,
  due_date TEXT,
  reminder_time TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE subtasks(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL,
  parent_id INTEGER,
  level INTEGER NOT NULL DEFAULT 0,
  title TEXT NOT NULL,
  is_done INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  due_date TEXT,
  reminder_time TEXT,
  deleted_at TEXT,
  FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

CREATE TABLE memos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  parent_id INTEGER,
  level INTEGER NOT NULL DEFAULT 0,
  content TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '紧急+重要+必须',
  sort_order INTEGER NOT NULL DEFAULT 0,
  due_date TEXT,
  reminder_time TEXT,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

---

## 架构：单向依赖

```
UI (screens/widgets) → Service → Repository → DatabaseProvider → SQLite
```

所有依赖通过构造函数注入。详细结构见 `project-docs/STRUCTURE.md`。

---

## 环境
- Flutter: `D:\EXE_Download\flutter`
- Android Studio: `D:\EXE_Download\android`
- Android SDK: `C:\Users\yjhdetianxuan\AppData\Local\Android\Sdk`
- 项目路径: `D:\MY_Project\to-do_list`

---

## 📄 最新文档

| 日期 | 文档 | 说明 |
|------|------|------|
| 2026-07-09 | [docs/2026-07-09-完善与重构.md](docs/2026-07-09-完善与重构.md) | 搜索、深色模式、备忘录通知、导出、去重 |
| 2026-07-09 | [docs/2026-07-09-子任务行高度调整.md](docs/2026-07-09-子任务行高度调整.md) | 子任务行放大到对齐备忘录尺寸 |
| 2026-07-09 | [docs/2026-07-09-子备忘录软删除划线恢复.md](docs/2026-07-09-子备忘录软删除划线恢复.md) | 子备忘录删除后划线+移底+可恢复 |
| 2026-07-09 | [docs/2026-07-09-修复4个Bug.md](docs/2026-07-09-修复4个Bug.md) | Q1删除延迟 / Q2边框 / Q3闹钟 / Q4 Enter提交 |
| 2026-07-09 | [docs/2026-07-09-修复subtasks表deleted_at列缺失.md](docs/2026-07-09-修复subtasks表deleted_at列缺失.md) | DB v15：subtasks 建表补 deleted_at 列 |
| 2026-07-09 | [docs/2026-07-09-子任务行hover重写.md](docs/2026-07-09-子任务行hover重写.md) | MouseRegion + Container 重写 hover（⚠未解决） |
| 2026-07-09 | [docs/2026-07-09-Q1Q2Q3三项修复.md](docs/2026-07-09-Q1Q2Q3三项修复.md) | Q1通知队列 / Q2右键菜单 / Q3子任务闹钟 |
| 2026-07-09 | [docs/2026-07-09-重复提醒功能.md](docs/2026-07-09-重复提醒功能.md) | 重复提醒：每天/每周/每月，自动重调度 |
| 2026-07-09 | [docs/2026-07-09-Windows后台提醒.md](docs/2026-07-09-Windows后台提醒.md) | schtasks + toast：app关闭/重启后仍触发提醒 |
| 2026-07-09 | [docs/2026-07-09-批量操作.md](docs/2026-07-09-批量操作.md) | Todos多选：批量完成/批量删除 |
| 2026-07-09 | [docs/2026-07-09-快捷键.md](docs/2026-07-09-快捷键.md) | Ctrl+F 搜索 / Ctrl+D 深色模式 |
| 2026-07-09 | [docs/2026-07-09-主题持久化.md](docs/2026-07-09-主题持久化.md) | 重启记忆深色/浅色选择 |
| 2026-07-09 | [docs/2026-07-09-备忘录Ctrl+N弹窗创建.md](docs/2026-07-09-备忘录Ctrl+N弹窗创建.md) | 备忘录 Ctrl+N 弹窗创建 + 智能Tab分发 |

> 每次会话结束时更新此表，追加最新文档链接。下一个 session 读到这里就能看到最近所有变更文档。

---

## 🧠 会话交接（最近一次）

| 项目 | 内容 |
|------|------|
| **日期** | 2026-07-09 |
| **做了什么** | 重复提醒(每天/每周/每月)、批量操作(多选完成/删除)、快捷键(Ctrl+N/F/D)、主题持久化(SQLite settings表)、Windows后台提醒(schtasks+toast)、备忘录Ctrl+N弹窗创建、时间选择器记忆、通知队列、右键菜单、子任务闹钟、DB v14→v17迁移 |
| **详细记录** | docs/ 下 13 个文档 |
| **当前进度** | 1-5 项全完成，第6项打包进行中(path已改名MY_Project，build目录已删，需重跑 flutter build windows) |
| **下一步** | flutter build windows 打包、README.md 写完整、GitHub 上传 |
| **踩过的坑** | 中文路径导致 flutter build windows 乱码(已解决：改名MY_Project)；flutter clean 会删掉 db 数据(不要clean，或先备份db)；CMakeCache 缓存旧路径(删build目录重建) |
| **已知未解决** | Q4 子任务hover边框(2轮尝试均未生效)；旧数据被 flutter clean 清掉无法恢复 |
