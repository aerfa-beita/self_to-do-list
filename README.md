# 🌸 小花备忘录 & Todo List

Flutter 桌面效率工具——备忘录 + Todo 双栏，Material 3，SQLite 本地存储。

## ✨ 功能

- **备忘录**：树形嵌套（5级）、分类标签、到期提醒、重复提醒（每天/每周/每月）
- **Todo List**：三区视图（未完成/已完成/最近删除）、子任务（5级）、自动完成检测
- **后台提醒**：Windows 任务计划 + 原生 toast，app 关闭/重启后仍然触发
- **批量操作**：多选批量完成/删除
- **搜索**：全文搜索（Todo + 备忘录）
- **深色模式**：一键切换（Ctrl+D），重启记忆偏好
- **快捷键**：`Ctrl+N` 新建 / `Ctrl+F` 搜索 / `Ctrl+D` 切换主题
- **数据导出**：JSON 导出到 Documents 目录

## 🚀 运行

```bash
flutter pub get
flutter run -d windows
```

## 📦 打包

```bash
flutter build windows
# exe 在 build/windows/x64/runner/Release/
```

## 🛠 技术栈

Flutter 3.44 / Dart 3.12 · SQLite · Material 3 · Windows schtasks

## 📄 文档

`CLAUDE.md` — 完整项目规则、进度、数据库模型
`project-docs/` — 项目索引、结构、代码统计
`docs/` — 变更记录
