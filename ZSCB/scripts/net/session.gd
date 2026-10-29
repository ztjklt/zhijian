class_name PaperNetSession
extends Node
signal operation_finished(result: Dictionary)
const Codec := preload("res://scripts/net/codec.gd")
const Remote := preload("res://scripts/net/remote_actor.gd")
const PROFILE := "user://network_profile.json"
const ProfileStore := preload("res://scripts/net/profile_store.gd")
var socket: WebSocketPeer
var address := ""
var player_id := ""
var token := ""
var code := ""
var world_id := ""
var is_owner := false
var epoch := ""
var revision := -1
var last_tick := -1
var ready_to_play := false
var status := "等待连接"
var game: PaperCastleMain
var remotes: Dictionary = {}
var mode := "create"
var map_id := "medieval-v1"
var display_name := "画家"
var seq := 0
var send_clock := 0.0
var preview_clock := 0.0
var heartbeat_clock := 0.0
var last_packet_age := 0.0
var connect_age := 0.0
var welcomed := false
var chunks: Dictionary = {}
var chunk_count := 0
var chunk_bytes := 0
var syncing := false
var pending: Dictionary = {}
var upload_queue: Array = []
var upload_clock := 0.0
var sent_weapon: Dictionary = {}
var equip_wait := false
var resend_pending := false
var hud: Label
var invite_button: Button
var round_trip_ms := -1
var ended := false
var leaving := false
var leave_seq := -1
var window_closing := false
var focus_active := true
var profile: Dictionary = {}
var profile_writable := true
var profile_error := ""
var carried_by_actor: Dictionary = {}
var targets: Dictionary = {}
var local_target := Vector2.ZERO
var received_position := false
var prediction = preload("res://scripts/net/local_prediction.gd").new()
var last_controls: Dictionary = {}
var resync_cooldown := 0.0
var jump_queued := false
var profile_clock := 0.0
var retries := 0
var retry_clock := -1.0
var save_exit_pending := false
var creation_receipts = preload("res://scripts/net/creation_receipts.gd").new()
var navigation_pending := false
var leave_confirmed := false
var local_dead_time := 0.0
var local_protection := 0.0
var last_event := -1
var feedback_epoch := ""
var peer_status := "等待朋友加入 · 1/2"
var last_blocked := false
var last_combat_blocked := false
var combat_intent = preload("res://scripts/net/combat_intent.gd").new()
var sent_preview: Array = []
var preview_current := false
var save_request = preload("res://scripts/net/save_request.gd").new()
var preview_lifecycle: Array = []

func _ready() -> void:
	get_tree().auto_accept_quit=false
	var loaded := ProfileStore.load_profile(PROFILE)
	profile = loaded.profile
	profile_writable = loaded.ok
	profile_error = loaded.error
	if profile_error != "": status = profile_error

func connect_room(url: String, action: String, invite: String, name_text: String, map: String, credential: String="", saved_world: String="") -> Error:
	address=url.strip_edges()
	if not address.begins_with("ws://") and not address.begins_with("wss://"): address="wss://"+address
	if address.begins_with("ws://") and not (address.begins_with("ws://127.0.0.1:") or address.begins_with("ws://localhost:")):
		status="公网联机请使用 wss:// 地址"
		return ERR_INVALID_PARAMETER
	mode=action; code=invite.strip_edges().to_upper(); display_name=name_text; map_id=map
	token=credential; world_id=saved_world
	ended=false; leaving=false; leave_seq=-1; retries=0
	seq=0; pending.clear(); equip_wait=false
	return _connect()

func _connect() -> Error:
	sent_preview.clear(); preview_current=false; preview_lifecycle.clear(); preview_clock=.15
	prediction.clear(); last_controls.clear(); heartbeat_clock=5
	combat_intent.reset(game)
	socket=WebSocketPeer.new()
	socket.inbound_buffer_size=4*1024*1024
	socket.outbound_buffer_size=2*1024*1024
	socket.max_queued_packets=256
	socket.heartbeat_interval=5
	welcomed=false; ready_to_play=false; syncing=false; connect_age=0; last_packet_age=0
	var result:=socket.connect_to_url(address)
	status="正在连接服务器…" if result==OK else "无法连接，请检查服务器地址"
	return result

