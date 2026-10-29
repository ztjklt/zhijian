class_name PaperNetRoom
extends SubViewport
## Each room owns a World2D. No physics bodies or identities cross rooms.
const Actor := preload("res://scripts/net/actor.gd")
const Validation := preload("res://scripts/net/validation.gd")
const Store := preload("res://scripts/net/world_store.gd")
const Codec := preload("res://scripts/net/codec.gd")
var code := ""
var map_id := "paper"
var owner_token := ""
var owner_id := ""
var world_id := ""
var epoch := ""
var store: RefCounted
var world: PaperCastleMain
var actors: Dictionary = {}
var member_credentials: Array = []
var next_id := 1
var revision := 1
var tick := 0
var closed := false
var close_reason := ""
var error := ""
var save_clock := 0.0
var locks: Dictionary = {}
var cooperation = preload("res://scripts/net/cooperation.gd").new(self)
var last_save_error := ""
var event_seq := 0
var combat_events: Array = []
var event_clock := 0.0

func configure(invite: String, map: String, credential: String, storage: RefCounted, id: String) -> void:
	code = invite
	map_id = map
	owner_token = credential
	store = storage
	world_id = id
	epoch = Store.token()
	owner_id = Store.token()

func _ready() -> void:
	world_2d = World2D.new()
	size = Vector2i(1280, 720)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	world = PaperCastleMain.new()
	world.network_headless = true
	world.world_kind = map_id
	add_child(world)
	world.feedback = preload("res://scripts/net/feedback.gd").new()
	world.feedback.room = self
	world.add_child(world.feedback)
	var loaded: Dictionary = store.load_world(world_id)
	if loaded.ok:
		var data: Dictionary = loaded.data
		if data.owner_token != owner_token:
			error = "世界所有者凭据不正确"
			closed = true
			return
		owner_id = data.get("owner_id", owner_id)
		member_credentials = data.get("member_credentials",[])
		next_id = int(data.get("next_id", 1))
		map_id = data.map_id
		if world.world_kind != map_id: world.select_world(map_id)
		world.objects = data.objects
		var details: Dictionary = data.get("world", {})
		if world.medieval_world != null:
			world.migrate_medieval_objects(world.objects, int(details.get("terrain_version",1)))
		world._rebuild_objects()
		world.structure_links.restore(details.get("connections", []))
		if world.medieval_world != null: world.medieval_world.restore_state(details.get("entities", []), int(details.get("terrain_version",1)), int(details.get("content_version",1)),details.get("bridge_trial",{}))
		if world.knowledge_world != null: world.knowledge_world.restore_state(details)
	elif not loaded.get("not_found", false) and FileAccess.file_exists(store.directory.path_join(world_id + ".json")):
		error = "存档损坏，已保留原文件"
		closed = true

func join(token: String, name_text: String) -> Dictionary:
	if closed: return {"ok":false,"error":error if error != "" else "房间已结束"}
	var saved_author := ""
	if token != "":
		for actor in actors.values():
			if actor.credential != token: continue
			if actor.connected: return {"ok":false,"error":"该玩家已经连接"}
			if actor.disconnect_age >= 30: return {"ok":false,"error":"重连席位已过期"}
			actor.connected = true
			actor.ready_to_play = false
			actor.disconnect_age = 0
			return _identity(actor)
		for member in member_credentials:
			if member.token==token: saved_author=member.id; break
		if saved_author=="" and token!=owner_token: return {"ok":false,"error":"重连凭据无效"}
		if token==owner_token and not actors.is_empty(): return {"ok":false,"error":"创建者席位已存在"}
	if actors.size() >= 2: return {"ok":false,"error":"房间已满，最多两人"}
	if not actors.is_empty() and saved_author=="" and member_credentials.size()>=256: return {"ok":false,"error":"该世界的朋友身份存储已满"}
	var desired_x:=3.0+actors.size()*1.4 if map_id=="medieval-v1" else 9.0+actors.size()*1.4 if map_id in ["knowledge-v1","nature-v1"] else -5.6+actors.size()*1.4
	var spawn= safe_spawn(desired_x)
	if spawn==null: return _failure("出生区域被占用，请清理后重试")
	var actor = Actor.new()
	actor.room = self
	actor.player_id = owner_id if actors.is_empty() else saved_author if saved_author!="" else Store.token()
	actor.credential = owner_token if actors.is_empty() else token if saved_author!="" else Store.token()
	if not actors.is_empty() and saved_author=="": member_credentials.append({"id":actor.player_id,"token":actor.credential})
	actor.display_name = name_text.strip_edges().left(24)
	if actor.display_name == "": actor.display_name = "画家" + str(actors.size()+1)
	actor.connected = true
	add_child(actor)
	actor.world_kind = map_id
	actor.knowledge_world = world.knowledge_world
	actor.medieval_world = world.medieval_world
	actor.objects = world.objects
	actor.object_nodes = world.object_nodes
	actor.player.position = spawn
	actor.last_player_x = actor.player.position.x
	actors[actor.player_id] = actor
	world.network_players.append(actor.player)
	return _identity(actor)

