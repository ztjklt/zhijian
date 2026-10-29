# GPT 战斗火柴人组件 v3

用 OpenAI 内置 image_gen 生成：`concept.png` 为战斗护架参考，`atlas.png` 为身体图集，`grips.png` 为用户要求的半握持物手。三个原始 PNG 均保留生成像素和透明通道。对应完整提示词为 `concept-prompt.txt`、`components-prompt.txt`、`grips-prompt.txt`。

`parts/*.tres` 用 AtlasTexture 非破坏性拆出组件；精确范围见 `manifest.json`。场景使用半握手 `hand.tres` / `back_hand.tres`；图集中原始拳型保留作记录，未用于当前手部。铅笔继续使用 v2 的已生成资源。

已组装到 `res://scenes/character.tscn`。原生 Skeleton2D / Bone2D + AnimationPlayer 驱动七种动作。`idle` 改为 2.4 秒循环的战斗护架：前后脚错开，屈膝降低重心，双手抬起，轻微呼吸；离线 IK 只用于生成可编辑关键帧，两脚的落点在循环中保持固定。其他动作显式恢复脚部角度与正常脚掌贴图。眨眼按贴图尺寸补偿缩放。

前后手均有 `WeaponGrip` Marker2D，位于半握手的开口。玩家武器流程：选择 2 武器模式 → 绘画 → F / 画好了 → 点击武器上的握持位置。新武器的 `paths` 保留绘制方向，`grip` 保存归一化后的握持坐标；渲染时每点减去 `grip`，所以该点恒落在手掌连接点上。转身、动画、手机缩放和蹲下均保持连接与武器世界尺寸。武器图纸、装备、撤销与作品存档都携带 `grip`；旧武器没有该字段时以原点为握点。

`res://tests/combat_preview.gd` 用真实场景演示选握点和装备，并渲染战斗待机动画；不会保存作品或教程偏好。实际预览保存在 `docs/previews/2026-10-24-combat-stickman/`。