func _process(delta: float) -> void:
	if socket==null or ended: return
	if retry_clock>=0:
		retry_clock-=delta
		if retry_clock<=0: retry_clock=-1; _connect()
		return
	connect_age+=delta; last_packet_age+=delta
	resync_cooldown=maxf(0,resync_cooldown-delta)
	socket.poll()
	match socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not welcomed:
				welcomed=true
				var request:={"type":mode,"protocol":Codec.PROTOCOL,"name":display_name,"map_id":map_id,"code":code,"token":token}
				request.preview_delta=true
				if mode=="join" and token=="":
					var known:Dictionary={}
					for saved in profile.get("known_worlds",[]):
						if saved.get("address","")==address: known[saved.world_id]=saved.token
					request.known_tokens=known
				if mode=="create" and world_id!="": request.world_id=world_id; request.owner_token=token
				_send(request)
				status="正在接收共享世界…"
			if leaving and ready_to_play and leave_seq<0: leave_seq=send_op("leave")
			upload_clock+=delta
			if ready_to_play and not upload_queue.is_empty() and upload_clock>=.05:
				upload_clock=0
				var part:Dictionary=upload_queue.pop_front()
				send_op(part.op,part.data)
			var budget:=32
			while socket.get_available_packet_count()>0 and budget>0:
				budget-=1
				var raw:=socket.get_packet()
				if raw.size()>4*1024*1024: _fail("服务器消息过大"); return
				var message=Codec.decode(raw.get_string_from_utf8())
				if not message is Dictionary: _fail("服务器消息无效"); return
				last_packet_age=0
				_receive(message)
			heartbeat_clock+=delta
			if heartbeat_clock>=5: heartbeat_clock=0; _send({"type":"ping","stamp":Time.get_ticks_msec()})
			if last_packet_age>15: socket.close(); _disconnected()
		WebSocketPeer.STATE_CONNECTING:
			if connect_age>12: socket.close(); _disconnected()
		WebSocketPeer.STATE_CLOSED:
			_disconnected()

func _send(message: Dictionary) -> void:
	if socket==null or socket.get_ready_state()!=WebSocketPeer.STATE_OPEN: return
	if socket.get_current_outbound_buffered_amount()>1024*1024: socket.close(1008,"slow connection"); return
	var text:=Codec.encode(message)
	if text!="": socket.send_text(text)

func send_op(op: String, data: Dictionary={}) -> int:
	if not ready_to_play:
		if game!=null: game.message("正在同步或重连，请稍候；草稿已保留")
		return -1
	seq+=1
	var message:=data.duplicate(true)
	message.type="command"; message.op=op; message.seq=seq; message.epoch=epoch
	_send(message)
	if game != null:
		if op == "attack": combat_intent.begin(game,seq,data.get("direction",Vector2(game.facing,0)))
		elif op == "bow": combat_intent.toggle(game,seq)
		elif op in ["equip","leave"]: combat_intent.cancel(game)
	return seq

func _receive(message: Dictionary) -> void:
	match str(message.get("type","")):
		"pong":
			if message.has("stamp"): round_trip_ms = maxi(0,Time.get_ticks_msec()-int(message.stamp))
		"welcome":
			if message.get("protocol",0) != Codec.PROTOCOL:
				_fail("联机版本不匹配：请让两位玩家和服务器使用同一版；当前需要对战协议%d" % Codec.PROTOCOL)
				return
			map_id = str(message.get("map_id",map_id))
			seq=maxi(seq,int(message.get("next_seq",0)))
			resend_pending=not pending.is_empty()
			player_id=message.player_id; token=message.token; is_owner=message.owner
			code=message.code; world_id=message.get("world_id",world_id)
			if epoch!=message.epoch: last_tick=-1
			epoch=message.epoch
			profile.address=address; profile.code=code; profile.token=token; profile.world_id=world_id
			profile.owner=is_owner; profile.name=display_name; profile.map_id=map_id
			var known_worlds:Array=profile.get("known_worlds",[])
			var known_found:=false
			for saved in known_worlds:
				if saved.get("world_id","")==world_id and saved.get("address","")==address:
					saved.token=token; known_found=true
			if not known_found: known_worlds.append({"world_id":world_id,"address":address,"token":token})
			profile.known_worlds=known_worlds
			if is_owner:
				var saved_worlds:Array=profile.get("saved_worlds",[])
				var found:=false
				for saved in saved_worlds:
					if saved.get("world_id","")==world_id and saved.get("address","")==address: found=true
				if not found: saved_worlds.append({"world_id":world_id,"address":address,"token":token,"map_id":map_id,"name":display_name})
				profile.saved_worlds=saved_worlds
			_save_profile()
		"world_changed":
			save_request.cancel(self,"共享世界已切换，请在当前世界重新保存")
			epoch=str(message.epoch); last_tick=-1; revision=-1
			sent_preview.clear(); preview_current=false; preview_lifecycle.clear(); preview_clock=.15
			prediction.clear()
			combat_intent.reset(game)
			ready_to_play=false; syncing=true; pending.clear(); equip_wait=false
		"snapshot_begin":
			if message.get("epoch","")!=epoch: return
			chunks.clear(); chunk_bytes=0; chunk_count=int(message.get("chunks",0))
			if chunk_count<1 or chunk_count>2048: _fail("世界快照过大"); return
			ready_to_play=false; syncing=true
		"snapshot_chunk":
			if message.get("epoch","")!=epoch or not syncing: return
			var index:=int(message.get("index",-1))
			if index<0 or index>=chunk_count or not message.get("data") is String: _fail("快照分块无效"); return
			if not chunks.has(index): chunk_bytes+=message.data.to_utf8_buffer().size()
			if chunk_bytes>16*1024*1024: _fail("世界快照超出限制"); return
			chunks[index]=message.data
		"snapshot_end":
			if message.get("epoch","")!=epoch or not syncing: return
			if chunks.size()!=chunk_count: _fail("快照不完整，请重新连接"); return
			var text:=""
			for i in chunk_count: text+=chunks[i]
			var snapshot=Codec.decode(text)
			if not snapshot is Dictionary: _fail("世界快照无效"); return
			apply_snapshot(snapshot)
			chunks.clear(); syncing=false
			_send({"type":"ready","epoch":epoch})
		"ready":
			if message.get("epoch","")!=epoch: return
			ready_to_play=true; retries=0
			if resend_pending:
				var numbers:Array=pending.keys(); numbers.sort()
				for number in numbers:
					if pending[number].has("request"): _send(pending[number].request)
				resend_pending=false
			status="房间 "+code+" · "+("创建者" if is_owner else "朋友")+" · 最多2人"
			if game!=null: game.message(status)
			save_request.step(self,0)
		"frame":
			apply_frame(message)
		"result":
			if message.get("epoch",epoch) != epoch: return
			_result(message)
		"error":
			if message.get("error","")=="resync_rate_limit": syncing=false; return
			status=_error_text(str(message.get("error","联机操作失败")))
			if game!=null: game.message(status)
			if not ready_to_play and not syncing: _fail(status)
		"closed":
			_fail(str(message.get("error","房间已结束")))

