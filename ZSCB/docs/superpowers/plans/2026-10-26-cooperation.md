# 双人共同搭建 Implementation Plan

> Use superpowers:executing-plans inline. 用户已授权按顺序直接实施，不重复索取计划审批。

**Goal:** 作者逐件开放朋友搬动／连接，让双方完整笔迹组成真实结构，并能撤回许可。
**Architecture:** 房间持有最多128件临时共享许可；作者身份和拆除权不转移。复用原锁、版本、真实关节和12米检查；权限撤销／任一人断线时结束借用，存档只存作品和连接。
**Tech Stack:** Godot4.6.3，GDScript，现有WSS与Web覆盖层；不安装依赖。
**Spec:** SPEC v0.44第13节第五阶段授权，本轮细化为v0.45。

## Global Constraints
- 本地协议10／r12成套候选，不部署、不触碰历史包或个人存档。
- 只开放搬动／连接／解除；拆除仍归作者，图纸／装备／攻击／保存权限不扩大。
- 同数字键与完整笔迹、墨水、真实物理、现有草稿不变；共享不写物件或世界存档。
- 任一人断线清空所有临时许可，保留已完成连接；重连须作者重新开放。撤回即时释放朋友编辑锁并增加版本，迟到移动失败。
- 用户共享未跟踪主线，沿用会话直接实施授权；局部补丁、备份/tmp/paper-cooperation-original-20261026，不切分支／提交。

## Review Focus
- 朋友不能自行开放、拆除或通过撤销绕过撤回、距离、锁与版本；碰撞破损仍有效。
- 跨作者连接后撤回不拆结构；解除需双方部件的当前许可，作者仍能拆自己的端点。
- 旧移动／连接撤销不能覆盖另一人的后来改动；建立／解除连接也要更新两端版本。
- 当前帧必须同步共享状态和编辑者；迟到快照／重连不恢复过期许可。
- 个人协作面板隔离绘画、攻击、地图键与触控，宽窄屏控件可达，单人入口说明联机用途。

### Task1 权威许可与实际共建
Files: new scripts/net/cooperation.gd, tests/cooperation_test.gd; room.gd.
Interfaces: can_use(actor,object), apply(actor,msg), clear(), remove(id), snapshot(); all operate room-owned state.
- [x] RED：默认保护、作者开放、编号去重、朋友搬动、不能拆除、编辑锁、撤回迟到消息、跨作者关节、撤销版本、断线／导入／存档。
- [x] 实现临时许可、复用移动／连接检查，更新撤销与端点版本；GREEN。

### Task2 个人协作界面与同步
Files: new cooperation_panel.gd/cooperation_ui_test.gd; main.gd, toolbar.gd, session.gd, touch_controls.gd, experience_panel.gd; Web adapter.
Interfaces: game.cooperation={shared:Array,locks:Dictionary}; can_cooperate(object), open_cooperation(), cooperation_action(id,enabled); panel.refresh().
- [x] RED：真实入口、逐件操作、作者／朋友提示、关闭回4搭建、四尺寸、真实快捷键／触控隔离。
- [x] 实现共享状态快照及帧同步、撤回时取消本人拖动、实际面板控件；GREEN和真实渲染。

### Task3 整体审查与最终验证
Files: cooperation_bot.gd, run_network_clients.py; docs与r12源码／Web／权威。
- [x] 两个完整客户端各画一件、开放、朋友移动、共同连接、双方显示真实结构、撤回拒绝、保存与重开保留结构但清空许可。
- [x] 独立只读审查，必要修复RED→GREEN；最终本机回归、匹配Web专项、成套导出及SHA。
- [x] SPEC／AGENTS／报告、证据同步；本地预览保持停止，测试资源清理。

## Execution ledger
- Pre-flight: Task1 server grants and Task2 client cooperation share only immutable snapshots; grants never travel inside object/world saves. Task3 actual clients consume same operations as panel.
- Ruling: 开放只含搬动和连接，保留拆除权，避免合作变成全权限；许可仅当前双人会话，任一人断线都清空，避免下一位朋友继承许可。
- Ruling: 建立／解除连接增加两端版本并记录撤销版本，防止后来的共同操作被旧撤销覆盖；撤回不破坏已有结构。

- Task1 complete: 权威38/0，复制端9/0；许可只在room，世界/对象/资料不带许可。
- Task2 complete: UI47/0，真实两地图快捷键、触控与四尺寸；默认深灰列表经视觉检查改为纸面墨色，配色断言RED→GREEN。
- Task3: 三套完整客户端100ms/256KiB/s实际生成、共建与重开通过；Web14/14，传输15/15，Python2/2。全量最终结果见专项报告日志。
- Review P2: 删除历史存下存活连接端点版本，恢复前复查；RED真实生命周期37项3失败→GREEN37/0，独立审查者复跑确认。元数据修正另经只读审查无阻塞。
- Ruling: 许可单独版本和普通帧足以同步，不提升世界revision；避免许可触发全图resync打断他人拖动。新回归38th先失败后通过。
- Ruling: 原结构撤销夹具固定version=1不再符合连接增加端点版本的规则；读取真实版本，保留全部13项保护检查，不放宽权限。
- Evidence: 实际完整客户端夹具须等待Ready和按钮可用，并匹配collaborate回执；不把旧输入回执、无截图或不完整关房当成功。原始失败保留。
- Final freeze: 源码1216、Web站点10、权威904文件，协议10。r7/r8/r9/r10/r11历史保持独立，不发布公网，不复用真实用户测试资料。

- Final completed: 本机117/117完整通过；最终Web专项14/14，完整三套客户端均通过，18份清单SHA零差异。所有测试进程结束，Maker预览保持stopped。
