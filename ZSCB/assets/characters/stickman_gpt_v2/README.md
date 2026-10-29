# GPT 火柴人组件 v2

用 OpenAI 内置 image_gen 生成的透明组件图集。黑色剪影、白色锐眼、平滑收束的四肢，保持纯火柴人造型。

`atlas.png` 保留生成原始像素；`parts/*.tres` 为独立可替换的 AtlasTexture，裁切范围见 `manifest.json`，完整提示词见 `prompt.txt`。

已接入 `res://scenes/character.tscn` 的原生 Skeleton2D / Bone2D。头部从 26 缩至 20 像素，四肢加粗并增加接头重叠，背侧部件也使用不透明像素，消除半透明接缝。七段动画继续使用原有库。
