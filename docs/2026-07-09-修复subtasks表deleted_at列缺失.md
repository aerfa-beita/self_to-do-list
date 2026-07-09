# 2026-07-09 修复 subtasks 表 deleted_at 列缺失

## 问题

`flutter run` 后崩溃：
```
table subtasks has no column named deleted_at
```

## 根因

`database.dart` `_onCreate()` 的 `CREATE TABLE subtasks` 语句缺少 `deleted_at TEXT`。
`onUpgrade` v13 有 `ALTER TABLE ADD COLUMN deleted_at`，但全新建库时走的是 `onCreate` 而不是 upgrade 链。

## 修复

1. `_onCreate` — subtasks 建表语句加 `deleted_at TEXT,`
2. DB 版本 v14 → **v15**，新增 v15 迁移：`ALTER TABLE subtasks ADD COLUMN deleted_at TEXT`

新库直接建表就有，旧库自动迁移补上。
