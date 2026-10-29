# 结构连接 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. Preserve the user's direct execution authorization; no repeated design approval.

**Goal:** 让手绘部件通过固定连接或转轴组合成真实受力结构，并支持解除、破损、存档和权威联机。

**Architecture:** `structure_links.gd`拥有连接记录及PinJoint2D，部件保持独立刚体。固定使用两个分离的自由点约束锁定相对角，转轴自由旋转；连接锚点落在双方现存真实材料附近，不能以包围盒空洞或草稿连接。UI只提交动作；服务器校验双方作者、距离、生死和编辑锁。

**Tech Stack:** Godot4.6.3 / GDScript / 既有存档和WebSocket。

**Spec:** SPEC v0.42第13节授权第三阶段，细化为v0.43。Godot官方PinJoint2D/Joint2D文档。

## Global Constraints

- 保持原数字键、多笔确认、动态物理、笔迹、破损和试桥事件；不自动生成或冻结用户造物。
- 工具放在4移动／拆除内，默认仍为移动。固定、转轴、解除为显式子工具；Esc取消选点。
- 点两件相邻自己的部件建立连接，每端距角色12米内；两次选点间不超过0.5米，每端锚点离有效材料不超过0.25米。每对至多一连接，全世界最多128。
- 联机不增加共同编辑权限；不能连接／解除朋友的作品。客户端仅显示记录，不创建物理关节。
- 连接随当前地图存档；旧作品缺少字段兼容空连接。删除／砍掉锚点清除对应连接。移动已连接件明确拒绝，先解除，避免单件瞬移拉飞结构。
- 连接不消耗额外墨水、不收入单件图纸；部件本身仍按原规则生成与收藏。
- 新物理规则与消息使用协议8/r10本地候选；不改公网r7及历史r8/r9，不自动部署。

## Approaches

采用真实物理关节，能够做拼接桥、转动门板或杠杆。合并所有轮廓为一个刚体会丢失部件身份与转轴；直接冻结／每帧改坐标不符合真实物理。本阶段先固定与转轴，不引入马达、绳索或团队权限。

## Review Focus

- 空洞、已切掉材料、装饰笔画不能成为锚点。
- 存档非法或悬空引用须在改动当前世界前拒绝；旧档仍可读。
- 关节删除后恢复双方碰撞；不得遗留碰撞例外。
- 作者、距离、死亡、锁及重复编号都由权威检查，客户端不能自建物理关节。
- 窄屏真实触控按钮归属、切工具／失焦／面板取消未完成选点，原草稿保留。

### Task 1: 真实连接与生命周期

**Files:** new `scripts/structure_links.gd`, `tests/structure_links_test.gd`; modify `main.gd`, `paper_canvas.gd`.
**Interfaces:** `create(a:String,b:String,point:Vector2,kind:String)->Dictionary`, `remove(id:String)->Dictionary`, `snapshot()->Array`, `restore(records:Variant)->bool`, `step()->bool`, `linked(key:String)->bool`, `ensure_key(object:Dictionary)->String`.

- [x] 写并观察RED：模块不存在；固定受力保持相对角、转轴真实转动、间隙／空洞拒绝、删除／切锚断开。
- [x] 实现真实PinJoint2D与稳定部件键、材料检测、碰撞恢复和远区连通体活动范围。
- [x] 普通60Hz物理GREEN，不用路径坐标或额外冻结使测试通过。

### Task 2: 保存与权威同步

**Files:** `main.gd`, `save_store.gd`, `net/room.gd`, `net/session.gd`, `net/world_store.gd`, `net/codec.gd`, `web/prepare_client.py`; new state/network tests.
**Interfaces:** `world.connections:Array`; strict `valid_state(records,objects)` handles JSON or runtime objects; `structure_link` action connect/unlink; revision causes matched snapshot resync.