func safe_spawn(desired_x: float) -> Variant:
	var query:=PhysicsShapeQueryParameters2D.new()
	var circle:=CircleShape2D.new(); circle.radius=.30
	query.shape=circle; query.collision_mask=9; query.margin=.015
	for attempt in 96:
		var column:=attempt/6
		var offset_x:=0.0 if column==0 else float((column+1)/2)*.75*(1 if column%2==1 else -1)
		var base:Vector2=world.terrain_spawn(desired_x+offset_x)
		var candidate:=base+Vector2(0,[0.0,.7,1.4,2.8,4.2,6.3][attempt%6])
		query.transform=Transform2D(0,candidate)
		if world.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return candidate
	return null

func _identity(actor) -> Dictionary:
	return {"ok":true,"error":"","player_id":actor.player_id,"token":actor.credential,"owner":actor.player_id==owner_id,"next_seq":maxi(actor.command_seq,actor.input_seq)}

func ready(player_id: String) -> void:
	if not actors.has(player_id): return
	var actor = actors[player_id]
	if actor.ready_to_play: return
	PhysicsServer2D.space_set_active(world_2d.space,true)
	actor.ready_to_play = true
	actor.set_active(actor.connected and actor.dead_time <= 0)

func disconnect_player(player_id: String) -> void:
	if not actors.has(player_id): return
	var actor = actors[player_id]
	_release_carried(actor)
	actor.connected = false
	actor.ready_to_play = false
	actor.disconnect_age = 0
	actor.preview.clear()
	actor.set_active(false)
	_release_locks(player_id)
	cooperation.clear()

func _release_locks(player_id: String) -> void:
	for id in locks.keys():
		if locks[id].player == player_id: locks.erase(id)

func carry_position(actor) -> Vector2:
	return actor.player.position + Vector2(float(actor.facing) * .82, -.72)

func _carry_index(actor) -> int:
	for index in world.objects.size():
		if str(world.objects[index].get("id", "")) == actor.carried_id: return index
	return -1

func _carry_step(actor) -> void:
	if actor.carried_id == "": return
	if locks.has(actor.carried_id): locks[actor.carried_id].time = 60.0
	var index := _carry_index(actor)
	if index < 0 or index >= world.object_nodes.size():
		_release_carried(actor)
		return
	var body: RigidBody2D = world.object_nodes[index]
	body.freeze = true; body.collision_layer = 0; body.collision_mask = 0
	var target := carry_position(actor)
	body.position = target
	body.rotation = float(world.objects[index].get("angle", 0.0))
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0
	world.objects[index].x = target.x
	world.objects[index].y = target.y

func _release_carried(actor) -> void:
	if actor.carried_id == "": return
	var index := _carry_index(actor)
	if index >= 0 and index < world.object_nodes.size():
		var body: RigidBody2D = world.object_nodes[index]
		var candidate: Dictionary = world.objects[index].duplicate(true)
		candidate.x = body.position.x; candidate.y = body.position.y
		var placement := PaperCarryPlacement.resolve(world, candidate)
		if placement.ok:
			world.objects[index].x = placement.object.x; world.objects[index].y = placement.object.y
			body.position = Vector2(placement.object.x, placement.object.y)
		body.collision_layer = actor.carried_layer
		body.collision_mask = actor.carried_mask
		body.freeze = actor.carried_freeze
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0
		world.objects[index].version = int(world.objects[index].get("version", 1)) + 1
	locks.erase(actor.carried_id)
	actor.carried_id = ""

func _carry_probe(actor, candidate: Dictionary) -> bool:
	if Vector2(candidate.x, candidate.y).distance_to(actor.player.position) > 12: return false
	var placement := PaperCarryPlacement.resolve(world, candidate)
	if not placement.ok: return false
	candidate.x = placement.object.x; candidate.y = placement.object.y
	return true

