# 小精灵动作素材 v2 · 第一阶段验收

## 本阶段交付

- `all_actions_contact_sheet.png`：12 组动作总联系表。
- `walk_left_review.gif`：8 帧左行动作，约 11 FPS。
- `walk_right_review.gif`：8 帧右行动作，约 11 FPS，独立绘制，未镜像左行。
- `dragged_review.gif`：4 帧悬空拖动循环，8 FPS。
- `carry_flow_review.gif`：`reach → lift → carry_left → put_down`，共 26 帧。
- `keyframes_numbered.png`：关键帧编号总图。
- `walk_left_frames_review.png`、`walk_right_frames_review.png`、`dragged_frames_review.png`：分动作编号图。
- `动作节奏与分层设计.md`：全部动作的帧数、节奏、重心、锚点与任务卡分层设计。
- `角色一致性核验.md`：原图、现有素材和 v2 设计边界核验。

## 只用于第一阶段验收

本目录没有 `animation_manifest.json`、正式 512×512 透明逐帧、正式 `body_back` / `hands_front` 分层帧或最终 ZIP。预览使用暖米色底，避免白底；确认动作后再进行正式透明分层导出。

## 验收顺序

1. 人物一致性：脸型、头身比、发型、眼镜、绷带、耳环。
2. 脚底接触：支撑脚在着地阶段是否有滑动感。
3. 重心：起步前倾、落脚承重、搬运屈膝与负重前倾。
4. 手型：抓取前张开、抓稳后抬起、接触窝后最后松手。
5. 节奏：步态约 11 FPS，其余动作 8 FPS，是否需要增减停顿帧。

## 已知第一阶段边界

- Chat 生成图用于动作与美术验收，不等同于正式生产帧。
- 正式阶段会重做透明边缘、统一任务卡尺寸，并逐帧记录锚点。
- `carry_flow_review.gif` 先验收左向搬运；右向负重步态在总动作设计中保留，正式阶段独立绘制。

