# 本机射箭、剑模交击与指尖土著验证

2026-10-24，Godot 4.6.3，macOS Apple M4 Max。最新要求：直接复用原主角模型只换白色；剑实际挥动，以完整剑模扫掠判定范围和伤害。

最终隔离检查全部通过：

| 脚本 | 检查数 | 结果 |
| --- | ---: | --- |
| blade_model_test | 22 | 通过 |
| native_combat_test | 31 | 通过 |
| test_runner | 93 | 通过 |
| realtime_test | 68 | 通过 |
| creation_feedback_test | 21 | 通过 |
| weapon_grip_test | 33 | 通过 |
| drawing_session_test | 27 | 通过 |
| building_physics_test | 39 | 通过 |
| auto_sculpt_test | 113 | 通过 |
| sculpt_library_test | 200 | 通过 |
| player_movement_test | 31 | 通过 |
| numeric_controls_test | 30 | 通过 |
| wall_climb_test | 14 | 通过 |
| 合计 | 722 | 0 失败 |

每项通过 `python3 tests/run_isolated.py --script res://tests/<脚本>.gd` 执行，使用临时工程和独立用户数据。旧有“按攻击键就立即扣血”的测试改为确认前摇不扣血、实际挥剑接触后才扣血，数字键沿用并行任务的最新规则。

关键证据包括：同一角色场景、同一贴图和动画资源；持剑显示与碰撞使用相同握点和变换；短剑伪造巨大 reach／damage 仍不能扩大实际命中；不规则和空心笔迹保持空白；跨帧扫到剑身中部可接触小结构；剑模交击、双方挡箭、箭箭相撞、先墙后箭、伤害去重、巡逻落地、受击倒地恢复、数量限制、文字输入与失焦、装备更换取消旧攻击、远处土著重新分布时清理旧挥击轨迹。

真实渲染使用 `python3 tests/run_isolated.py --visual --script res://tests/native_combat_visual.gd`，Metal 4.0 / Forward+，结束时无脚本错误或资源泄漏。已查看 1280×720、844×390、390×844 截图；实际双方剑模相碰产生交击，攻击姿态短暂停留后回弹。动作帧录自真实游戏运行。预览存放于工程根的 `docs/previews/2026-10-24-native-combat/`，包含截图及从实际帧编码的 GIF。

Q 切换短弓／近战，R／攻击按钮出招，N 开关土著，作品菜单提供触屏入口。当前范围为本机试打；不据此宣称多人同步、玩家互伤、正式多人重生或 Railway 部署已交付。
