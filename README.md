# 🌸 小花备忘录 & Todo List

Flutter 桌面效率工具 · Material 3 · SQLite 本地存储 · Windows + Android

## ✨ 功能

**备忘录**
- 树形嵌套（5级子备忘）· 分类标签（8 个默认 + 自定义）· 弹窗创建（Ctrl+N）
- 到期提醒 + 重复提醒（每天/每周/每月）· 后台提醒（关机重启仍触发）
- 全文搜索 · 长按/右键菜单 · 软删除（划线+移底+可恢复）

**Todo List**
- 三区视图（未完成/已完成/最近删除）· 子任务（5级嵌套）
- 自动完成检测（全部子任务完成→自动标记）
- 到期提醒 + 重复提醒 · 子任务闹钟
- 全文搜索 · 右键菜单 · 批量操作（多选完成/删除）

**通用**
- 深色模式（Ctrl+D，重启记忆）· 快捷键（Ctrl+N/F/D）
- JSON 数据导出 · 通知队列（多通知不丢失）· 时间选择器记忆

## 🚀 运行

```bash
flutter pub get
flutter run -d windows    # 桌面
flutter run -d <device>   # Android
```

## 📦 打包

```bash
flutter build windows                    # exe 在 build/windows/x64/runner/Release/
flutter build apk --release              # apk 在 build/app/outputs/apk/release/
```

## 🛠 技术栈

Flutter 3.44 / Dart 3.12 · SQLite (sqflite + ffi) · Material 3 · Windows schtasks + toast · Android zonedSchedule

## 📄 文档体系

```
CLAUDE.md          → 会话入口（交接 + 待办 + 最新文档）
README.md          → 本文件（功能介绍，每次加功能后更新）
project-docs/
  INDEX.md         → 项目索引（技术栈、环境、文档导航）
  STRUCTURE.md     → 目录树 + 分层架构
docs/              → 按日期的变更记录
```

> 加新功能后必须更新 README.md 的功能列表