func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.get("epoch","")!=epoch: return
	if game==null:
		game=preload("res://scenes/main.tscn").instantiate()
		game.world_kind=snapshot.world_kind
		game.network_session=self
		get_tree().root.add_child(game)
		var lobby=get_tree().current_scene
		get_tree().current_scene=game
		if lobby!=null and lobby!=game: lobby.queue_free()
		game.combat.set_natives(false)
		game.onboarding.visible=false; game.onboarding.persist=false
		game.toolbar.training_button.disabled=true
		game.toolbar.undo_button.disabled=false
		game.toolbar.redo_button.disabled=true
		game.player.freeze=true
		game.player.collision_layer=0; game.player.collision_mask=0
		if ProfileStore.valid_bag(profile.get("bag")): game.bag=profile.bag
		game.equipped_weapon=profile.get("weapon",{})
		creation_receipts.restore(profile.get("pending_blueprints", []))
		sent_weapon=game.equipped_weapon.duplicate(true)
		var layer:=CanvasLayer.new(); layer.layer=3
		game.add_child(layer)
		hud=Label.new(); hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
		hud.add_theme_color_override("font_color",Color("216a73"))
		hud.add_theme_font_size_override("font_size",13)
		layer.add_child(hud)
		hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hud.add_theme_color_override("font_shadow_color",Color("fffdf1"))
		hud.add_theme_constant_override("shadow_outline_size",4)
		invite_button = Button.new()
		invite_button.focus_mode = Control.FOCUS_NONE
		invite_button.theme = PaperTheme.create()
		invite_button.pressed.connect(func():
			if ended: return_to_selector("res://scenes/network_lobby.tscn")
			else:
				DisplayServer.clipboard_set("纸间双人房间："+code+"\n服务器："+address+"\n请使用同一版客户端（对战协议%d）" % Codec.PROTOCOL)
				game.message("房间码和服务器地址已复制，发给朋友即可加入"))
		layer.add_child(invite_button)
		get_window().title="纸间 · 双人对战 "+Codec.RELEASE+" · "+code
	# Routine resync must not discard a stroke while the mouse is held.
	if game.drag!=null: game.cancel_pointer()
	game.selected=-1
	if game.knowledge_world!=null and not snapshot.get("layout",{}).is_empty(): game.knowledge_world.apply_network_layout(snapshot.layout)
	game.objects=snapshot.get("objects",[])
	game.receive_cooperation(snapshot.get("cooperation",{}))
	game._rebuild_objects()
	game.structure_links.restore(snapshot.get("world", {}).get("connections", []))
	targets.clear()
	for record in snapshot.get("bodies",[]): targets[str(record.id)]=record
	for body in game.object_nodes:
		body.freeze=true; body.collision_layer=8 if body.data.get("kind","") in ["gate","ladder"] else 1; body.collision_mask=0
		_body_motion(body,targets.get(str(body.data.id),{}))
	if game.medieval_world!=null:
		var details:Dictionary=snapshot.get("world",{})
		var records:Array=details.get("entities",[])
		if not records.is_empty(): game.medieval_world.restore_state(records,int(details.get("terrain_version",1)),int(details.get("content_version",1)),details.get("bridge_trial",{}))
		for entity in game.medieval_world.entities: entity.freeze=true; entity.collision_layer=0; entity.collision_mask=0
	revision=int(snapshot.get("revision",0))
	# A snapshot describes current state; its historical sounds must stay silent.
	# New room epochs may restart numbering, while same-room resync cannot rewind.
	var cursor:=int(snapshot.get("event_cursor",0))
	last_event=cursor if feedback_epoch!=epoch else maxi(last_event,cursor)
	feedback_epoch=epoch
	carried_by_actor.clear()
	for state in snapshot.get("actors",[]): _actor(state)
	_apply_carry_collisions()
	game.backpack_ui.refresh()

