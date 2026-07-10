# to-do_list — 项目结构

> 最后更新：2026-07-10

---

## 目录树

```
MY_Project/to-do_list/
├── README.md                         # GitHub 首页 🆕
├── CLAUDE.md                         # 核心交接文档
├── pubspec.yaml
├── .gitignore
├── assets/
│   ├── fonts/msyh.ttc
│   └── scripts/show_toast.ps1        # Windows toast 通知脚本 🆕
├── docs/                             # 13 个变更文档 🆕
├── project-docs/                     # 索引/结构/统计 🆕
├── lib/
│   ├── main.dart                     # 入口 + DI + TabBar + 快捷键 🆕
│   ├── database/database.dart        # DB v17 + settings 表 + exportAllJson 🆕
│   ├── models/  (3个: task/sub_task/memo)  # +repeatType 🆕
│   ├── repositories/  (5个)
│   ├── services/
│   │   ├── task_service.dart
│   │   ├── memo_service.dart
│   │   └── notification_service.dart # 通知队列 + schtasks + repeat 🆕
│   ├── screens/
│   │   ├── todo_screen.dart          # +批量选择 + Ctrl+N 🆕
│   │   ├── task_detail_screen.dart   # +子任务闹钟 + 重复选择器 🆕
│   │   └── memo_screen.dart          # +弹窗创建 + 批量选择 + 搜索 🆕
│   ├── widgets/
│   │   ├── todo_item.dart            # +选择模式 + 右键菜单 🆕
│   │   ├── memo_item.dart            # +选择模式 + 分类 chip 🆕
│   │   ├── add_todo_dialog.dart      # +重复选择器 + Enter提交 🆕
│   │   └── date_time_picker.dart     # +时间记忆 🆕
│   └── utils/date_utils.dart         # +categoryColor 🆕
├── test/widget_test.dart
├── windows/                          # Windows runner (C++)
└── android/                          # Android (Kotlin)
```

## DB 版本历史

v14 → v15 (subtasks.deleted_at) → v16 (repeat_type) → v17 (settings 表)