func _carry(actor, msg: Dictionary) -> Dictionary:
	var action := str(msg.get("action", ""))
	if action == "pick":
		if actor.carried_id != "": return _failure("已经拿着一个部件")
		var index := _object_index(str(msg.get("id", "")))
		if index < 0: return _failure("物件已经不存在")
		var object: Dictionary = world.objects[index]
		if not cooperation.can_use(actor, object): return _failure("没有权限拿起这个部件")
		if int(msg.get("version", -1)) != int(object.version): return _failure("物件状态已变化，请重新选择")
		if Vector2(object.x, object.y).distance_to(actor.player.position) > 12: return _failure("请走近部件，在12米内拿起")
		if world.structure_links.linked(object.get("structure_id", "")): return _failure("部件已有连接，请先解除连接")
		if locks.has(object.id) and locks[object.id].player != actor.player_id: return _failure("物件正在被编辑")
		var body: RigidBody2D = world.object_nodes[index]
		actor.carried_id = str(object.id)
		actor.carried_layer = body.collision_layer
		actor.carried_mask = body.collision_mask
		actor.carried_freeze = body.freeze
		body.freeze = true; body.collision_layer = 0; body.collision_mask = 0
		locks[object.id] = {"player": actor.player_id, "time": 60.0, "carry": true}
		_carry_step(actor)
		return {"ok": true, "error": "", "carried_id": actor.carried_id, "id": actor.carried_id, "version": object.version}
	if action == "drop":
		if actor.carried_id == "": return _failure("当前没有携带部件")
		if str(msg.get("id", "")) != actor.carried_id: return _failure("携带状态已变化，请重新选择")
		var index := _carry_index(actor)
		if index < 0: _release_carried(actor); return _failure("物件已经不存在")
		var body: RigidBody2D = world.object_nodes[index]
		var candidate: Dictionary = world.objects[index].duplicate(true)
		candidate.x = body.position.x + float(actor.facing) * .42; candidate.y = body.position.y
		if not _carry_probe(actor, candidate): return _failure("这里没有安全落点，仍在携带中")
		body.position = Vector2(candidate.x, candidate.y)
		body.collision_layer = actor.carried_layer; body.collision_mask = actor.carried_mask
		body.freeze = actor.carried_freeze; body.linear_velocity = Vector2.ZERO; body.angular_velocity = 0
		world.objects[index].x = candidate.x; world.objects[index].y = candidate.y; world.objects[index].version += 1
		locks.erase(actor.carried_id)
		actor.carried_id = ""
		return {"ok": true, "error": "", "carried_id": "", "id": candidate.id, "version": world.objects[index].version}
	return _failure("携物动作无效")

func _physics_process(delta: float) -> void:
	if closed or world == null: return
	tick += 1
	event_clock += delta
	combat_events = combat_events.filter(func(event): return event_clock - event.at < 2.0)
	var old_health := {}
	for object in world.objects: old_health[object.id] = object.get("health",120.0)
	var old_count := world.objects.size()
	var active := false
	for id in actors.keys():
		var actor = actors[id]
		actor.network_peers=actors.values()
		actor.simulate(delta)
		if actor.dead_time > 0: _release_carried(actor)
		if actor.connected and actor.ready_to_play: active = true
		if not actor.connected and actor.disconnect_age >= 30:
			if id == owner_id:
				close_room("创建者断线超过30秒，房间已保存并结束")
				return
			world.network_players.erase(actor.player)
			_release_locks(id)
			actors.erase(id)
			actor.queue_free()
	for id in locks.keys():
		locks[id].time -= delta
		if locks[id].time <= 0: locks.erase(id)
	if not active:
		PhysicsServer2D.space_set_active(world_2d.space,false)
		return
	PhysicsServer2D.space_set_active(world_2d.space,true)
	if world.sync_objects(): revision += 1
	world._update_world_chunks()
	for actor in actors.values(): _carry_step(actor)
	if world.medieval_world != null: world.medieval_world.step(delta)
	_resolve_players(delta)
	_step_shared_arrows(delta)
	if old_count != world.objects.size(): revision += 1
	for object in world.objects:
		if old_health.get(object.id,0) != object.get("health",120.0): object.version += 1
	for actor in actors.values():
		actor.objects = world.objects
		actor.object_nodes = world.object_nodes
		if actor.dead_time > 0: _release_locks(actor.player_id)
	save_clock += delta
	if save_clock >= 30:
		save_clock = 0
		_save()

func _resolve_players(delta: float) -> void:
	for attacker in actors.values():
		if not attacker.connected or not attacker.ready_to_play or attacker.dead_time > 0: continue
		var battle = attacker.combat
		if not battle.blade_active(): continue
		var wall: Dictionary = battle._blade_structure(battle.previous_player_paths,battle.player_paths,battle._held_blade_origin())
		for target in actors.values():
			if attacker == target or not target.connected or not target.ready_to_play or target.dead_time > 0: continue
			var key: String = "player_" + target.player_id
			if battle.hit_ids.has(key): continue
			if target.combat.blade_active():
				var clash := PaperBladeSweep.blade_contact(battle.previous_player_paths,battle.player_paths,target.combat.previous_player_paths,target.combat.player_paths)
				var other_wall: Dictionary = target.combat._blade_structure(target.combat.previous_player_paths,target.combat.player_paths,target.combat._held_blade_origin())
				if not clash.is_empty() and wall.get("time",INF)>clash.time and other_wall.get("time",INF)>clash.time:
					battle.clash(clash.position)
					target.combat.clash(clash.position)
					battle.hit_ids[key] = true
					continue
			var hit := PaperBladeSweep.circle_contact(battle.previous_player_paths,battle.player_paths,target.player.position+Vector2(0,.2),.25 if target.crouching else .33)
			if hit.is_empty() or wall.get("time",INF) <= hit.time: continue
			battle.hit_ids[key] = true
			var damage := PaperWeaponTypes.damage(battle.swing_weapon,PaperBladeSweep.motion_distance(battle.previous_player_paths,battle.player_paths)/maxf(delta,.001))
			target.hit(damage,battle.swing_direction,PaperWeaponTypes.impulse(battle.swing_weapon),hit.position,PaperWeaponTypes.kind(battle.swing_weapon))

