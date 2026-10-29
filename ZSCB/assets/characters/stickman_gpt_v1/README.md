# GPT 火柴人组件 v1

OpenAI 内置 image_gen 生成的透明组件图集：圆头、线条躯干、上/前臂、手、上/下腿、简单脚掌、关节补片、铅笔、闭眼头、握笔手。保持黑白火柴人风格，无头发、帽子或衣服。

`atlas.png` 保留原始透明像素；`parts/*.tres` 为可单独替换的非破坏性 AtlasTexture 组件，精确范围见 manifest.json。生成提示词见 prompt.txt。

已组装至 res://scenes/character.tscn；原有七段动画继续驱动，肢体长度和髋部高度已适配火柴人比例。
