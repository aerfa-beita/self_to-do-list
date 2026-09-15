# Windows / Android 同步与效率模块

> 日期：2026-07-31  
> 应用：1.1.0+2  
> 数据库：v18  
> 原则：SQLite 本地优先、标签分类不变、无 Markdown 编辑器

## 完成功能

### Todo

- 智能视图：收件箱、今天、未来七天。
- 今天包含逾期任务，逾期排在顶部；未来七天从明天开始。
- 单行任务列表；Windows 宽屏点击任务后在右侧显示详情。
- Android：右滑完成、左滑打开编辑/删除操作、长按进入多选。
- 今日负荷：轻松 1、普通 2、费力 3；默认上限 8，可调整。
- 超出上限时软提醒，可改到明天、仍放今天或取消。

### 备忘录

- 根备忘录置顶、取消置顶、归档、移出归档。
- 一条备忘录生成一个 Todo，并自动建立双向关联。
- 一篇备忘录按行生成多个 Todo。
- 支持普通行、`-`、编号、`- [ ]` 的轻量识别；不提供 Markdown 编辑或渲染。
- 备忘录可关联已有 Todo；Todo 的 Windows 侧边详情可查看关联备忘录。
- 原有 5 个 Todo 分类和 8 个备忘录分类名称、筛选和自定义分类逻辑不变。

## 同步架构

```text
Windows / Android UI
        ↓
Service（修改后 4 秒防抖）
        ↓
Repository
        ↓
SQLite v18 + sync_outbox
        ↓
SyncEngine
        ↓
Supabase Auth + REST + Realtime
```

- 启动、回到前台、修改后 4 秒、前台每 5 分钟、手动按钮触发增量同步。
- `sync_id` 跨设备稳定；本机自增 `id` 不上传为关联键。
- 任务、子任务、备忘录、两套分类、Todo/备忘录关联均进入 outbox。
- 软删除作为 tombstone 同步；永久删除发送 delete 记录。
- 拉取时按分类 → Task → Memo → SubTask → Link 顺序处理外键。
- 本地和云端同时修改时不覆盖本地版本，双方快照写入 `sync_conflicts`，JSON 导出包含冲突记录。
- Realtime 只负责唤醒增量同步；断线后仍靠时间游标补拉，因此实时失败不会丢本地修改。
- 登录只保存 access/refresh token，不保存密码；JSON 导出不包含登录 token。

## Supabase 启用

1. 新建 Supabase 项目。
2. 在 SQL Editor 执行 `supabase/schema.sql`，创建表、RLS 和 Realtime publication。
3. 使用项目 URL 和 anon key 构建：

```powershell
flutter build windows --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=ANON_KEY
flutter build apk --release --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=ANON_KEY
```

4. 应用内点云图标，用同一邮箱账号在 Windows 和 Android 登录。
5. 需要实时监听时追加 `--dart-define=SYNC_REALTIME=true`；不开启时仍有完整的非实时增量同步。

## 数据库 v18

新增字段：

- `tasks`：`effort_points`、`sync_id`、`updated_at`、`revision`。
- `subtasks`：`sync_id`、`updated_at`、`revision`。
- `memos`：`pinned_at`、`archived_at`、`sync_id`、`revision`。
- `categories` / `memo_categories`：同步元数据。

新增表：

- `task_memo_links`
- `sync_outbox`
- `sync_runtime`
- `sync_state`
- `sync_conflicts`

迁移测试确认 v17 的任务、备忘录和分类原样保留，并补齐同步元数据。

## 数据安全

- 修改前备份：`.local-backups/todo_list-before-sync-ui-20260731.db`
- 原库与备份 SHA-256 一致。
- 未运行 `flutter clean`，未删除真实数据库。
- 同步未配置或离线时，所有修改先写 SQLite；云端故障不阻塞本机使用。

## 验证结果

- `dart analyze`：0 error，保留 18 条原有/风格 info。
- `flutter test`：4/4 通过。
- Android Release 离线构建：成功。
- APK：`build/app/outputs/flutter-apk/app-release.apk`
- APK 大小：63,587,505 bytes。
- APK SHA-256：`E91ECA5B2D62225AEECE1740440A8F8EF19177320215039D12D397807C3D9C73`
- Windows 源码检查与测试通过；本机 `flutter build windows` 两次均无错误输出地停在 MSBuild `INSTALL.vcxproj`，按规则停止重试，旧 exe 未作为新版本交付。

## 验收顺序

1. Android 安装 APK，检查收件箱/今天/未来七天和三种手势。
2. 新建心力值 3 的今日任务，直到超过上限，检查软提醒三个选项。
3. 新建多行备忘录，测试置顶、归档、生成一个 Todo、生成多个 Todo、关联已有 Todo。
4. Windows 构建恢复后检查宽屏侧边详情。
5. 配置 Supabase 后用同一账号登录双端，依次测试手动同步、离线编辑后重连、Realtime 开关。
