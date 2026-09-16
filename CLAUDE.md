# todo_list — 项目规则与进度

> 最后更新：2026-09-15 · DB v22 · 路径 `D:\MY_Project\to-do_list`
> 技术栈/架构/环境详见 `project-docs/INDEX.md` + `STRUCTURE.md`

---

## 🧠 会话交接

| 项目 | 内容 |
|------|------|
| **日期** | 2026-09-15 |
| **做了什么** | Android 改为“备忘录 / 安排”底部导航，安排顶部收敛为“本周 / 阶段 / 收件箱”。收件箱加入已安排，三类页面各自显示来源已完成/最近删除；已安排只管理不完成/删除。长按负责排序，多选改为明确按钮，任务与备忘录三点菜单统一图标和顺序。DB 升至 v22，新增 `completed_scope`、`deleted_scope`，同步、JSON、恢复规则和 Android 小部件一并适配。 |
| **下一步** | Flutter 完整测试 61/61、静态分析和 Windows Release 已通过。Android 普通终端发现的小部件删除 `kind` 未传参已修复；Codex 重试被既有回环故障拦截，需小花先生在原普通终端重跑 Release，再侧装真机验收。 |
| **踩坑** | Android 原生小部件新增来源参数时，必须沿 Intent → Activity → Store 的整条调用链传递；Flutter 测试不会编译 Kotlin，不能替代 Android Release 构建。 |
| **已知问题** | Codex Windows 子进程内 Android Release 仍报 `Unable to establish loopback connection`；`kind` 源码错误已修复但需普通终端确认 Kotlin 编译。本批尚未生成 v22 APK，当前也无 Android 设备或 AVD。静态分析保留同步网关既有 2 条 warning；列表逐条读取子任务进度仍是性能后续项。 |
| **自我改进** | 跨视图任务应把业务属性、视图排序、状态来源分开建模；手势只承担一个主要动作，长按排序后多选必须使用可见入口；发布验收必须核对产物时间和实际设备。 |

---

## 🔲 待完成

| # | 内容 |
|---|------|
| — | 在普通 PowerShell/Android Studio 构建 v22 Android Release；当前 12:41 APK 是旧 v21 包，禁止作为本批验收产物 |
| — | 侧装 v22 Android Release，实机验收安排顶部三页、来源已完成/最近删除、二级移动面板、长按排序、页面恢复与两个桌面小部件 |
| — | 后续评估“逾期未完成集中处理”、常用任务模板、批量读取子任务进度和仅在任务变化时更新提醒 |
| — | Windows Release 验收备忘录子树级联转 Todo：父+2 层子 memo 三入口行为（详情页 SubTask 树 / 按行生成提示 / 关联反查）+ 同步核对 |
| — | 手机装最新 release（含 R8 + 精确闹钟 + 白名单引导）验收：开 app/划掉 app/重启手机 三场景设提醒 → 到点收到；同步、安排折叠区、小精灵脱节 |
| — | Windows/Android 同账号验收阶段、日期、完成来源和删除来源同步 |
| — | Android“现在 / 本周”小部件待 Gradle 环境恢复后生成正式包，并做手机、平板 Launcher 实机验收 |
| — | VS18 `cl.exe /Bv` 已恢复；交互式 CMD 已连续两次成功构建 Windows Release |
| — | Supabase 本地公共配置与数据路径已修复；云端端点本轮超时，待双端同账号实连验收 |
| — | 运行新版 Windows Release，完成 Todo / 阶段模式视觉与交互验收 |
| — | 由小花先生决定是否从 `.local-backups/todo_list-before-sync-ui-20260731.db` 恢复旧删除内容 |
| — | 子任务 hover 边框 bug |

---

## 📄 最新文档