func apply_frame(frame: Dictionary) -> void:
	if game==null or frame.get("epoch","")!=epoch: return
	var frame_tick:=int(frame.get("tick",0))
	if frame_tick<=last_tick: return
	last_tick=frame_tick
	game.receive_cooperation(frame.get("cooperation",{}))
	var seen:={}
	var bodies:Dictionary={}
	for item in frame.get("bodies",[]): bodies[str(item.id)]=item
	for i in range(game.objects.size()-1,-1,-1):
		var object:Dictionary=game.objects[i]
		if not bodies.has(str(object.id)):
			game.object_nodes[i].queue_free(); game.object_nodes.remove_at(i); game.objects.remove_at(i)
			continue
		var item:Dictionary=bodies[str(object.id)]
		targets[str(object.id)]=item
		_body_motion(game.object_nodes[i],item)
		object.health=item.health; object.version=item.version
		if item.has("damage_cuts") and object.get("damage_cuts",[])!=item.damage_cuts:
			if PaperObjectDamage.valid_cuts(item.damage_cuts):
				object.damage_cuts=item.damage_cuts.duplicate(true)
				game.object_nodes[i].rebuild_damage()
	for state in frame.get("actors",[]):
		seen[state.id]=true
		_actor(state)
	for id in remotes.keys():
		if not seen.has(id): remotes[id].queue_free(); remotes.erase(id);game.weapon_lab.others.erase(id);carried_by_actor.erase(id)
	_apply_carry_collisions()
	if remotes.is_empty(): peer_status = "等待朋友加入 · 1/2"
	_apply_feedback(frame.get("events",[]))
	if game.medieval_world!=null:
		for record in frame.get("entities",[]):
			var entity=game.medieval_world.entity_by_id(str(record.id))
			if entity==null: continue
			entity.position=Vector2(record.x,record.y); entity.rotation=float(record.get("angle",0))
			entity.health=record.health; entity.alive=record.alive; entity.state=record.state; entity.facing=record.facing
			if entity.cuts!=record.cuts: entity.cuts=record.cuts; entity.rebuild_geometry()
	if game.medieval_world!=null and frame.has("bridge_trial"): game.medieval_world.bridge_trial.receive(frame.bridge_trial)
	if frame.get("save_error","")!="": game.message("云存档保存失败："+str(frame.save_error))
	if int(frame.get("revision",revision))!=revision and not syncing and resync_cooldown<=0:
		syncing=true; ready_to_play=false; resync_cooldown=1.1; _send({"type":"resync"})

func _body_motion(body: RigidBody2D, state: Dictionary) -> void:
	# Frozen copies provide support motion to the shared ladder controller only.
	# No replica simulation and no motion fields in persistent drawing data.
	body.linear_velocity = state.get("velocity",Vector2.ZERO)
	body.angular_velocity = float(state.get("angular_velocity",0))

func _apply_carry_collisions() -> void:
	var held: Dictionary = {}
	for id in carried_by_actor.values():
		if str(id) != "": held[str(id)] = true
	for body in game.object_nodes:
		body.freeze = true
		body.collision_mask = 0
		body.collision_layer = 0 if held.has(str(body.data.get("id", ""))) else (8 if body.data.get("kind", "") in ["gate", "ladder"] else 1)