- [x] RED：JSON写盘往返、旧档、地图返回、非法引用原子拒绝；导入重新分配网络ID仍保留连接。
- [x] RED：作者／远处／死亡／锁／重发拒绝或去重，双方/晚加入一致、客户端无关节。
- [x] 实现并GREEN；保留撤销，连接／解除可撤销，已有连接物件移动拒绝，删除可撤销恢复连接。

### Task 3: 游戏入口与真实触控

**Files:** `toolbar.gd`, `main.gd`, `experience_panel.gd`; new UI/visual tests.
- [x] RED：实际按钮、两次点选建立／解除、不落墨、取消保留草稿、四尺寸可达。
- [x] 实现固定／转轴／解除子工具与锚点提示；GREEN及四尺寸渲染。

### Task 4: 验收与交付

- [x] 全量本机／Web、传输与实际双客户端；浏览器实际拼接或转动结构。
- [x] 独立只读审查并处理具体问题；新r10独立源码／Web／权威包与SHA清单。
- [x] SPEC、AGENTS、专项报告与证据一致；Maker预览保持停止，无云部署。

## Execution ledger

- 用户连续要求按既定顺序直接改进，沿用会话内实施。项目整棵未跟踪且共享，不提交／切分支；修改前备份`/tmp/paper-structure-original-20261026`，测试使用隔离副本和用户目录。
- 基线：1192运行文件与r9冻结0差异。现有103/103、Web113/113作为上阶段证据。
- Pre-flight: Task1稳定键供Task2存档引用；JSON锚点用独立数值字段，避免Vector2恢复差异；Task3只发动作，不写入权威记录。

- Ruling: 固定连接不用PinJoint2D角限位；普通60Hz复现位置数值爆炸，±0.001限位仍失败。改为两个相距0.6米的自由点约束，21项普通60Hz检查通过，保持独立动态刚体；依据Godot官方问题#88481。成本是每固定连接两个约束。
- Task1: complete — RED模块不存在、角限位失败均保留；最终21/21，含重力支撑、自由转动、双动态部件受冲量、锚点破损、无效恢复原子性及解除碰撞恢复。
- Task2: complete — 存档14/14、权威14/14。独立实测发现撤销能绕过距离，补RED并修复。实际两完整客户端100ms／256KiB/s通过；初次夹具在快照尚未ready时发命令失败，改为等待真实同步完成，不改产品状态。
- Task3: complete — 真实控件与指针22/22；四尺寸渲染及真实转轴重力运动。Task4已完成。

- Review fix pass: 两个独立确认P2和长链地面均补RED→GREEN；保存/snapshot清理递增revision，拆除撤销验证另一端权限、锁、距离，物理分块覆盖活动结构远端。独立复核活动26/26、撤销权限13/13、网络16/16，无剩余同级问题。
- Task4: complete — 审查后本机109/109、Web119/119；普通60Hz物理21、状态14、网络16、UI22、活动26、撤销权限13全部通过。传输15/15无跳过，Python2/2。
- 实际原生／Web双完整客户端100ms附加RTT与每方向256KiB/s通过；相同Web候选对战600ms／256KiB/s通过。浏览器鼠标手绘两部件、固定连接后送货成功，解除保留部件，转轴实际转动。
- Frozen: r10源码1201、Web10、权威896文件SHA一致；当前运行文件0差异。r7/r8/r9各来源与历史清单一致。所有产物仅本地，未更新公网。
- Test harness incident: Web夹具曾沿用旧本机“指尖”资料目录，两个角色共用profile。已用通用项目名替换隔离，并从WEB_RELEASE找匹配支持源；原目录不删除，测试前联机资料无法恢复，可能影响旧版上次联机记录。作品文件未写入，敏感事后副本只保存在本机临时目录，不打包。后续验证独立目录完成并清理。
- Evidence: docs/previews/structure-2026-10-26/。本轮浏览器与HTTP服务已关闭，Maker停止。保留本机工作区修改和r10候选，不创建提交／分支／PR。