func command(player_id: String, message: Dictionary) -> Dictionary:
	if closed or not actors.has(player_id): return {"ok":false,"error":"房间已结束"}
	var actor = actors[player_id]
	var op := str(message.get("op", ""))
	var raw_seq = message.get("seq",0)
	if not (raw_seq is float or raw_seq is int) or not is_finite(float(raw_seq)) or float(raw_seq)<1 or float(raw_seq)>9007199254740991 or floorf(float(raw_seq))!=float(raw_seq): return _failure("操作编号无效")
	var seq := int(raw_seq)
	if op == "input":
		if seq <= actor.input_seq: return {"ok":true,"error":""}
		actor.input_seq = seq
		if not actor.connected or not actor.ready_to_play or actor.dead_time>0: return {"ok":false,"error":"等待出生或同步"}
		actor.input_age = 0
		if bool(message.get("blocked",false)):
			actor.block_controls()
			return _success()
		actor.controls_blocked = false
		actor.combat_blocked = bool(message.get("combat_blocked",false))
		if actor.combat_blocked: actor.combat.cancel_draw()
		var jump := bool(message.get("jump",false))
		actor.pending_jump = actor.pending_jump or (jump and not actor.jump_down)
		actor.jump_down = jump
		actor.input_age = 0
		actor.input_state = {}
		for key in ["left","right","up","down"]: actor.input_state[key] = bool(message.get(key,false))
		return {"ok":true,"error":""}
	if actor.results.has(seq): return actor.results[seq]
	if seq <= actor.command_seq: return {"ok":false,"error":"过期的操作"}
	actor.command_seq = seq
	var result: Dictionary
	if not actor.connected or not actor.ready_to_play or actor.dead_time>0:
		result = {"ok":false,"error":"等待出生或同步"}
	else:
		result = _apply(actor, op, message)
	result.op = op
	actor.results[seq] = result
	while actor.results.size()>64: actor.results.erase(actor.results.keys().front())
	return result

