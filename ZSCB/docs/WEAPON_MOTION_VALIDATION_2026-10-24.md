# 手持武器四式与衔接验证 · 2026-10-24

本次增加下劈、反手上挑、前刺、重斩。沿用 R／攻击按钮和无草稿右键；持续短间隔按键依次接招，停手后回防，停顿超过连击窗口后重新从下劈开始。没有输入不会自动连发。

`weapon_motion.gd` 提供共享动作曲线：掌心位置、剑身角度和身体前倾以带限幅切线的三次 Hermite 曲线过渡；同向运动保留速度，极值及开始／结束处平滑减速。后手提供反向平衡，头部抵消躯干旋转；腿保留原动画。`combat_pose.gd` 继续用原腕部 IK 控制握点；`held_weapon.gd`、`blade_sweep.gd` 和真实轮廓判定未改为额外射线或圆形范围。

收势或冷却末尾最多保留一个输入，期限 0.20 秒；原武器冷却保持，最低覆盖 0.36 秒动作时长。背包、文本焦点、握点选择、换装备、切弓、失焦、受击、对刀和重置会清除缓存。灰色土著共用四式，但保留原 AI 预警和较长攻击间隔。

## 验证

命令均为 `python3 tests/run_isolated.py --script res://tests/<name>.gd`，副本运行，隔离用户数据。

- 新增 `weapon_motion_test.gd`：1188 项检查通过。真实场景中四次攻击剑身方向不同；四式都能以实际模型命中附近目标，每次只命中一次，前摇不扣血。验证末段输入缓存、只多出一次攻击、重武器冷却结束后接招、中断清理，以及左右镜像下每式 73 个采样的握点贴手与连续剑身位移。
- 先在旧实现观察到 9 项预期失败（动作重复、无法缓存）；补充重武器案例再观察到 1 项预期失败后修正，最终零失败。
- 原战斗检查：`sword_pose_test.gd` 33、`blade_model_test.gd` 22、`native_combat_test.gd` 31，全部通过。
- 其余 14 组回归全部通过：`test_runner` 93、`realtime` 69、`creation_feedback` 21、`weapon_grip` 33、`drawing_session` 27、`building_physics` 39、`auto_sculpt` 113、`sculpt_library` 200、`player_movement` 31、`numeric_controls` 30、`wall_climb` 14、`knowledge_layout` 语义排版 PASS、`knowledge_integration` 35、`knowledge_migration` 12。
- 共 18 组自动检查通过。现有灰色材质、2D MSAA、世界锐化与 UI 层级保留。

GPU 实录命令：`python3 tests/run_isolated.py --visual --script res://tests/weapon_motion_visual.gd`。Godot 4.6.3 / Metal 4.0 / Apple M4 Max，退出码 0，无脚本或资源泄漏报错。玩家通过真实攻击入口和缓存依次执行四式；旁边灰色原角色骨架同步镜像，用于目视比较动作。镜像参考在该测试中不参与决斗，避免交击中断展示；实际伤害、对刀和箭的回归由上述战斗测试覆盖。

录制 112 帧，动图及四式静帧位于工程父目录 `docs/previews/2026-10-24-weapon-motion/`。已读取四式画面核对方向、姿态和剑柄贴手。录制为放大近景，无额外修改角色模型；不代表多人联机已经实现。