func _actor(state: Dictionary) -> void:
	if state.has("carried_id"): carried_by_actor[str(state.id)] = str(state.carried_id)
	if state.has("weapon_lab"):
		if state.id==player_id:game.weapon_lab.receive(state.weapon_lab)
		else:game.weapon_lab.others[state.id]=state.weapon_lab.duplicate(true)
	if state.id==player_id:
		if state.has("carried_id"): game.apply_carry_state(str(state.get("carried_id", "")))
		local_target=state.position
		prediction.receive(game,state,Time.get_ticks_msec(),round_trip_ms)
		received_position=true
		game.ink.amount = clampf(float(state.get("ink", 300)), 0, 300)
		game.ink.wait = maxf(0, float(state.get("ink_wait", 0)))
		game.ink.last_cost = float(state.get("ink_spent", 0))
		game.ink.recent = float(state.get("ink_flash", 0))
		combat_intent.receive(game,state)
		for key in ["impact_hold","swing","motion_index","swing_direction","recoil","shot_recoil","health","projectiles"]:
			if state.has(key): game.combat.set(key,state[key])
		# A delayed initial frame must not erase a hotbar choice before tick queues it.
		if not equip_wait and state.has("weapon") and game.equipped_weapon == sent_weapon:
			game.equipped_weapon=state.weapon; sent_weapon=state.weapon.duplicate(true)
		var dead := float(state.get("dead",0))
		if dead > 0 and local_dead_time <= 0:
			preview_current=false; preview_clock=.15
			game.retain_active_stroke()
			game.drag = null
			game.cancel_pointer()
			game.selected = -1
			game.cancel_weapon_grip(false)
			game.pending_building.clear()
			game.placement_preview.clear()
			game.placing_blueprint_id = -1
			jump_queued = false
		local_dead_time = dead
		local_protection = float(state.get("protected",0))
		game.character_visual.visible=dead<=0
		status="房间 "+code+" · "+str(state.get("name","画家"))+" · HP "+str(int(state.get("health",100)))
		if local_protection > 0 and dead <= 0: status += " · 保护中"
		if dead>0: status+=" · "+str(snappedf(state.dead,.1))+"秒后重生"
	else:
		if not remotes.has(state.id):
			var remote=Remote.new(); remote.display_game=game; remote.z_index=10
			game.add_child(remote); remotes[state.id]=remote
		remotes[state.id].apply(state)
		peer_status = str(state.get("name","朋友"))+" · HP "+str(int(state.get("health",100)))
		if not state.get("connected",true): peer_status += " · 断线重连中"
		elif float(state.get("dead",0))>0: peer_status += " · %.1f秒后重生" % float(state.dead)
		elif float(state.get("protected",0))>0: peer_status += " · 保护中"

