# Supabase 双端同步配置与 Windows 数据路径修复

> 日期：2026-08-19

## 实际根因

1. 近期 Windows 和 Android 使用普通 `flutter build`，没有携带 `SUPABASE_URL` / `SUPABASE_ANON_KEY`，因此运行时同步入口处于“未配置”。
2. Windows 的 SQLite 默认路径跟随启动工作目录，项目内已经产生两份 `todo_list.db`。新版 Release 目录数据库有 74 条待上传记录，但没有登录会话。
3. 访问令牌过期时只显示“离线”，没有尝试刷新后重发，也没有明确要求重新登录。

## 修复

- 新增 `assets/config/supabase.json` 本地公共配置回退；环境变量仍拥有更高优先级。
- 本地配置文件进入应用资源，但被 `.gitignore` 排除；仓库只保留 `supabase.example.json`。
- Android Debug APK 已确认包含正确项目地址、Publishable key 和 Realtime 开关；不再依赖手写构建参数。
- Windows 数据库固定为 `%LOCALAPPDATA%\XiaohuaTodo\todo_list.db`。
- Windows 首次启动时从旧工作目录复制数据库及 WAL/SHM，不删除旧库；稳定库已经存在时不覆盖。
- Supabase REST 请求遇到 401 时先刷新会话并自动重试一次；仍失败则清除失效会话并提示重新登录。
- 同步失败提示保留具体原因，本地 outbox 不清空。

## 验证

- `dart analyze lib test`：0 error、0 warning，保留 15 条既有 info。
- Flutter 完整测试：28/28 通过。
- 同步专项：本地配置回退、全量拉取父子关系修复、205 条 outbox 全批次上传均通过。
- Windows 数据路径专项：旧库复制到稳定目录、旧库保留、后续启动不覆盖稳定库。
- Android Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`，176,727,933 bytes。
- APK SHA-256：`C16ED01AB19730FE796D9E95BC0237B349590A4E5499B6D6FF8D4DE18B701FB1`。
- APK 内配置核验：项目 host、Publishable key、Realtime 均存在。
- Supabase `/auth/v1/settings` 只读连通验证本轮 20 秒超时，按网络规则停止重试；云端实连仍需设备登录验收。

## 双端验收

1. Windows 重新构建并启动，点击云图标登录同步邮箱。
2. Android 安装本轮 Debug APK，登录完全相同的邮箱。
3. Windows 新建任务，手动同步；Android 手动同步后确认出现。
4. Android 修改标题并完成任务；Windows 手动同步后确认回写。
5. 任一端删除任务，另一端同步后确认删除状态一致。
6. 确认同步图标显示成功，待上传数量回到 0。

