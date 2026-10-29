# 双人联机实施计划

> **For agentic workers:** Use superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** 将当前 Godot 游戏接入双人权威服务器，准备 Railway WSS 部署，保留单人及本机作品。
**Architecture:** 每房间独立 World2D，Godot 运行共享物理；每人独立控制器和战斗状态。WebSocket 传输有界 JSON，完整快照分块，Ready 后操作，20Hz 最新状态；持久卷独立保存世界和所有者凭据。
**Tech Stack:** Godot 4.6 GDScript、WebSocket、Python stdlib HTTP/WS 网关、Docker。
**Spec:** ZSCB/SPEC.md §§9–14（已批准设计与实施顺序）。

## Global Constraints
- 双人私人房间；每玩家独立草稿、武器、图纸、镜头。
- 服务端裁决移动、造物、伤害、编辑；实体稳定 ID、作者、版本；禁止全世界快照撤销。
- 3秒死亡重生、2秒保护、30秒重连；所有者退出保存关房；持久卷原子保存。
- 不覆盖真实本机作品；所有测试在副本与隔离用户目录执行。
- 不把本机测试视作异地 Railway 验收，云部署及付费动作待具体结果可审阅后确认。

## Review Focus
- 畸形和超量笔迹、非法数值、伪造身份与越权。
- 快照期间增量、迟到帧、删除实体、慢连接有界队列。
- 断线／重启／满房／不同房间隔离。
- 每人远离镜头时地形碰撞仍存在；同件实体只生成一次。
- 保存失败、不覆盖旧作品、客人不能载入世界、撤销不抹掉朋友进度。

### Task 1: 有界协议与独立云存档
**Files:** scripts/net/codec.gd, validation.gd, world_store.gd; tests/network_data_test.gd
**Interfaces:** Codec.encode(value)->String / decode(text)->Variant; Validation.object(value)->Dictionary {ok,error,object}; Validation.weapon(value)->Dictionary {ok,error,weapon}; WorldStore.new(directory); save(id,data)->Dictionary {ok,error}; load_world(id)->Dictionary {ok,error,data}; token()->String.
- [x] 写并运行失败测试：笔迹 round-trip、拒绝非有限/超量数据、武器重新推导、原子备份及失败保护。
- [x] 实现并运行通过测试。

### Task 2: WebSocket 服务器入口与部署包
**Files:** server/server.gd, gateway.py, Dockerfile, railway.json; tests/network_transport_test.py
**Interfaces:** Room.new(); room.configure(code,map_id,owner_token,store,world_id); room.join(token,name)->Dictionary; room.command(player_id,message)->Dictionary; room.disconnect(player_id); room.frame()->Dictionary; room.snapshot()->Dictionary; room.closed bool; server owns sockets and Ready handshake.
- [x] 实际 WebSocket/健康检查测试先失败，再实现传输、分块快照、心跳、队列上限、端口与单副本部署配置。
- [x] 导出可运行启动方式及错误状态。

### Task 3: 共享世界与独立角色
**Files:** scripts/net/room.gd, actor.gd; scripts/main.gd, knowledge_world.gd
**Interfaces:** room APIs above; Actor extends PaperCastleMain with lightweight ready and shared world refs; step_locomotion(delta,input) shared by offline and server.
- [x] 失败测试：双人移动、第三人拒绝、隔房、造物权限、去重、近战伤害/重生及断线输入归零。
- [x] 实现真实 Godot 物理、个人操作撤销与持久保存，运行通过。

### Task 4: 电脑客户端与房间界面
**Files:** scripts/net/session.gd, lobby.gd, remote_actor.gd; map_select.gd/main.gd hooks
- [x] 失败测试：两个真实客户端加入、Ready、创建实体只一次、装备同步、断线/保存提示。
- [x] 接入创建/加入/重连、独立镜头/图纸、远端角色/草稿、世界状态显示。

### Task 5: 回归与部署验证
**Files:** tests/run_network.py; docs/MULTIPLAYER_VALIDATION_2026-10-24.md; SPEC.md
- [x] 运行网络集成及现有核心回归、实际窗口检查。
- [x] 审查权限/存档/重连/拥塞边界，修复后复验。
- [x] 记录已验证与未验证范围，准备部署产物。
- [ ] Railway实际发布、Linux容器运行与异地双机：认证尚未恢复，明确保留未完成状态。

执行记录：46个行为测试脚本、12个传输测试通过；中世纪实际渲染与课本双客户端验证通过，见验收记录。原工程存在其他会话的未提交文件，所有改动留在当前工作目录，未创建提交或发布。
