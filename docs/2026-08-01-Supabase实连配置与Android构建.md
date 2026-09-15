# Supabase 实连配置与 Android 构建

> 日期：2026-08-01  
> 客户端版本：1.2.2+5  
> 目标项目：`xcvebevyrwwghrwonhqt`

## 已完成

- Chrome 登录状态中确认目标项目为 `yezilan698@gmail.com 的项目`。
- Project URL：`https://xcvebevyrwwghrwonhqt.supabase.co`。
- 区域：孟买 `ap-south-1`。
- 使用项目 Publishable key 构建客户端；key 只作为 `--dart-define` 构建参数，没有写入源码、文档或 Git。
- 构建参数启用 `SYNC_REALTIME=true`。
- 对 `/auth/v1/settings` 做只读连通验证，HTTP 状态为 200，证明 URL 与 Publishable key 匹配。
- Android Release APK 构建和签名校验通过。

## Android 产物

- 文件：`build/app/outputs/flutter-apk/todo-list-1.2.2+5-supabase-android.apk`
- 包名：`com.xiaohua.todo_list`
- 版本：1.2.2（versionCode 5）
- 大小：63,905,369 bytes
- SHA-256：`475B330C0A6C4B96F2C83D178385421B92A9DA1C117EED5EA96E194F7FCE31A5`

## 云端执行结果

2026-08-01，小花先生在目标项目 SQL Editor 手动执行 `supabase/schema.sql`，界面返回“成功，未返回任何行”。这是 DDL 脚本的正常结果。脚本已：

- 创建 `public.app_records`；
- 创建 `user_id + entity_type + entity_id` 主键和更新时间索引；
- 开启 RLS；
- 创建仅允许登录用户读写本人记录的 select/insert/update policy；
- 只向 `authenticated` 授予读写权限；
- 把 `app_records` 加入 `supabase_realtime` publication。

脚本使用 `if not exists` 和先删后建 policy，可安全重复执行。当前运行环境随后两次只读 REST 验证均未取得 HTTP 状态，按网络重试规则停止；云端状态以 SQL Editor 成功结果为准，表读写、RLS 和 Realtime 留到双端同账号验收确认。

## 构建命令模板

实际 Publishable key 不写入文档：

```powershell
flutter build apk --release --no-pub `
  --dart-define=SUPABASE_URL=https://xcvebevyrwwghrwonhqt.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=<PUBLISHABLE_KEY> `
  --dart-define=SYNC_REALTIME=true
```

## 安全边界

- 不使用 `service_role` 或 Secret key。
- 不把账号密码、数据库密码或 Publishable key提交到仓库。
- Android 仍需同一账号登录后才会获得 `auth.uid()`，RLS 不允许匿名读取同步数据。
- API 200 和 APK 构建成功不等于多设备同步完成；SQL 成功后仍需 Windows/Android 同账号写入、拉取和冲突测试。