func tick(delta: float) -> void:
	save_request.step(self,delta)
	creation_receipts.retry(self,delta)
	if hud!=null:
		hud.text=status+(" · 同步中…" if syncing else "")+"\n"+peer_status+(" · %dms" % round_trip_ms if round_trip_ms>=0 else "")
		var viewport := game.get_viewport_rect().size
		var amount := PaperGuiScale.factor(viewport)
		var logical := viewport / amount
		var compact := logical.x < 900 or logical.y < 500
		var width := minf(350*amount,viewport.x-24*amount)
		var top:float = game.toolbar.header.get_global_rect().end.y + 8*amount
		if compact:
			top = maxf(top,game.toolbar.bottom.get_global_rect().end.y+40*amount)
			var controls = game.knowledge_world.controls if game.knowledge_world!=null else game.map_controls
			if controls!=null and controls.panel.is_visible_in_tree(): top = maxf(top,controls.panel.get_global_rect().end.y+40*amount)
		hud.add_theme_font_size_override("font_size",roundi(13*amount))
		hud.position=Vector2(12*amount if compact else viewport.x-width-20*amount,top)
		hud.size=Vector2(width,0)
		if invite_button!=null:
			invite_button.text="返回联机大厅" if ended else "复制房间邀请 · "+code
			invite_button.add_theme_font_size_override("font_size",roundi(12*amount))
			invite_button.position=hud.position+Vector2(0,hud.get_combined_minimum_size().y+4*amount)
			invite_button.size=Vector2(minf(width,220*amount),30*amount)
		hud.visible=not game.bag_open and not (game.experience!=null and game.experience.visible) and not game.lab_open() and not game.cooperation_open()
		if invite_button!=null: invite_button.visible=hud.visible

	for i in game.object_nodes.size():
		var body:RigidBody2D=game.object_nodes[i]
		body.freeze=true
		var id:=str(game.objects[i].id)
		if targets.has(id) and not (game.drag!=null and game.selected==i):
			var state:Dictionary=targets[id]
			body.position=body.position.lerp(state.position,minf(1,delta*22))
			body.rotation=lerp_angle(body.rotation,float(state.angle),minf(1,delta*22))
			body.sync_to_data()
	if game.active_stroke==null and game.drag==null and not game.selecting_weapon_grip:
		game.camera_x=lerpf(game.camera_x,game.player.position.x,1-exp(-delta*7))
		if game.knowledge_world!=null or game.medieval_world!=null: game.camera_y=lerpf(game.camera_y,game.camera_target_y(),1-exp(-delta*5))
	game._update_world_chunks()
	for effect in game.combat.effects: effect.time -= delta
	game.combat.effects = game.combat.effects.filter(func(effect): return effect.time > 0)
	if not ready_to_play or leaving or local_dead_time>0: combat_intent.reset(game)
	if not ready_to_play or leaving or ended or local_dead_time>0:
		prediction.step(game,delta,{},false,Time.get_ticks_msec())
		return
	_input_keys()
	var focus:=game.get_viewport().gui_get_focus_owner()
	var blocked:bool=not focus_active or focus is LineEdit or focus is TextEdit or game.bag_open or (game.knowledge_world!=null and game.knowledge_world.overview) or (game.experience!=null and game.experience.visible) or game.lab_open() or game.cooperation_open()
	jump_queued=false if blocked else jump_queued or Input.is_action_just_pressed("jump")
	send_clock+=delta; preview_clock+=delta
	profile_clock+=delta
	if profile_clock>=10: profile_clock=0; _save_profile()
	var combat_blocked:bool = blocked or game.selecting_weapon_grip
	combat_intent.step(game,delta,combat_blocked)
	var stick:Vector2=game.touch_controls.movement_vector() if game.touch_controls!=null else Vector2.ZERO
	var controls:={"blocked":blocked,"combat_blocked":combat_blocked,"left":not blocked and (Input.is_action_pressed("move_left") or stick.x<-.25),"right":not blocked and (Input.is_action_pressed("move_right") or stick.x>.25),"up":not blocked and (Input.is_action_pressed("move_up") or stick.y<-.5),"down":not blocked and (Input.is_action_pressed("move_down") or stick.y>.5),"jump":not blocked and (Input.is_action_pressed("jump") or jump_queued)}
	prediction.step(game,delta,controls,true,Time.get_ticks_msec())
	if send_clock>=.05 or controls!=last_controls:
		last_blocked=blocked;last_combat_blocked=combat_blocked
		last_controls=controls.duplicate();send_clock=0
		var input_number:=send_op("input",controls)
		prediction.sent_input(input_number,controls)
	jump_queued=false
	if not equip_wait and game.equipped_weapon!=sent_weapon:
		var number:=send_op("equip",{"weapon":game.equipped_weapon})
		if number>0: pending[number]={"op":"equip","before":sent_weapon.duplicate(true),"request":{"type":"command","op":"equip","seq":number,"epoch":epoch,"weapon":game.equipped_weapon.duplicate(true)}}; equip_wait=true
	_sync_preview()

func _sync_preview() -> void:
	var lifecycle := [game.draw_mode,game.draft.size(),game.active_stroke!=null,game.active_stroke!=null and game.active_stroke.points.size()>1]
	if preview_clock < .15 and lifecycle == preview_lifecycle: return
	preview_clock=0; preview_lifecycle=lifecycle
	var paths: Array = game.draft.duplicate()
	if game.active_stroke!=null: paths.append(game.active_stroke)
	var reduced: Array = preload("res://scripts/net/drawing_preview.gd").sample(paths)
	if (not preview_current or reduced != sent_preview) and send_op("preview",{"paths":reduced}) > 0:
		sent_preview=reduced; preview_current=true

func _input_keys() -> void:
	if not focus_active: return
	var focus:=game.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if game.personal_overlay_open():
		if Input.is_action_just_pressed("cancel"): game.close_personal_overlay()
		return
	if Input.is_action_just_pressed("toggle_bag"): game.toggle_bag()
	if Input.is_action_just_pressed("cancel"):
		if game.bag_open: game.toggle_bag()
		else: game.cancel_pointer(); game.cancel_weapon_grip(false)
	if game.bag_open: return
	for slot in range(6):
		if Input.is_action_just_pressed("hotbar_"+str(slot+1)):
			if Input.is_key_pressed(KEY_SHIFT): game.equip_hotbar(slot)
			elif slot==5: game.toggle_bag()
			else: game.activate_draw_mode([1,3,2,4,5][slot])
	if Input.is_action_just_pressed("generate"): game.input_command("generate")
	if Input.is_action_just_pressed("attack"): game.attack()
	if Input.is_action_just_pressed("carry"): game.toggle_carry()
	if Input.is_action_just_pressed("toggle_bow"): send_op("bow")
	if Input.is_action_just_pressed("delete_object"): game.delete_selected()

