# to-do_list — 项目索引

> 最后更新：2026-07-09

---

## 项目简介

Flutter 桌面端（Windows + Android）备忘录 + Todo List 应用，Material 3 UI，SQLite 本地存储。

---

## 快速导航

| 文档 | 说明 |
|------|------|
| [CLAUDE.md](../CLAUDE.md) | 项目规则、技术栈、已完成功能 |
| [README.md](../README.md) | GitHub 首页 |
| [STRUCTURE.md](STRUCTURE.md) | 目录结构、文件关系、架构图 |
| [CODE_STATS.md](CODE_STATS.md) | 代码统计 |

---

## 2026-07-09 新增功能

| 功能 | 状态 |
|------|------|
| 重复提醒（每天/每周/每月） | ✅ |
| 批量操作（多选完成/删除） | ✅ |
| 快捷键（Ctrl+N/F/D） | ✅ |
| 主题持久化（重启记忆） | ✅ |
| Windows 后台提醒（schtasks + toast） | ✅ |
| 备忘录 Ctrl+N 弹窗创建 | ✅ |
| 时间选择器记忆 | ✅ |
| 通知队列（多通知不丢失） | ✅ |
| Todo 右键菜单 | ✅ |
| 子任务闹钟 | ✅ |

## 已知问题

| 问题 | 状态 |
|------|------|
| 子任务 hover 边框 | ⚠️ 两轮修复未生效 |
| flutter clean 会清掉 db 数据 | ⚠️ 需手动备份 |

---

## 技术栈

- Flutter 3.44.5 / Dart 3.12+ · SQLite · Material 3 · Windows schtasks

## 架构

UI → Service → Repository → DatabaseProvider → SQLite（单向依赖，构造函数 DI）

## 数据库

| 表 | 说明 |
|----|------|
| tasks / subtasks | 任务+子任务（5级嵌套、软删除、重复提醒） |
| memos | 备忘录（5级嵌套、分类、重复提醒） |
| categories / memo_categories | 分类管理 |
| settings | 键值存储（深色模式偏好） |

当前 DB 版本：v17
