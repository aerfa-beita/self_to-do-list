# Android Todo 页面精简、拖拽排序与安排收起

> 日期：2026-08-31 · 数据库版本：v20（无迁移）

## 一、已完成内容

### 1. 页面减负（仅 `<900dp`）

- Todo 顶部改为单行“列表 / 安排 + 当前筛选”工具栏；搜索、智能视图、分类和统计收入底部面板。
- AppBar 常驻同步按钮；主题切换、JSON 导出和 JSON 导入合并到“更多”菜单。
- Android 任务卡只显示完成控件、两行标题、必要元信息、子任务完成进度和独立 48dp 拖拽柄。
- Android 列表取消内联子任务展开，点击任务进入详情。
- 小精灵缩为 48dp 边缘入口，展开对话后自动收回，并限制在工具栏、FAB、底部导航之外。
- Windows 宽屏路径保留原有工具栏、任务卡、内联子任务和详情布局。

### 2. 安排分组收起

- `lib/screens/flow_screen.dart` 中的“现在 / 接下来 / 稍后”在窄屏支持独立收起。
- 分组标题栏整个区域可点击，右侧提供 48dp 展开箭头；收起时只显示分组名、未完成数量和箭头。
- 收起时不渲染任务、拖拽柄、“同时任务”按钮或首项预览。
- 安排说明栏按状态显示“全部收起”或“三组全收起时的全部展开”。
- 使用约 180ms 高度动画；“已完成”和“未安排任务”仍由原有独立折叠逻辑控制。
- Windows 三列始终展开，不显示窄屏折叠控件。

### 3. 本机状态记忆

- 新增设置键 `arrangement_collapsed_modes`，复用现有 `settings` 表。
- 只接受 `plan_now`、`plan_next`、`plan_later`；无效、重复或损坏内容会被过滤，默认三组展开。
- 通过 `TaskService → TaskRepository → settings` 读取和保存；不进入同步 outbox，不改变数据库版本，Windows 与 Android 各自保存。

### 4. 安全拖拽排序

- Android 只允许从 48dp 独立拖拽柄启动排序；任务正文长按继续负责多选。
- 手动排序范围为收件箱及其分类/搜索结果；日期视图和精灵窝继续自动排序。
- 仅把当前可见任务 ID 交给事务排序，再合并回完整活动列表；隐藏任务保持相对位置。
- 事务统一更新 `sort_order`、`updated_at` 和 `revision`；失败时重新读取旧顺序。
- Windows 原有上移/下移改为同分类、同完成状态、同安排模式、同精灵窝状态内寻找邻居，避免跨范围移动。
- 拖拽开始提供震动反馈，成功后提供一次“撤销”；撤销同样走事务排序。

## 二、当前架构

| 层 | 入口 |
|---|---|
| UI | `todo_screen.dart`、`flow_screen.dart`、`todo_item.dart`、`workload_companion.dart` |
| Service | `TaskService.reorderTaskSubset`、`getArrangementCollapsedModes`、`setArrangementCollapsedModes` |
| Repository | `TaskRepository.reorderActiveSubset`、设置键读写、同范围上移/下移 |
| Database | v20 既有 `tasks`、`settings` 和同步触发机制；无新增表/迁移 |

排序方向仍为 UI → Service → Repository → Database；折叠状态只写本机 settings，不写云同步字段。

## 三、验证结果

- 安排收起/展开、全部按钮、Windows 展开、紧凑任务卡、360×800 + 文字缩放 1.3、设置过滤、隐藏位置保持、旧移动入口和 Service 接口：专项测试 11/11。
- 完整 Flutter 测试：47/47（`--no-pub --concurrency=1`）。
- 静态检查：0 errors、0 warnings；保留项目原有 17 条 info。
- Android Release 构建：未完成。Flutter/Gradle 多次报 `java.io.IOException: Unable to establish loopback connection`；已确认可用 JDK 在 `D:\EXE_Download\android\jbr`，临时设置 `JAVA_HOME` 后仍复现。工作区现有 APK 最后修改于 2026-08-25，不属于本批次。
- 设备检查：仅发现 Windows、Chrome、Edge，无 Android 真机，因此未进行安装和真机验收。
- 未执行 `flutter clean`，未升级数据库，未清理或覆盖既有工作区数据。

## 四、维护方式

- 新增安排模式时，先更新 `Task.arrangementModes`，再同步 Repository 的合法值过滤和 UI 标题/排序映射。
- 修改排序显示时保持“可见 ID 子集 → 完整活动列表槽位”的算法，不直接给全量列表重新编号。
- 修改窄屏布局时以 `<900dp` 为边界，优先补 360×800、412×915 和 1.3 文字缩放测试；Windows 分支不得复用窄屏折叠状态。
- 涉及数据库字段或同步元数据前先重新评估迁移与 outbox；本批次设置键不应加入云同步。

## 五、潜在问题

- 本轮自动化覆盖了布局、状态和排序逻辑，但 Android Release 构建被本机 Gradle 回环连接阻塞，真机上的页面密度、滚动位置、震动强度、拖拽手感和进程重启恢复仍需验收。
- 持续动画组件不可用 `pumpAndSettle` 作为测试等待条件，应使用固定时长推进。
- Windows Release 仍需运行检查三列安排布局和旧上移/下移入口；双端同账号同步顺序也需独立实测。

## 六、下一步与交接清单

- [ ] 修复本机 Gradle 回环连接/Android 工具链环境，重新构建本批次 Android Release 并确认 APK 时间为本批次。
- [ ] 安装本批次 Android Release，验收 360×800、412×915、文字缩放 1.3。
- [ ] 真机验证三组独立收起、组合状态、全部收起/展开、任务增删/完成/跨组移动后的标题数量。
- [ ] 真机验证拖拽只从柄启动、拖拽期间不误触折叠、撤销和失败恢复。
- [ ] 重启 Android，确认折叠集合恢复；运行 Windows，确认始终三列展开。
- [ ] 完成 Windows/Android 同账号同步和既有后台提醒场景验收。
