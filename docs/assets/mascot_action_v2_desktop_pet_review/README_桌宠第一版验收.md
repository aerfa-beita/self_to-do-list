# 小精灵动作素材 v2 · 桌宠第一版验收

## 本目录用途

本目录只包含独立美术与动作素材，没有修改 Flutter 代码，也没有覆盖 `assets/mascot/2_5d` 或上一阶段验收目录。

## 优先可复用素材

| 素材 | 路径 | 规格 | 可复用范围 |
|---|---|---|---|
| 正面 idle 基准帧 | `front_idle/front_idle_000.png` | 512×512 RGBA | 桌宠第一版默认站立形态、后续动作身份锚点 |
| celebrate | `celebrate/celebrate_001.png` ～ `celebrate_008.png` | 每帧 512×512 RGBA | 完成任务后的庆祝动画，建议 10 FPS |
| dragged | `dragged/dragged_001.png` ～ `dragged_004.png` | 每帧 512×512 RGBA | 鼠标拖动时的悬空循环，建议 8 FPS |
| Windows 头像 | `avatar/windows_avatar_1024.png` | 1024×1024 RGBA | Windows 程序图标源图、托盘头像源图 |
| 头像缩放版 | `avatar/windows_avatar_256.png`、`64.png`、`48.png` | RGBA | 图标与托盘小尺寸预览；正式 ICO 可由桌宠项目转换 |
| 收起形态 A | `collapsed_options/option_a_avatar_badge_*` | 512/72/64/48 RGBA | 第一版首选；角色身份最完整、最容易识别 |
| 收起形态 B | `collapsed_options/option_b_nest_dumpling_*` | 512/72/64/48 RGBA | 更软萌的小窝团子备选 |
| 收起形态 C | `collapsed_options/option_c_glasses_hair_token_*` | 512/72/64/48 RGBA | 最简识别物备选，占用感最低 |

## 动作帧语义

### celebrate

- `celebrate_001.png`：直立起始。
- `celebrate_002.png`：屈膝蓄力，手臂后摆。
- `celebrate_003.png`：腿部发力，双臂上抬。
- `celebrate_004.png`：小幅离地。
- `celebrate_005.png`：短暂滞空，耳坠延迟。
- `celebrate_006.png`：下降准备触地。
- `celebrate_007.png`：屈膝落地缓冲。
- `celebrate_008.png`：回到直立。

### dragged

- `dragged_001.png`：向左柔软偏摆。
- `dragged_002.png`：居中收膝。
- `dragged_003.png`：向右偏摆，单腿延迟。
- `dragged_004.png`：回中并准备循环。

## 角色锁定项

- 完整人物连续绘制，不使用散件旋转。
- 瘦圆脸、左右耳大小一致。
- 解剖学右耳单耳坠；正面观看位于画面左侧。
- 解剖学左前臂三圈绷带；正面观看位于画面右侧。
- 黑色蓬松碎发、矩形眼镜、黑色椭圆眼、小波浪嘴。
- 白短袖、黑短裤、赤脚、暖棕轮廓、柔软蜡笔质感。
- 无膝肘连接筒、腿环、鞋子或新增装饰。

## 验收图

- `celebrate/celebrate_contact_sheet.png`：庆祝关键姿势编号图。
- `celebrate/celebrate_review.gif`：庆祝 8 帧预览。
- `dragged/dragged_review.gif`：拖动 4 帧预览。
- `collapsed_options/collapsed_options_contact_sheet.png`：三种收起形态对照。
- `collapsed_options/collapsed_options_64px_readability.png`：实际 64px 缩小后放大观察的可读性对照。

## 延续动作

`walk_left`、`walk_right`、`reach`、`lift`、`carry_left`、`carry_right`、`put_down` 继续沿用 `../mascot_action_v2_review/` 的动作节奏与分层方案。本目录不重复覆盖上一阶段文件。