func _apply(actor, op: String, msg: Dictionary) -> Dictionary:
	match op:
		"collaborate": return cooperation.apply(actor,msg)
		"carry": return _carry(actor, msg)
		"weapon_lab":
			for field in ["position","score","hits","target","player_id"]:
				if msg.has(field):return _failure("试靶位置和成绩由服务器决定")
			var action = msg.get("action", "")
			var result: Dictionary = _failure("不支持的试打动作")
			match action:
				"inspect":actor.weapon_lab.select(actor.weapon_lab.effective_weapon());result=_success()
				"start":
					var distance = msg.get("distance",1.2)
					if not Validation._number(distance,5):return _failure("试靶距离无效")
					result = actor.weapon_lab.start(float(distance))
				"stop":actor.weapon_lab.stop();result=_success()
				"reset":actor.weapon_lab.reset();result=_success()
				"keep":result=actor.weapon_lab.keep()
			result.action = action
			return result
		"structure_link":
			return _structure_link(actor, msg)
		"bridge_trial":
			if world.medieval_world == null: return _failure("磨坊试桥位于中世纪地图")
			if actor.player.position.distance_to(Vector2(133.5,5.2)) > 12: return _failure("请走近磨坊渡口的试桥台")
			var action = msg.get("action","")
			if action not in ["prepare","start"]: return _failure("试桥只接受布置或投放动作")
			return world.medieval_world.bridge_trial.call(action)
		"spawn":
			if world.objects.size()>=600: return _failure("纸面实体已满")
			var checked := Validation.object(msg.get("object"))
			if not checked.ok: return _failure(checked.error)
			var object: Dictionary = checked.object
			var ink_cost: float = PaperInkReserve.cost(object)
			if not actor.ink.can_spend(ink_cost): return _failure("墨水不足，需要%d，当前%d；草稿已保留" % [ink_cost, actor.ink.amount])
			var total_points := 0
			for record in world.objects + [object]:
				for path in record.paths: total_points += path.points.size()
			if total_points > Store.MAX_WORLD_POINTS: return _failure("房间笔迹容量已满，请先拆除一些作品")
			object.dynamic = true
			var body = actor._drop_candidate(object)
			if body == null: return _failure("超出12米或没有安全空位；草稿已保留")
			object.id = str(next_id); next_id += 1
			object.author = actor.player_id
			object.version = 1
			object.health = 120.0; object.max_health = 120.0
			actor.ink.spend(ink_cost)
			world.objects.append(object)
			world.object_nodes.append(world._attach_body(body,object))
			for person in actors.values():
				if object.kind=="ladder": body.add_collision_exception_with(person.player)
			actor.history.append({"op":"spawn","id":object.id,"version":1})
			_trim_history(actor)
			revision += 1
			return {"ok":true,"error":"","id":object.id,"object":object,"revision":revision}
		"equip":
			if msg.get("weapon") is Dictionary and msg.weapon.is_empty():
				actor.equipped_weapon = {}; actor.equipment_version += 1
				return {"ok":true,"error":"","weapon":{}}
			var checked := Validation.weapon(msg.get("weapon"))
			if not checked.ok: return _failure(checked.error)
			if actor.equipped_weapon != checked.weapon and not actor.ink.spend(PaperInkReserve.cost(checked.weapon)):
				return _failure("墨水不足，原武器和草稿已保留")
			actor.equipped_weapon = checked.weapon
			actor.combat.bow_equipped = false
			actor.equipment_version += 1
			actor.combat.cancel_draw()
			return {"ok":true,"error":"","weapon":actor.equipped_weapon}
		"attack":
			if actor.controls_blocked or actor.combat_blocked: return _failure("操作已暂停，请关闭个人面板或返回游戏窗口")
			var direction = msg.get("direction",Vector2(actor.facing,0))
			if not direction is Vector2 or not direction.is_finite(): return _failure("瞄准数据无效")
			actor.combat.invulnerable = 0
			var previous_cooldown: float = actor.combat.cooldown
			actor.combat.attack(direction)
			return {"ok":true,"error":"","attack_started":previous_cooldown <= 0 and actor.combat.cooldown > 0}
		"bow":
			actor.combat.toggle_bow()
			return _success()
		"preview":
			var paths = msg.get("paths",[])
			if not paths is Array or paths.size()>128: return _failure("预览过大")
			var count := 0
			for path in paths:
				if not path is Dictionary or not path.get("points") is Array: return _failure("预览无效")
				for p in path.points:
					count += 1
					if count>512 or not p is Vector2 or not p.is_finite() or p.distance_to(actor.player.position)>24: return _failure("预览超出范围")
			actor.preview = paths
			return _success()
		"lock", "move", "delete":
			return _edit(actor,op,msg)
		"undo":
			return _undo(actor)
		"upload_begin", "upload_chunk", "upload_commit":
			return _upload(actor,op,msg)
		"import":
			return _import_world(actor,msg.get("data"))
		"save":
			if actor.player_id!=owner_id: return _failure("只有创建者能保存房间世界")
			return _save()
		"leave":
			if actor.player_id==owner_id: return close_room("创建者结束了房间，世界已保存")
			disconnect_player(actor.player_id)
			actor.disconnect_age = 30
			return _success()
		"respawn":
			actor.player.reset_movement()
			var spawn=safe_spawn(actor.player.position.x)
			if spawn==null: return _failure("附近没有安全落点")
			actor.movement_reset += 1
			actor.player.position = spawn
			PhysicsServer2D.body_set_state(actor.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,actor.player.position))
			actor.player.linear_velocity=Vector2.ZERO
			return _success()
	return _failure("不支持的联机操作")

func _upload(actor, op: String, msg: Dictionary) -> Dictionary:
	if actor.player_id!=owner_id: return _failure("只有创建者能导入作品")
	if op=="upload_begin":
		var count = msg.get("chunks",0)
		if not (count is float or count is int) or int(count)<1 or int(count)>2048: return _failure("导入过大")
		actor.upload={"chunks":int(count),"parts":{},"bytes":0}
		actor.upload_age=0
		return _success()
	if actor.upload.is_empty(): return _failure("导入已过期，请重新读取作品")
	if op=="upload_chunk":
		var index_value = msg.get("index",-1)
		var text = msg.get("data")
		if not (index_value is float or index_value is int) or not text is String: return _failure("导入分块无效")
		var index := int(index_value)
		if index<0 or index>=actor.upload.chunks or text.length()>16384: return _failure("导入分块无效")
		if not actor.upload.parts.has(index): actor.upload.bytes+=text.to_utf8_buffer().size()
		if actor.upload.bytes>16*1024*1024: actor.upload.clear(); return _failure("导入超过容量")
		actor.upload.parts[index]=text
		return _success()
	if actor.upload.parts.size()!=actor.upload.chunks: actor.upload.clear(); return _failure("导入分块不完整，原世界未改变")
	var text:=""
	for index in actor.upload.chunks: text+=actor.upload.parts[index]
	actor.upload.clear()
	return _import_world(actor,Codec.decode(text))

