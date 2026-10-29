# 高延迟联机验收加固 · 2026-10-26

本轮只修正测试脚本与补充验证证据。当前游戏运行代码、碰撞、伤害、冷却和存档均与本地 r13／协议10相同；未制作新运行版本，公网仍为 r7／协议6。

## 发现与改动

`network_duel_bot.gd`原先将弓箭瞄向朋友位置下方0.15米；真实受击圆心位于上方0.20米、站立半径0.33米。新增诊断捕获到一次服务器明确`attack_started=true`、实际目标未受伤的Web适配双客户端失败。玩家显示／预测位置存在小幅差异，原测试瞄准碰撞下缘之外，射线可能直接擦过；这不能单独证明服务器丢了攻击。

新固定夹具使用显示距离0.96米、真实距离1.30米，左右两个方向都调用测试机器人的实际瞄准、真实拉弓、放箭及房间共享弹丸判定。旧瞄准得到7项检查／2失败；改为真实受击中心后7／0，目标生命必须从100降至76。额外反例验证冷却中发起的攻击仍无箭、无伤害。这版箭矢实际直线飞行，不将其解释成重力下坠。

- 三次弓箭操作共用中心瞄准，冷却后再次读取当前目标位置。
- 测试参与者等待致死的上限由12秒改为30秒，仍在实际死亡时立即结束；攻击者等待死亡回显采用实测RTT加0.2秒、最低0.4秒。伤害、六次攻击上限、3秒重生及保护断言保留。旧时限不足是测试风险，不能据此将所有历史致死失败认定为同一根因。
- 火枪→冷却中尝试弓箭→冷却后弓箭，三次序号分别要求权威回执`attack_started=true / false / true`；保留原0.1+0.66秒请求节奏及最终真实伤害要求。不重试攻击、不在测试中补血或降低命中要求。
- 诊断记录攻击序号、起手回执、生命、位置和当前姿态，不输出凭据或完整画稿。

## 本轮验证

| 检查 | 实际结果 |
| --- | --- |
| 原生完整隔离行为回归 | 122／122通过 |
| Web适配联机专项 | 10／10通过 |
| 双向真实箭矢固定夹具 | RED 7项／2失败 → GREEN 7项／0失败；独立复核7／0 |
| 原生两个完整客户端，额外100ms RTT | 通过；每方向256KiB/s |
| 原生两个完整客户端，额外600ms RTT | 通过；每方向256KiB/s |
| Web适配两个完整客户端，额外100ms RTT | 通过；每方向256KiB/s |
| Web适配两个完整客户端，额外600ms RTT | 通过；每方向256KiB/s |
| r7—r13历史冻结清单 | 21份清单逐项校验，零差异 |
| 当前r13非测试文件 | 896项与冻结来源相同 |

最后四轮完整客户端均使用加强回执断言后的机器人，包含双向近战、致死／重生、装备／草稿保留、真实弓箭命中、打开图纸取消拉弓、凭据重连、火枪切弓冷却及确认保存关房。另保留两轮加强回执前的600ms通过日志，不混作最后四轮。

`web/run_checks.py`十项为：network_duel_aim、network_bow_intent、network_bow_transition_authority、network_duel_arrows、network_duel_state、network_duel_sync、network_client、online_prediction_delay、online_prediction_transition、online_jitter_burst。均在Web适配工程的桌面Godot副本执行，不是浏览器WASM实玩。

完整测试由临时工程、随机项目名与私有用户资料运行；本机测试权威使用临时世界目录，不触碰玩家真实作品。独立只读审查未发现阻塞问题或削弱断言。

## 证据与边界

证据位于`docs/previews/network-reliability-20261026/`：`diagnostic-web/`保留已起手但未命中的失败，`final-native-100/`、`final-native-600-b/`、`final-web-100/`、`final-web-600-b/`为最后四轮；`logs/`保留RED／GREEN、完整回归和各次运行输出，`review.txt`、`integrity.json`及`final-status.json`记录复核与范围。

本轮证明当前r13在上述受控场景完成对战流程，同时修正了一类测试误判。此前r11等历史600ms失败记录继续保留，不追溯改成通过，也不宣称所有高延迟手感问题均已解决。仍需不同网络两台物理设备实玩；未部署Railway、未进行Maker远程构建。Maker本地预览为stopped，未自动启动。

复验：

```sh
python3 tests/run_isolated.py --script res://tests/network_duel_aim_test.gd
python3 tests/run_headless_suite.py
python3 tests/run_network_clients.py --duel --latency-ms 600 --bandwidth-kbps 256 --evidence-dir docs/previews/network-reliability-recheck
```
