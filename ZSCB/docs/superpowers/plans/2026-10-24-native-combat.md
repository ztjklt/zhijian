# 射箭、近战与指尖土著实施计划

目标：在现有 Godot 4.6 本机沙盒中提供可操作的拉弓、挥刀、命中与交击反馈，以及四处游荡的白色火柴人。依据：SPEC 与 2026-10-24 用户要求；最新纠正要求复用原主角模型仅换白色，按实际剑模挥动扫掠判定范围和伤害。

采用：同一个原角色场景和骨架叠加攻击动作，土著材质换白；手持剑模显示与碰撞共用路径和变换，完整扫掠；战斗统一处理双方攻击与弹道。只增靶子无法验证游荡与对刀，另画角色不符合用户最新要求。直接在当前未跟踪工作目录局部修改，保留其他对话成果，不提交、推送或部署。

- [x] 1. 写 `tests/native_combat_test.gd`，实际启动游戏验证：箭的发射/伤害、跨帧扫掠相撞、先墙后箭碰、友方箭忽略、近战交击去重、土著移动/击退/死亡、非练习状态弹道、开背包不暂停、失焦取消拉弓。
- [x] 2. 扩展 `paper_combat.gd`：短弓 0.42 秒拉弓自动释放，挥刀前摇/有效段/回收，独立受击和震刀状态，统一按碰撞时间解析箭/墙/角色，限制弹道和土著数量。保留练习设施接口，旧瞬时伤害改为实际剑模命中。
- [x] 3. `native_agent.gd` 实例化原角色场景，`native_white.gdshader` 只换色；`combat_visual.gd` 仅绘制名字、弓和箭。`blade_sweep.gd` 完整剑模扫掠，模型大小/面积/速度决定伤害；`blade_model_test.gd` 验证假射程无效、空白区域不命中、跨帧剑身接触及与显示变换相同。
- [x] 4. `character_visual.gd`、`held_weapon.gd`、`main.gd`、`toolbar.gd` 接入上半身动作、Q 切弓和菜单入口，保留其他对话最新数字 1–6、二连跳、下穿、攀墙；`creation_feedback.gd` 增交击、镜头震动和音频，不修改 Engine.time_scale。
- [x] 5. 隔离存档运行新增与既有测试，真实渲染动作与交击截图，查看图片；同步 SPEC/README 与本记录。更新后的本机 Godot 画面不代表多人或 Railway 已交付。

重点检查：同帧箭先击墙不能隔墙震刀；同阵营箭不互消；一次挥击不重复扣血；交击时受击不能穿透；文字输入和失焦无幽灵攻击；绘画中移动与确认规则不变；关闭土著清掉其箭，数量有界。

验证命令：`python3 tests/run_isolated.py --script res://tests/native_combat_test.gd`；既有 `test_runner`、`realtime_test`、`weapon_grip_test`、`drawing_session_test`、`building_physics_test`、`auto_sculpt_test`、`sculpt_library_test`、`creation_feedback_test`、`player_movement_test`。画面：隔离 `--visual`。

完成证据：13 组隔离测试、722 项检查全通过；真实 Metal 渲染通过，已查看拉弓、原主角白色模型、剑模交击及横竖窄屏截图。记录见 `../../COMBAT_VALIDATION_2026-10-24.md`。没有操作用户存档、重启其他对话的游戏窗口、远程构建或部署。