func _import_world(actor, data: Variant) -> Dictionary:
	if actor.player_id!=owner_id: return _failure("只有创建者能导入作品")
	if not data is Dictionary or not data.get("objects") is Array or data.objects.size()>600 or not data.get("world") is Dictionary: return _failure("作品无效，原世界未改变")
	if data.world.get("id", "paper") != map_id: return _failure("请在相同地图的房间导入作品，原世界未改变")
	var imported: Array=[]
	var points:=0
	var pending_next:=next_id
	for entry in data.objects:
		var checked:=Validation.object(entry)
		if not checked.ok: return _failure(checked.error)
		var object:Dictionary=checked.object
		if entry.has("structure_id"): object.structure_id = entry.structure_id
		if entry.has("damage_cuts"):
			if not PaperObjectDamage.valid_cuts(entry.damage_cuts) or not Validation._number(entry.get("health",120),120) or float(entry.get("health",120))<=0:return _failure("作品破损状态无效")
			object.damage_cuts=entry.damage_cuts.duplicate(true)
			object.health=float(entry.get("health",120))
		for path in object.paths: points+=path.points.size()
		if points>Store.MAX_WORLD_POINTS: return _failure("作品笔迹超出房间容量")
		object.id=str(pending_next); pending_next+=1
		object.author=owner_id; object.version=1
		imported.append(object)
	if world.medieval_world!=null and not MedievalWorld.validate_snapshot(data.world): return _failure("中世纪作品状态或版本无效，原世界未改变")
	var details:Dictionary=data.world.duplicate(true)
	if not preload("res://scripts/structure_links.gd").valid_state(details.get("connections", []), imported): return _failure("结构连接无效，原世界未改变")
	# Persist the replacement before touching the live world. A failed write leaves
	# the original room and previous valid snapshot intact.
	var saved:Dictionary=store.save(world_id,{"map_id":map_id,"owner_token":owner_token,"owner_id":owner_id,"member_credentials":member_credentials,"next_id":pending_next,"paper":world.paper,"objects":imported,"world":details})
	if not saved.ok: return saved
	world.objects=imported
	if world.medieval_world!=null: world.migrate_medieval_objects(world.objects, int(details.get("terrain_version",1)))
	world._rebuild_objects()
	world.structure_links.restore(details.get("connections", []))
	if world.medieval_world!=null: world.medieval_world.restore_state(details.get("entities",[]),int(details.get("terrain_version",1)),int(details.get("content_version",1)),details.get("bridge_trial",{}))
	if world.knowledge_world!=null: world.knowledge_world.restore_state(details)
	for person in actors.values():
		person.objects=world.objects; person.object_nodes=world.object_nodes
		person.history.clear(); person.combat.cancel_draw()
		person.weapon_lab.stop()
	locks.clear()
	cooperation.clear()
	next_id=pending_next
	epoch=Store.token()
	combat_events.clear()
	revision+=1
	return {"ok":true,"error":"","op":"import","count":imported.size()}

func _edit(actor, op: String, msg: Dictionary) -> Dictionary:
	var index := _object_index(str(msg.get("id","")))
	if index<0: return _failure("物件已经不存在")
	var object: Dictionary = world.objects[index]
	if (op=="delete" and object.author!=actor.player_id) or not cooperation.can_use(actor,object): return _failure("只能搬动自己或作者已开放的部件；拆除仍归作者")
	if int(msg.get("version",-1))!=int(object.version): return _failure("物件状态已变化，请重新选择")
	if Vector2(object.x,object.y).distance_to(actor.player.position)>12: return _failure("超出12米编辑范围")
	if locks.has(object.id) and locks[object.id].player!=actor.player_id: return _failure("物件正在被编辑")
	if op != "delete" and world.structure_links.linked(object.get("structure_id", "")): return _failure("部件已有连接，先解除连接再移动")
	if op=="lock": locks[object.id]={"player":actor.player_id,"time":5.0}; return _success()
	var before: Dictionary = object.duplicate(true)
	if op=="delete":
		before.saved_connections = world.structure_links.snapshot().filter(func(link): return object.get("structure_id", "") in [link.a,link.b])
		_remove(index)
		before.saved_versions={}
		for link in before.saved_connections:
			for key in [link.a,link.b]:
				var survivor:Dictionary=world.structure_links.object(key)
				if not survivor.is_empty():before.saved_versions[survivor.id]=survivor.version
		actor.history.append({"op":"delete","object":before})
	else:
		if not locks.has(object.id): return _failure("请重新选择物件")
		var position_value = msg.get("position")
		if not position_value is Vector2 or not position_value.is_finite(): return _failure("位置无效")
		var candidate := before.duplicate(true)
		candidate.x=position_value.x; candidate.y=position_value.y
		var original: RigidBody2D = world.object_nodes[index]
		var previous_layer := original.collision_layer
		original.collision_layer=0
		var body = actor._drop_candidate(candidate)
		original.collision_layer=previous_layer
		if body==null: return _failure("新位置没有安全空位")
		body.free()
		object.x=candidate.x; object.y=candidate.y; object.version+=1
		original.position=Vector2(object.x,object.y)
		PhysicsServer2D.body_set_state(original.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(float(object.get("angle",0)),original.position))
		original.linear_velocity=Vector2.ZERO; original.angular_velocity=0
		actor.history.append({"op":"move","object":before,"version":object.version})
	locks.erase(before.id)
	_trim_history(actor)
	revision+=1
	return _success()