func spawn_candidate(object: Dictionary):
	if creation_receipts.blocked(self): return null
	for request in pending.values():
		if request.op=="spawn": game.message("正在等待服务器生成确认；请勿重复提交"); return null
	if game.bag.entries.size()>=128 and game.placing_blueprint_id<0: game.message("图纸背包已满，请先整理"); return null
	var number:=send_op("spawn",{"object":object})
	if number>0:
		pending[number]={"op":"spawn","draft":game.draft.duplicate(true),"draw_mode":game.draw_mode,"blueprint":game.placing_blueprint_id,"request":{"type":"command","op":"spawn","seq":number,"epoch":epoch,"object":object.duplicate(true)}}
		pending[number].creation=creation_receipts.capture(self)
		game.message("正在等待服务器生成确认…")
	return null

func equip_drawing(weapon: Dictionary) -> void:
	if creation_receipts.blocked(self): return
	if equip_wait: game.message("正在等待服务器确认武器"); return
	if game.bag.entries.size()>=128: game.message("图纸背包已满，草稿已保留"); return
	var number:=send_op("equip",{"weapon":weapon})
	if number<0: return
	pending[number]={"op":"equip_drawing","before":game.equipped_weapon.duplicate(true),"draft":game.draft.duplicate(true),"draw_mode":game.draw_mode,"request":{"type":"command","op":"equip","epoch":epoch,"seq":number,"weapon":weapon}}
	pending[number].creation=creation_receipts.capture(self)
	equip_wait=true
	game.message("正在等待服务器确认握点与武器；原武器保持装备")

func _result(result: Dictionary) -> void:
	if result.get("op","")=="preview" and not result.get("ok",false): preview_current=false
	if game != null: combat_intent.result(game,result)
	if game != null and result.get("op","")=="weapon_lab": game.weapon_lab_receipt(result)
	if game!=null and result.get("op","")=="collaborate":game.cooperation_panel.notice_label.text="协作许可已确认；可关闭面板继续搭建。" if result.get("ok",false) else str(result.get("error","协作操作失败"))
	var handled_save: bool = save_request.receive(self,result)
	operation_finished.emit(result)
	if handled_save: return
	if result.get("op","")=="leave":
		leave_confirmed = bool(result.get("ok",false))
		status="已保存并退出房间" if result.get("ok",false) else str(result.get("error","保存失败，上次好档已保留"))
		if game != null and not leave_confirmed: game.message(status)
		ended=true; ready_to_play=false
		if socket!=null: socket.close()
		return
	var number:=int(result.get("seq",-1))
	var request:Dictionary=pending.get(number,{})
	pending.erase(number)
	if request.get("op","") in ["equip","equip_drawing"]:
		equip_wait=false
		if result.get("ok",false): sent_weapon=result.get("weapon",{}).duplicate(true); game.equipped_weapon=sent_weapon.duplicate(true)
		else: game.equipped_weapon=request.before
	if not result.get("ok",false):
		if game!=null: game.message(str(result.get("error","服务器拒绝操作")))
		return
	if request.get("op","")=="equip_drawing" and game!=null:
		creation_receipts.complete(self,request,game.equipped_weapon)
	if request.get("op","")=="spawn" and game!=null:
		creation_receipts.complete(self,request,result.object)
	if result.get("op","") in ["import","upload_commit"] and game!=null: game.message("旧作品已由服务器校验、保存并导入；双方图纸保持独立")
	if result.get("op","")=="save" and game!=null: game.message("房间世界已保存到服务器")
	if result.get("op","")=="structure_link" and game!=null: game.message("服务器已确认结构连接操作")
	if result.get("op","")=="carry" and game!=null:
		game.apply_carry_result(result)
		return

func import_local() -> void:
	if not is_owner: game.message("只有创建者能读取旧作品覆盖房间"); return
	if not ready_to_play or not upload_queue.is_empty(): game.message("请等待当前同步完成"); return
	var result:=SaveStore.load_game("medieval-v1" if game.world_kind=="medieval-v1" else "")
	if result.error!="": game.message(result.error); return
	var data:Dictionary=result.data
	var world:Dictionary=data.get("world",{"id":"paper"})
	if world.get("id","paper")!=game.world_kind: game.message("请在相同地图的房间导入旧作品"); return
	var text:=Codec.encode({"objects":data.objects,"world":world})
	if text=="": game.message("旧作品数据超过容量，原世界未改变"); return
	var count:=ceili(float(text.length())/12000)
	upload_queue.append({"op":"upload_begin","data":{"chunks":count}})
	for index in count: upload_queue.append({"op":"upload_chunk","data":{"index":index,"data":text.substr(index*12000,12000)}})
	upload_queue.append({"op":"upload_commit","data":{}})
	game.message("正在导入本机旧作品；服务器确认成功前保留原世界")

func _save_profile() -> bool:
	if game!=null:
		profile.bag=game.bag; profile.weapon=game.equipped_weapon
		profile.pending_blueprints=creation_receipts.persistent_items()
	var saved: Dictionary = ProfileStore.save_profile(PROFILE,profile) if profile_writable else {"ok": false, "error": profile_error}
	if not saved.ok:
		profile_error = saved.error
		if game!=null: game.message("个人资料保存失败："+profile_error)
		return false
	profile_error = ""
	return true

