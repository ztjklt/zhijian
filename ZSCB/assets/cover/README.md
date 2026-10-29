# 已批准封面接入

八张 PNG 原样复制自 `docs/art-direction/cover-v10/assets/`，不重新生成、不合并按钮。
素材来源和原始尺寸保留在 manifest.json；完整提示词及原始构图在项目根目录 `docs/art-direction/cover-v10/`。

`layout.json` 保留1672×941原设计。运行时 `scripts/title_menu.gd` 将三个菜单素材变为实际 TextureButton，桌面沿用设计位置，窄竖屏重排触点。

`scenes/title_menu.tscn` 是 Godot 正常启动入口。