func _undo(actor) -> Dictionary:
	if actor.history.is_empty(): return _failure("没有可撤销的联机操作")
	var entry: Dictionary = actor.history.pop_back()
	if entry.op in ["link_add", "link_remove"]:
		for key in [entry.link.a, entry.link.b]:
			var object: Dictionary = world.structure_links.object(key)
			if object.is_empty() or not cooperation.can_use(actor,object): return _failure("原部件不存在或作者已撤回协作")
			if entry.get("versions",{}).get(object.id,-1)!=object.version:return _failure("部件已有后来改动，不能撤销旧连接操作")
			if Vector2(object.x,object.y).distance_to(actor.player.position)>12: return _failure("超出12米连接范围")
			if locks.has(object.id): return _failure("部件正在被编辑")
		var result: Dictionary
		if entry.op == "link_add": result = world.structure_links.remove(entry.link.id)
		else: result = {"ok":world.structure_links.restore(world.structure_links.snapshot()+[entry.link]), "error":"原连接位置已变化，不能撤销"}
		if result.ok:
			cooperation.touch([entry.link.a,entry.link.b]);revision += 1
		return result
	var id: String = entry.get("id",entry.get("object",{}).get("id",""))
	var index := _object_index(id)
	if entry.op in ["spawn","move"]:
		if index<0 or world.objects[index].version!=entry.version or world.objects[index].health<120: return _failure("物件已受损或变化，不能撤销")
		var current:Dictionary=world.objects[index]
		if not cooperation.can_use(actor,current) or (entry.op=="spawn" and current.author!=actor.player_id):return _failure("作者已撤回协作，不能撤销")
		if Vector2(current.x,current.y).distance_to(actor.player.position)>12:return _failure("超出12米撤销范围")
		if locks.has(current.id):return _failure("部件正在被编辑")
		if entry.op=="spawn": _remove(index)
		else:
			var original: Dictionary = entry.object
			if world.structure_links.linked(original.get("structure_id", "")): return _failure("部件已有连接，先解除再撤销移动")
			var body: RigidBody2D = world.object_nodes[index]
			var layer := body.collision_layer
			body.collision_layer=0
			var candidate = actor._drop_candidate(original)
			body.collision_layer=layer
			if candidate==null: return _failure("原位置已被占用，不能撤销")
			candidate.free()
			original.version=world.objects[index].version+1
			world.objects[index]=original
			body.data=original; body.position=Vector2(original.x,original.y)
			PhysicsServer2D.body_set_state(body.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(float(original.get("angle",0)),body.position))
	else:
		if index>=0 or entry.object.health<120: return _failure("物件已受损或变化，不能撤销")
		var original: Dictionary = entry.object
		var saved_connections: Array = original.get("saved_connections", [])
		var saved_versions:Dictionary=original.get("saved_versions",{})
		original.erase("saved_connections")
		original.erase("saved_versions")
		for link in saved_connections:
			for key in [link.a, link.b]:
				var endpoint: Dictionary = original if key == original.get("structure_id", "") else world.structure_links.object(key)
				if endpoint.is_empty() or not cooperation.can_use(actor,endpoint): return _failure("连接另一端已不存在或作者已撤回协作")
				if endpoint!=original and saved_versions.get(endpoint.id,-1)!=endpoint.version:return _failure("连接另一端已有后来改动，不能撤销旧拆除")
				if Vector2(endpoint.x,endpoint.y).distance_to(actor.player.position)>12: return _failure("连接另一端超出12米范围")
				if locks.has(endpoint.id): return _failure("连接另一端正在被编辑")
		var body = actor._drop_candidate(original)
		if body==null: return _failure("原位置已被占用，不能撤销")
		if not preload("res://scripts/structure_links.gd").valid_state(world.structure_links.snapshot()+saved_connections,world.objects+[original]):
			body.free()
			return _failure("原连接位置已变化，不能撤销拆除")
		original.version+=1
		world.objects.append(original)
		world.object_nodes.append(world._attach_body(body,original))
		world.structure_links.restore(world.structure_links.snapshot()+saved_connections)
		for link in saved_connections:cooperation.touch([link.a,link.b])
	revision+=1
	return _success()

func _remove(index: int) -> void:
	for actor in actors.values():
		if actor.carried_id == world.objects[index].id: actor.carried_id = ""
	var key:String=world.objects[index].get("structure_id","")
	for link in world.structure_links.records:
		if key in [link.a,link.b]:cooperation.touch([link.a,link.b])
	cooperation.remove(world.objects[index].id)
	locks.erase(world.objects[index].id)
	world.object_nodes[index].queue_free()
	world.object_nodes.remove_at(index)
	world.objects.remove_at(index)
	world.structure_links.step()