func request_save() -> int:
	if not _save_profile(): return save_request.refuse_local(self,"个人资料保存失败："+profile_error)
	return save_request.begin(self)

func save_feedback() -> Dictionary:
	return save_request.feedback()

func leave() -> bool:
	if not _save_profile():
		save_request.refuse_local(self,"个人资料保存失败，离开已取消："+profile_error)
		return false
	save_request.cancel(self,"正在离开房间，原保存请求不再自动发送；请等待退出确认")
	if ended: return true
	leaving=true
	status="正在保存并结束房间…" if is_owner else "正在退出房间…"
	if ready_to_play and leave_seq<0: leave_seq=send_op("leave")
	return true

func save_and_return_to_selector(destination: String) -> void:
	if save_exit_pending or navigation_pending: return
	save_exit_pending = true
	if not is_owner:
		# Guests save their personal profile on leave; only the owner saves the world.
		await return_to_selector(destination, true)
		save_exit_pending = false
		return
	var save_ticket := request_save()
	while not save_request.completed.has(save_ticket):
		await get_tree().process_frame
	var receipt: Dictionary = save_request.completed[save_ticket]
	if not receipt.get("ok",false):
		save_exit_pending = false
		return
	await return_to_selector(destination, true)
	save_exit_pending = false

func return_to_selector(destination: String = "res://scenes/map_select.tscn", require_confirmation: bool = false) -> void:
	if navigation_pending: return
	navigation_pending = true
	leave_confirmed = false
	if not leave(): navigation_pending = false; return
	var deadline:=Time.get_ticks_msec()+3000
	while not ended and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if require_confirmation and not leave_confirmed:
		if not ended: status = "尚未收到退出保存确认，已保留当前画面与草稿；请检查连接"
		if game != null: game.message(status)
		navigation_pending = false
		return
	if not _save_profile():
		save_request.refuse_local(self,"个人资料保存失败，当前画面保留："+profile_error)
		navigation_pending = false
		return
	if socket!=null: socket.close()
	if game!=null: game.network_session=null
	get_tree().change_scene_to_file(destination)
	queue_free()

func _disconnected() -> void:
	save_request.disconnected(self)
	combat_intent.reset(game)
	if game!=null: game.apply_carry_state("")
	ready_to_play=false
	if leaving: ended=true; return
	if game!=null and token!="" and retries<3:
		retries+=1; mode="join"; retry_clock=1.0
		status="连接中断，正在尝试重连（保留30秒席位）…"
	else: _fail("连接失败或重连未成功；回到联机入口可重试，草稿仍保留在本窗口")

func _fail(text: String) -> void:
	save_request.cancel(self,text)
	combat_intent.reset(game)
	status=text; ready_to_play=false; ended=true
	if socket!=null: socket.close()
	if game!=null: game.message(text)


func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and not window_closing:
		window_closing=true
		_close_application()

func _close_application() -> void:
	if not leave(): window_closing = false; return
	var deadline:=Time.get_ticks_msec()+3000
	while not ended and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if not _save_profile():
		save_request.refuse_local(self,"个人资料保存失败，关闭已取消："+profile_error)
		window_closing = false
		return
	get_tree().quit()

func _exit_tree() -> void:
	if get_tree()!=null: get_tree().auto_accept_quit=true

func _apply_feedback(events: Array) -> void:
	for event in events:
		var number := int(event.get("id",0))
		if number <= last_event: continue
		last_event = number
		var position: Vector2 = event.get("position",Vector2.ZERO)
		if game.player.position.distance_to(position)>24: continue
		var kind := str(event.get("kind",""))
		if kind == "hurt" and event.get("source","") != player_id: kind = "hit"
		game.feedback.emit_remote(kind,position,str(event.get("audio","")))
		if float(event.get("amount",0))>0: game.combat.add_damage_text(position,event.amount)

func _error_text(error: String) -> String:
	return {"version_mismatch":"联机版本不匹配：请更新两位玩家的客户端及服务器，再进入同一房间",
		"room_full":"房间已满，最多两人；断线席位会保留30秒",
		"room_not_found":"房间不存在或已结束，请让创建者重开并发送新房间码",
		"service_full":"服务器房间已满，请稍后再创建",
		"world_already_open":"这份云端作品已开房，请重连上次房间",
		"invalid_owner":"云端作品的创建者凭据不匹配，请使用原设备及服务器地址",
		"not_ready":"共享世界仍在同步，请稍候",
		"stale_epoch":"世界已经更新，请等待重新同步"}.get(error,error)