| 批次 | 内容 |
|------|------|
| 9/15 | Android 小部件删除操作补齐 `kind` 参数链，修复 `compileReleaseKotlin` 的 unresolved reference；见 `docs/2026-09-15-Android小部件删除作用域编译修复.md` |
| 9/15 | Android“安排优先”整体改版、DB v22、来源归档与恢复、单层导航、已安排管理页及统一图标菜单；见 `docs/2026-09-15-Android安排优先整体改版.md` |
| 9/15 | Gradle 回环报错定因：Codex Windows 子进程的 JBR NIO/AF_UNIX 环境异常；普通终端构建成功，APK 结构与 v2 签名有效；见 `docs/2026-09-15-Gradle回环连接诊断.md` |
| 9/15 | Android 本周/阶段/列表重构、DB v21、本周独立排序、页面恢复与滑动误触修复；见 `docs/2026-09-15-Android本周阶段与列表改造.md` |
| 9/13 | 收件箱独占已完成/最近删除、安排移除完成捷径、Android 小部件远程视图勾选兼容修复；见 `docs/2026-09-13-收件箱归属与小部件加载修复.md` |
| 9/12 | 收件箱职责收拢、列表/安排命名、分组底部精简添加、Android“现在/本周”桌面小部件及 Kotlin Release 类型推断修复；见 `docs/2026-09-12-收件箱安排与Android桌面小部件.md` |
| 9/12 | 阶段/本周双视图的前序方案与变更历史；当前入口与添加位置以上一行新文档为准；见 `docs/2026-09-12-阶段与本周双视图.md` |
| 8/31 | Android Todo 页面减负、独立安排收起与安全拖拽排序（本机折叠记忆、事务排序、一次撤销）；见 `docs/2026-08-31-Android Todo页面精简拖拽与安排收起.md` |
| 8/31 | Android Todo 长按取消、多选删除去重、完成区域减负与安排完成 7 天清理；见 `docs/2026-08-31-Android Todo交互与完成任务清理.md` |
| 8/25 | 备忘录子树级联转 Todo（子层级转 SubTask 树、按行生成有子级不拆行、关联级联一对多）；见 `docs/2026-08-25-备忘录子树级联转Todo.md` |
| 8/24 | Android 后台提醒保障：精确闹钟 + 小米白名单引导（不打开 app 也能提醒）；见 `docs/2026-08-24-Android后台提醒保障.md` |
| 8/24 | Android 提醒失效根因：R8 丢泛型（Missing type parameter）+ proguard 修复；见 `docs/2026-08-24-Android提醒R8丢泛型修复.md` |
| 8/24 | 小精灵脱节根因（素材 8px 边距×fill）修复 + Android release 重建 + 提醒验收指引；见 `docs/2026-08-24-小精灵脱节根因与Android提醒验收.md` |
| 8/20 | 安排模式改造（完成折叠区/行菜单编辑删除/详情页三段切换）；见 `docs/2026-08-20-安排模式完成折叠区与任务管理.md` |
| 8/20 | 同步推送中文编码修复（双端从未同步成功的根因）+ 编码回归测试；见 `docs/2026-08-20-同步中文编码修复.md` |
| 8/19 | Todo 单模块“列表｜安排”、三段分组、无锁定互转与双端自适应；见 `docs/2026-08-19-Todo列表与安排模式.md` |
| 8/19 | Supabase 普通构建配置、会话刷新、Windows 稳定数据路径与迁移；见 `docs/2026-08-19-Supabase双端同步配置与Windows数据路径修复.md` |
| 8/18 | Todo / 流程双模块、顺序步骤、双向互通与 DB v20；见 `docs/2026-08-18-Todo与流程双模块互通.md` |
| 8/17 | 最终 2.5D 分层素材、关节步态、拖动吸边、双手搬运与 Android 提醒修复；见 `docs/2026-08-17-2.5D小精灵动作拖拽与Android提醒修复.md` |
| 8/16 | 双端同步批次/全量拉取/关系修复、同步后刷新、手机输入与精灵空间优化；见 `docs/2026-08-16-双端同步与移动端交互完善.md` |
| 8/16 | 3D 小精灵透明 WebP、五状态机、Todo 触发逻辑与路线评估；见 `docs/2026-08-16-3D小精灵轻量集成.md` |
| 8/01 | Supabase目标核验、Publishable客户端配置、Realtime与Android 1.2.2+5构建；见 `docs/2026-08-01-Supabase实连配置与Android构建.md` |
| 8/01 | 两步时间向导、跨屏吞任务、横幅关闭、旧版/真实Release JSON合并与Android APK；见 `docs/2026-08-01-创建时间向导跨屏精灵与旧版JSON合并.md` |
| 8/01 | Q版人物建模设定、原生关节绘制与步态动画；见 `docs/2026-08-01-Q版人物关节步态动画.md` |
| 7/31 | 整体UI、备忘录自适应详情、小花精灵/精灵窝、JSON双端合并备份、数据安全核验；见 `docs/2026-07-31-整体UI精灵负荷与JSON双端备份.md` |
| 7/31 | Windows/Android同步、Todo效率视图与心力负荷、备忘录置顶归档和Todo联动；见 `docs/2026-07-31-Windows-Android同步与效率模块.md` |
| 7/12 | Q2-Q5四项完善(分类按钮+搜索隐藏+拖拽排序+长按菜单)+Ctrl+Shift+N快捷键+sort_order修复 |
| 7/10 | Android白屏修复、备忘录分类横滑、文档体系重构、Hook加强(备份+边界+stop-check) |
| 7/09 | 打包上传、主题持久化、快捷键、批量操作、后台提醒、重复提醒等 12 篇 |

> 删旧留新，旧文档索引见 `project-docs/INDEX.md`
