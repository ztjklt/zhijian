# 持剑姿态、灰色土著与画质修正

用户反馈：持剑姿态有明显问题，土著白色难辨认且内部粗糙，要求改灰色并开启抗锯齿与锐化。

原因：旧持剑节点用独立世界角度转动，手腕和手臂并未共同跟随；旧换色材质扩大原始透明边缘，角色纹理大幅缩小时又没有 Mipmap 过滤。

修正：

- 手臂 IK 针对实际掌心握点求解，扣除握点在手骨上的偏移；肘部在肩下自然弯曲，手腕与剑身方向统一。待机斜向前上，前摇、下斩、回收和交击回弹共用手部控制，取消剑身的独立旋转。
- 保持玩家已有武器握点，默认土著短剑改握柄中段。退出持剑时清理手腕覆盖，保持绘画、弓箭和徒手动画。
- 原主角图集、比例、骨骼和基础动画不变；土著材质改中灰色，保留原 alpha 轮廓和白色眼睛，不再扩张轮廓。
- 4× 2D MSAA；角色场景的线性 Mipmap 过滤；atlas/grips 导入时生成 Mipmap；世界后处理增加强度 0.18、邻域限幅的轻锐化。后处理在世界之上、UI 之下，不处理输入。

验证：Godot 4.6.3，Metal 4.0 / Forward+，Apple M4 Max。

`sword_pose_test.gd` 33 项从失败修正为全部通过，覆盖左右朝向、6 个攻击阶段、握点随手、手腕与剑轴一致、肘部姿态、退出持剑恢复、运行视口 4× MSAA、后处理与 UI 的层次关系。

最终 17 组隔离检查全部通过：sword_pose、blade_model、native_combat、test_runner、realtime、creation_feedback、weapon_grip、drawing_session、building_physics、auto_sculpt、sculpt_library、player_movement、numeric_controls、wall_climb、knowledge_layout、knowledge_integration、knowledge_migration。命令均为 `python3 tests/run_isolated.py --script res://tests/<脚本>.gd`，没有改写用户存档。

真实渲染：`python3 tests/run_isolated.py --visual --script res://tests/sword_pose_visual.gd` 成功，确认视口 MSAA 枚举为 4×、纹理确有 Mipmap、锐化层覆盖整个视口；查看了放大和正常尺寸的待机、前摇、下斩与回收截图。预览位于工作区 `docs/previews/2026-10-24-sword-quality/`，GIF 来自实际角色骨骼驱动的渲染帧。

保留其他对话已接入的知识地图和操作规则。本次没有启动 Maker 远程构建、部署或重启其他对话的游戏窗口。