func _structure_link(actor, msg: Dictionary) -> Dictionary:
	var links = world.structure_links
	var action = msg.get("action", "")
	if action not in ["connect", "unlink"]: return _failure("连接动作无效")
	var a: String = str(msg.get("a", "")); var b: String = str(msg.get("b", ""))
	var saved: Dictionary = {}
	if action == "unlink":
		for record in links.records:
			if record.id == msg.get("id"): saved = record; break
		if saved.is_empty(): return _failure("连接已经不存在")
		a = saved.a; b = saved.b
	for key in [a,b]:
		var object: Dictionary = links.object(key)
		if object.is_empty(): return _failure("部件已经不存在")
		if not cooperation.can_use(actor,object): return _failure("只能连接自己或作者已开放的部件")
		if Vector2(object.x,object.y).distance_to(actor.player.position)>12: return _failure("超出12米连接范围")
		if locks.has(object.id): return _failure("先结束部件移动，再连接")
	var result: Dictionary
	if action == "connect":
		var point = msg.get("point")
		if not point is Vector2 or not point.is_finite() or point.distance_to(actor.player.position)>12: return _failure("连接位置无效或超出12米")
		result = links.create(a,b,point,str(msg.get("kind", "")))
	else: result = links.remove(saved.id)
	if result.ok:
		var versions:Dictionary=cooperation.touch([a,b])
		actor.history.append({"op":"link_add" if action=="connect" else "link_remove", "link":result.link,"versions":versions})
		_trim_history(actor); revision += 1
	return result

func _object_index(id: String) -> int:
	for index in world.objects.size():
		if world.objects[index].id==id: return index
	return -1

func _trim_history(actor) -> void:
	while actor.history.size()>30: actor.history.pop_front()

func _save() -> Dictionary:
	if world.sync_objects(): revision += 1
	var result: Dictionary = store.save(world_id,{"map_id":map_id,"owner_token":owner_token,"owner_id":owner_id,"member_credentials":member_credentials,"next_id":next_id,"paper":world.paper,"objects":world.objects,"world":world.world_save_state()})
	last_save_error = "" if result.ok else str(result.error)
	return result

func close_room(reason: String) -> Dictionary:
	for actor in actors.values(): _release_carried(actor)
	var result := _save()
	if not result.ok:
		close_reason = "房间结束，但保存失败："+str(result.error)+"；上次有效存档已保留"
	else: close_reason=reason
	closed=true
	return result

func snapshot() -> Dictionary:
	if world.sync_objects(): revision += 1
	return {"epoch":epoch,"revision":revision,"cooperation":cooperation.snapshot(),"world_kind":map_id,"objects":world.objects.duplicate(true),"bodies":_body_states(),"world":world.world_save_state(),"event_cursor":event_seq,"layout":world.knowledge_world.network_layout() if map_id=="knowledge-v1" else {},"actors":_actor_states()}

func _actor_states(compact: bool=false) -> Array:
	var result: Array = []
	for actor in actors.values():
		var state: Dictionary = actor.state()
		if compact: state.erase("weapon")
		result.append(state)
	return result

func _body_states() -> Array:
	var bodies: Array = []
	for i in world.objects.size():
		var object: Dictionary = world.objects[i]
		var body: RigidBody2D = world.object_nodes[i]
		bodies.append({"id":object.id,"position":body.position,"angle":body.rotation,"velocity":body.linear_velocity,"angular_velocity":body.angular_velocity,"health":object.health,"version":object.version,"damage_cuts":object.get("damage_cuts",[])})
	return bodies

func frame() -> Dictionary:
	var bodies: Array = _body_states()
	var entities: Array = []
	if world.medieval_world!=null: entities=world.medieval_world.save_state()
	return {"epoch":epoch,"tick":tick,"revision":revision,"cooperation":cooperation.snapshot(),"actors":_actor_states(),"events":combat_events.duplicate(true),"bodies":bodies,"entities":entities,"bridge_trial":world.medieval_world.bridge_trial.snapshot() if world.medieval_world!=null else {},"save_error":last_save_error}

func _success() -> Dictionary: return {"ok":true,"error":""}
func _failure(text: String) -> Dictionary: return {"ok":false,"error":text}

func record_feedback(kind: String, position: Vector2, source: String = "", amount: float = 0.0, audio: String = "") -> void:
	if audio!="" and not PaperCombatAudio.valid(audio):return
	if kind not in ["swing","hit","break","hurt","clash","draw_bow","shoot","voice"]: return
	event_seq += 1
	combat_events.append({"id":event_seq,"kind":kind,"position":position,"source":source,"amount":amount,"at":event_clock,"audio":audio})
	while combat_events.size() > 64: combat_events.pop_front()

func _step_shared_arrows(delta: float) -> void:
	# All arrows use the same frame interval and ordered contacts, including walls.
	# Keep each player's display/projectile ownership independent after arbitration.
	world.network_peers = actors.values()
	world.combat.projectiles = []
	for actor in actors.values():
		for arrow in actor.combat.projectiles:
			arrow.shooter = actor.player_id
			world.combat.projectiles.append(arrow)
	world.combat._step_projectiles(delta)
	world.combat.effects.clear()
	for actor in actors.values():
		actor.combat.projectiles = world.combat.projectiles.filter(func(arrow): return arrow.get("shooter","") == actor.player_id)
	world.combat.projectiles = []
