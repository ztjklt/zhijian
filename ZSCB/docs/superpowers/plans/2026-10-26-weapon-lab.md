# 武器试打 Implementation Plan

> Use superpowers:executing-plans inline. User already authorized direct execution in order.

**Goal:** 让玩家用真实武器试靶、比较方案、复制笔迹修改，再通过实际命中验证。
**Architecture:** 每人一个临时weapon_lab，显式布置、无实体推挤和墨弹。使用原真实剑模扫掠／最早弹丸接触；成绩由单人本机或联网权威产生。面板是个人操作与结果，靶可供双方看见，只有各自攻击与各自试靶交互。
**Tech:** Godot4.6.3/GDScript/WSS。Spec v0.43既定第四阶段，细化v0.44。

## Choices and constraints

- 三档布靶距离1.2／2.5／5米，位于人物朝向，当前位置安全才布置；不传客户端靶位置或成绩。每人一个，旧箭不能命中新一轮靶。
- 使用真实伤害、实际握点与笔迹最远距离、真实冷却；显示命中数、最近／平均／最高伤害与最远命中距离。未命中不能生成成绩，不把静态参数当实测伤害。
- 保留当前成绩为对照；更换几何／握点／类型分开统计。弹丸在发射／蓄力时绑定方案，换装备后不能记到新方案。
- 固定有界会话记录最多8个方案，保留对照一份；不写世界存档或本机图纸资料，不加资源奖励、DPS排行或长期经济。
- “复制回画布”保留原装备，复制完整路径；已有武器草稿不覆盖。仍走3握点→3类型→3装备，不直接替换形状、不自动装备。
- 单人／联机共用试靶与实测模块。客户端不自行记命中，权威检查生死、Ready、动作和距离；伙伴不能操作对方试靶／成绩。
- 世界不中断，开启面板不暂停另一人；面板本身隔离绘画／攻击。关闭后保留简短试打摘要，靶不挡普通人物／物件移动。
- 新试靶判定与消息使用协议9/r11独立本地候选；不改公网r7及r8/r9/r10历史包，不自动部署。
- 继续使用隔离测试副本和随机项目名，绝不重用旧本机资料目录；以WEB_RELEASE找到匹配支持源。

## Review focus

- 空挥、墙后、已取消攻击、同一挥击重复帧不记分；枪／箭都按统一最早碰撞排序。
- 蓄力／发射后换装备、移靶／清空、断线／死亡，不得错记新方案或新一轮。
- 导入画布不丢原装备、现有草稿或图纸；坐标与多笔相对形状保留。
- 客户端不能上传位置、分数、命中或替他人开启试靶；晚加入可看见靶，个人成绩独立。
- 桌面、窄横屏、竖屏、触控实际控件可达；UI事件不落墨、不抢摇杆，不泄露资料。

### Task1 真实试靶与统计
Files: new scripts/weapon_lab.gd, tests/weapon_lab_test.gd; paper_combat.gd/main.gd/paper_canvas.gd.
Interfaces: start(distance:float)->Dictionary, stop(), select(weapon), ticket()->Dictionary, hit(ticket,amount,contact,origin), keep()->Dictionary, reset(), snapshot()->Dictionary, receive(data), step(delta).
- [x] RED：模块／布靶／真实近战、弓枪命中；墙遮挡、空挥、去重、旧票与换武器归属。
- [x] 实现有界模块、原剑模／弹丸接线、真实布靶；GREEN。

### Task2 权威与个人试打
Files: net/actor.gd, room.gd, session.gd, codec.gd, Web adapter; new weapon_lab_network_test.gd.
- [x] RED：双方可见／各自成绩、权限、生死、非法位置成绩、重复请求、重连只读副本。
- [x] 实现weapon_lab动作及actor状态，不接受客户端成绩；GREEN。

### Task3 画布往返与界面
Files: new weapon_lab_panel.gd; main.gd/toolbar.gd/experience_panel.gd/touch_controls.gd; new weapon_lab_ui_test.gd/visual fixture.
- [x] RED：真实入口／控件、保留对照、复制完整笔迹再选握点、拒绝覆盖草稿、四尺寸输入隔离。
- [x] 实现面板、精简摘要与返回画布；GREEN及视觉验收。

### Task4 独立审查与成套验证
- [x] 独立只读审查；修复具体问题，保留RED证据。
- [x] 全套本机／Web、传输、双完整客户端实测与网页实际操作。
- [x] r11源码／Web／权威独立候选与SHA；SPEC／AGENTS／报告同步，预览保持停止，无部署。

## Execution ledger
- 主线整棵未跟踪且共享；沿用用户直接渐进实施授权，局部补丁，备份/tmp/paper-weapon-lab-original-20261026，不切分支／提交。
- r10基线1201文件0差异，上阶段109/109、119/119证据保留。
- Pre-flight：Task1票据只含代数与方案键，不把整件武器放进弹丸／网络帧；Task2自己模块与伙伴显示独立；Task3改稿只写个人草稿，不调用装备／服务器造物。

- Task1: core19项、真实角色5类15项通过；新增占位64层角色RED后纳入安全查询。旧票只禁止记分不足以阻止新靶吞旧弹，补RED并在接触收集前验证票据。
- Ruling: 实际鼠标瞄准测试近靶的弓枪失败，根因出手点比人物高0.43米。修正Main.attack从出手点算方向，触控默认仍水平；真实角色五类15/15通过，冷却／伤害／墨水不改。
- Task2: 15项通过；增补替换世界撤下临时试靶且保留会话对照的RED并修复；inspect动作读取真实装备，使未开靶面板也能显示当前方案。
- Task3: 首次布局沿用0宽换行造成1345像素旧最小高度，已复现并按容器宽度落定后重新布局。34项通过，含完整笔迹、原装备、草稿拒绝覆盖、类型默认、填充偏好与4尺寸控件／触控。
- 记录只为临时会话，不写本机联机profile或世界；所有验证使用已修复的随机项目名隔离，不复用旧版资料目录。

- Review: 独立审查确认地图快捷键漏过试打面板。真实键盘事件 RED 10项6失败；两个地图改用 personal_overlay_open 后10项全过，审查者独立复测确认无剩余阻塞。
- Browser: 真实浏览器完整手绘火枪、试靶28、保留对照、复制完整笔迹、重选握点改弓、试靶24；截图 browser-comparison.png。
- Final freeze: r11源码1210文件、Web10站点文件、权威900文件，三者协议9，r7/r8/r9/r10的15份相关清单SHA无差异。
- Additional probe: 权威包配原生客户端的600ms额外RTT对战探测未完成致死序列；失败原样保留，不计入已通过范围。此前Web成套600ms对战通过；本阶段试打双完整客户端100ms/256KiB/s通过。

- Final results: 最终Web124/124；本机首跑113/114，唯一复杂武器性能项原测试复跑16组全过（最高12.712ms），不称单次114/114。传输15/15、Python2/2。
- Supplemental results: 最终Web600ms对战复跑失败于火枪冷却后弓箭命中；r10原生600ms基线失败于接近对手。原始失败保留，不声称高延迟对战稳定通过，不改测试阈值或取消步骤。
- Completed: 最终源码／Web／权威已冻结，独立审查通过、浏览器实际操作与双客户端试打通过。未部署；下一阶段为双人共同创造，高延迟对战仍有已记录未通过项。
