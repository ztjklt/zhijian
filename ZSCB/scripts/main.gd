class_name PaperCastleMain
extends Node2D

const GROUND_Y := -2.8
var PIXELS_PER_UNIT := 78.0
const MAX_OBJECTS := 600
const MAX_UNDO := 30
const MAX_DRAW_STROKES := 128
@export_enum("paper", "knowledge-v1", "medieval-v1", "nature-v1") var world_kind := "paper"
var map_workspaces: Dictionary = {}
var knowledge_world: Node2D = null
var medieval_world: Node2D = null
var map_controls: Control = null
var camera_y := 0.0

# Game state
var creation_context := 0
var blueprint_selection_context := 0
var mode := "play"
var tool := "draw"
var generator := "own"
var paper := "draft"
var camera_x := 0.0
var ground_chunks := {}
var objects: Array = []
var object_nodes: Array = []
var bag := BlueprintBag.new_bag()
var selected_blueprint_id := -1
var placing_blueprint_id := -1
var bag_open := false
var draft: Array = []
var active_stroke = null
var pending_match: Array = []
var candidate_index := 0
var preview_paths = null
var preview_x := 0.0
var preview_y := 0.0
var selected := -1
var drag = null
var carried_id := ""
var carried_previous: Dictionary = {}
const CARRY_DISTANCE := 0.82
const CARRY_HEIGHT := 0.72
const CARRY_DROP_OFFSET := 0.42
var undo_stack: Array = []
var redo_stack: Array = []
var elapsed := 0.0
var flip_timer := 0.0
var last_page := 0
var on_ground := false
var ground_contacts := 0
var facing := 1
var move_direction := 0
var pose := "idle"
var walk_phase := 0.0
var land_timer := 0.0
var climb_lock_timer := 0.0
var climbing := false
var wall_climb := preload("res://scripts/wall_climb.gd").new()
var draw_cursor = null
var artist_world = null
var last_player_x := -5.6
var has_played := true
var draw_mode := 1
var sculpt_return_mode := 1
var mode_drafts := {}
var build_kind := "freehand"
var building_wait := -1.0
const BUILDING_PAUSE := 0.6
var pending_building: Dictionary = {}
var placement_preview: Dictionary = {}
var placement_world := Vector2.ZERO
var equipped_weapon: Dictionary = {}
var selecting_weapon_type := false
var selected_weapon_type := "sword"
var weapon_type_wheel: Control
var selecting_weapon_grip := false
var selected_weapon_grip: Variant = null
var grip_hover := Vector2.ZERO
var aim_world := Vector2.ZERO
var crouching := false
var combat = null
var ink = preload("res://scripts/ink_reserve.gd").new()
var vitals_hud: Control
var feedback: PaperCreationFeedback = null
var touch_controls = null
var jump_was_down := false
var jumps_used := 0
var down_was_down := false
var down_tap_timer := 0.0
const DOWN_DOUBLE_TAP_WINDOW := 0.28

# Node references
var player: RigidBody2D = null
var camera: Camera2D = null
var canvas_node: Node2D = null
var toolbar: Control = null
var backpack_panel: Control = null
var backpack_ui = null
var onboarding := PaperOnboarding.new()
var first_work
var character_visual: Node2D
var experience: PaperExperience
# Online presentation and authoritative rooms keep independent state.
var network_session = null
var network_headless := false
var network_players: Array = []
var network_peers: Array = []
var structure_links
var weapon_lab
var weapon_lab_panel: Control
var cooperation:Dictionary={"shared":[],"locks":{}}
var cooperation_version:=-1
var cooperation_panel:Control
var refine_weapon_type := ""
var refine_model_fill: Variant = null
var connection_tool := "move"
var connection_source: Dictionary = {}

var build_object_scene := preload("res://scenes/build_object.tscn")

func _ready() -> void:
	weapon_lab = preload("res://scripts/weapon_lab.gd").new(self)
	structure_links = preload("res://scripts/structure_links.gd").new()
	structure_links.game = self
	add_child(structure_links)
	if network_headless:
		_ready_server_world()
		return
	first_work=preload("res://scripts/first_work.gd").new(self)
	get_window().title = "纸间 · " + PaperExperience.VERSION + " 完整体验"
	get_window().content_scale_size = Vector2i.ZERO
	get_viewport().size_changed.connect(_resize_world)
	_resize_world()
	canvas_node = Node2D.new()
	canvas_node.name = "PaperCanvas"
	canvas_node.set_script(preload("res://scripts/paper_canvas.gd"))
	canvas_node.game = self
	add_child(canvas_node)
	character_visual = preload("res://scenes/character.tscn").instantiate()
	add_child(character_visual)
	character_visual.game = self

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 2
	add_child(ui_layer)

	var toolbar_scene := preload("res://scenes/ui/toolbar.tscn")
	toolbar = toolbar_scene.instantiate()
	ui_layer.add_child(toolbar)
	toolbar.game = self
	vitals_hud = toolbar.vitals
	weapon_type_wheel = PaperWeaponTypeWheel.new()
	weapon_type_wheel.game = self
	ui_layer.add_child(weapon_type_wheel)

	var backpack_scene := preload("res://scenes/ui/backpack_panel.tscn")
	backpack_panel = backpack_scene.instantiate()
	ui_layer.add_child(backpack_panel)
	backpack_panel.game = self
	backpack_panel.visible = false
	backpack_ui = backpack_panel

	var player_scene := preload("res://scenes/player.tscn")
	player = player_scene.instantiate()
	player.position = Vector2(-5.6, GROUND_Y + 0.54)
	add_child(player)
	player.game = self

	var starters := [
		{"kind": "wall", "width": 2.6, "height": 1.4},
		{"kind": "tower", "width": 1.1, "height": 2.5},
		{"kind": "gate", "width": 2.6, "height": 2.2},
		{"kind": "ramp", "width": 3.0, "height": 1.1},
		{"kind": "platform", "width": 3.2, "height": 0.35},
		{"kind": "ladder", "width": 0.8, "height": 2.2},
	]
	for item in starters:
		var obj := {"source": "library", "kind": item.kind, "paths": ShapeMatcher.make_prefab(item.kind, {"width": item.width, "height": item.height})}
		BlueprintBag.add_entry(bag, obj)

	combat = PaperCombat.new(self)
	var feedback_layer := CanvasLayer.new()
	feedback_layer.name = "CreationFeedbackLayer"
	feedback_layer.layer = 0 # Above the paper and below interactive toolbar / bag.
	add_child(feedback_layer)
	feedback = PaperCreationFeedback.new()
	feedback.game = self
	feedback_layer.add_child(feedback)
	touch_controls = PaperTouchControls.new()
	touch_controls.game = self
	ui_layer.add_child(touch_controls)
	select_world(world_kind)
	_update_world_chunks()
	var combat_visual := PaperCombatVisual.new()
	combat_visual.game = self
	combat_visual.z_index = 11
	add_child(combat_visual)
	var quality := PaperVisualQuality.new()
	quality.name = "VisualQuality"
	add_child(quality)
	combat.set_natives(world_kind != "medieval-v1")
	var experience_layer := CanvasLayer.new()
	experience_layer.name = "ExperienceLayer"
	experience_layer.layer = 4
	add_child(experience_layer)
	experience = PaperExperience.new()
	experience.game = self
	experience_layer.add_child(experience)
	var lab_layer := CanvasLayer.new()
	lab_layer.layer = 5
	add_child(lab_layer)
	weapon_lab_panel = preload("res://scripts/weapon_lab_panel.gd").new()
	weapon_lab_panel.game = self
	lab_layer.add_child(weapon_lab_panel)
	cooperation_panel=preload("res://scripts/cooperation_panel.gd").new()
	cooperation_panel.game=self
	lab_layer.add_child(cooperation_panel)
	map_controls = preload("res://scripts/medieval_controls.gd").new()
	map_controls.game = self
	ui_layer.add_child(map_controls)
	_resize_world()
	if "--experience" in OS.get_cmdline_user_args(): experience.open()
	if "--clean-ui" in OS.get_cmdline_user_args():
		first_work.visible=false
		onboarding.persist = false
		onboarding.visible = false
		get_window().title = "纸间 · " + PaperExperience.VERSION + " · 最新 UI 整合版"
	print("Paper Castle sandbox started")

func world_to_screen(pos: Vector2) -> Vector2:
	if knowledge_world != null and knowledge_world.overview:
		return knowledge_world.overview_point(pos)
	var viewport_size := get_viewport().get_visible_rect().size
	var shake: Vector2 = feedback.screen_offset if feedback != null else Vector2.ZERO
	return shake + Vector2(
		viewport_size.x * 0.5 + (pos.x - camera_x) * PIXELS_PER_UNIT,
		viewport_size.y - _ground_margin() + (GROUND_Y + camera_y - pos.y) * PIXELS_PER_UNIT
	)

func lab_open() -> bool:
	return weapon_lab_panel != null and weapon_lab_panel.visible

func personal_overlay_open() -> bool:
	return cooperation_open() or lab_open() or (experience != null and experience.visible)

func cooperation_open()->bool:return cooperation_panel!=null and cooperation_panel.visible
func open_cooperation()->void:cooperation_panel.open()
func can_cooperate(object:Dictionary)->bool:
	if network_session==null:return true
	var holder:String=cooperation.get("locks",{}).get(object.get("id",""),"")
	return (holder=="" or holder==network_session.player_id) and (object.get("author","")==network_session.player_id or object.get("id","") in cooperation.get("shared",[]))

func carry_position() -> Vector2:
	return player.position + Vector2(float(facing) * CARRY_DISTANCE, -CARRY_HEIGHT)

func carried_index() -> int:
	if carried_id == "": return -1
	for index in objects.size():
		if str(objects[index].get("id", objects[index].get("structure_id", ""))) == carried_id: return index
	return -1

func toggle_carry() -> bool:
	if network_session != null:
		if carried_id != "":
			network_session.send_op("carry", {"action": "drop", "id": carried_id, "version": objects[carried_index()].version if carried_index() >= 0 else -1})
			return true
		if selected >= 0 and selected < objects.size():
			var candidate: Dictionary = objects[selected]
			if can_cooperate(candidate):
				network_session.send_op("carry", {"action": "pick", "id": candidate.id, "version": candidate.version})
				message("正在等待服务器确认拿起…")
				return true
		message("先用 4 选中一个可搬动的部件")
		return false
	if carried_id != "": return drop_carried()
	if selected < 0 or selected >= objects.size():
		message("先用 4 选中一个部件")
		return false
	return pick_carried(selected)

func apply_carry_state(id: String) -> void:
	if id == carried_id: return
	if carried_id != "":
		var old_index := carried_index()
		if old_index >= 0 and old_index < object_nodes.size():
			var old_body: RigidBody2D = object_nodes[old_index]
			old_body.collision_layer = int(carried_previous.get("layer", 1)) if not carried_previous.is_empty() else (8 if objects[old_index].get("kind", "") in ["gate", "ladder"] else 1)
			old_body.collision_mask = int(carried_previous.get("mask", 1)) if not carried_previous.is_empty() else 1 | 8 | 64 | 128
			old_body.freeze = bool(carried_previous.get("freeze", false))
	carried_id = id
	carried_previous.clear()
	if carried_id == "": return
	var index := carried_index()
	if index < 0 or index >= object_nodes.size(): carried_id = ""; return
	var body: RigidBody2D = object_nodes[index]
	carried_previous = {"layer": body.collision_layer, "mask": body.collision_mask, "freeze": body.freeze}
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	selected = index

func apply_carry_result(result: Dictionary) -> void:
	if not result.get("ok", false):
		message(str(result.get("error", "携物操作失败")))
		return
	apply_carry_state(str(result.get("carried_id", "")))
	message("已拿起部件 · G 放下 · 可继续移动" if carried_id != "" else "已放下部件")

func pick_carried(index: int) -> bool:
	if index < 0 or index >= objects.size() or index >= object_nodes.size(): return false
	var object: Dictionary = objects[index]
	if not can_cooperate(object): message("没有权限拿起这个部件"); return false
	if structure_links != null and structure_links.linked(object.get("structure_id", "")):
		message("部件已连接，请先解除连接再拿起"); return false
	if Vector2(object.x, object.y).distance_to(player.position) > DrawingRules.BUILD_RANGE:
		message("请走近部件，在 12 米内拿起"); return false
	var body: RigidBody2D = object_nodes[index]
	# Single-player drawings have a stable structure key, but no network id.
	carried_id = str(object.get("id", object.get("structure_id", "")))
	carried_previous = {"layer": body.collision_layer, "mask": body.collision_mask, "freeze": body.freeze}
	body.freeze = true
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0
	body.collision_layer = 0
	body.collision_mask = 0
	selected = index
	update_carried_object()
	message("已拿起部件 · G 放下 · 可继续移动")
	return true

func update_carried_object() -> void:
	if carried_id == "": return
	var index := carried_index()
	if index < 0 or index >= object_nodes.size():
		carried_id = ""
		carried_previous.clear()
		return
	var body: RigidBody2D = object_nodes[index]
	var target := carry_position()
	body.position = target
	body.rotation = float(objects[index].get("angle", 0.0))
	objects[index].x = target.x
	objects[index].y = target.y

func drop_carried() -> bool:
	var index := carried_index()
	if index < 0 or index >= object_nodes.size(): carried_id = ""; carried_previous.clear(); return false
	var object: Dictionary = objects[index]
	var body: RigidBody2D = object_nodes[index]
	var old_layer: int = int(carried_previous.get("layer", 1))
	var old_mask: int = int(carried_previous.get("mask", 1))
	body.collision_layer = old_layer
	body.collision_mask = old_mask
	var candidate := object.duplicate(true)
	candidate.x = body.position.x + float(facing) * CARRY_DROP_OFFSET; candidate.y = body.position.y
	body.collision_layer = 0
	body.collision_mask = 0
	var probe := _carry_probe(candidate)
	if probe == null:
		body.collision_layer = old_layer; body.collision_mask = old_mask
		message("这里没有安全落点，仍在携带中")
		return false
	probe.free()
	body.collision_layer = old_layer
	body.collision_mask = old_mask
	object.x = candidate.x; object.y = candidate.y
	body.position = Vector2(object.x, object.y)
	body.freeze = bool(carried_previous.get("freeze", false))
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0
	carried_id = ""
	carried_previous.clear()
	message("已放下部件")
	return true

func _carry_probe(object: Dictionary) -> RigidBody2D:
	var node: RigidBody2D = build_object_scene.instantiate()
	node.setup(object)
	if node.get_child_count() == 0:
		node.free()
		return null
	var clearance := PaperSpawnClearance.resolve(self, node, object)
	if not clearance.valid:
		node.free()
		return null
	return node
func cooperation_action(id:String,enabled:bool)->void:
	if network_session==null:message("请先进入双人房间");return
	for object in objects:
		if object.get("id","")==id:
			network_session.send_op("collaborate",{"id":id,"version":object.version,"enabled":enabled})
			cooperation_panel.notice_label.text="正在等待服务器确认协作许可…"
			return
func receive_cooperation(state:Dictionary)->void:
	if int(state.get("version",0))<cooperation_version:return
	cooperation_version=int(state.get("version",0));cooperation=state.duplicate(true)
	if selected>=0 and selected<objects.size() and drag!=null and not can_cooperate(objects[selected]):
		# Cancelling a revoked drag must never send _finish_drag's move request.
		drag=null;selected=-1;connection_source.clear();message("协作许可或编辑者已变化，请重新选择部件")

func close_personal_overlay() -> void:
	if cooperation_open():cooperation_panel.close()
	elif lab_open(): weapon_lab_panel.close()
	elif experience != null: experience.close()

func open_weapon_lab() -> void:
	if weapon_lab_panel != null: weapon_lab_panel.open()

func weapon_lab_action(data: Dictionary) -> void:
	if network_session != null:
		network_session.send_op("weapon_lab", data)
		weapon_lab_panel.notice("正在等待服务器确认试打操作…")
		return
	var action: String = data.get("action", "")
	var result: Dictionary = {"ok":true,"error":"","action":action}
	match action:
		"start": result=weapon_lab.start(float(data.get("distance",1.2)))
		"keep": result=weapon_lab.keep()
		"reset": weapon_lab.reset()
		"stop": weapon_lab.stop()
		_: result={"ok":false,"error":"试打动作无效"}
	result.action=action
	weapon_lab_receipt(result)

func weapon_lab_receipt(result: Dictionary) -> void:
	var text: String = result.get("error", "") if not result.get("ok",false) else {"start":"试靶已布置 · 关面板后用自己的武器试打", "keep":"已保留当前实测方案作为对照", "reset":"已清空本轮记录，保留对照", "stop":"已撤下试靶，原作品保留"}.get(result.get("action", ""), "试打操作已确认")
	message(text)
	if weapon_lab_panel != null:
		weapon_lab_panel.notice(text)
		weapon_lab_panel.refresh()
		if result.get("ok",false) and result.get("action")=="start": weapon_lab_panel.close()

func refine_weapon() -> bool:
	var error := ""
	if equipped_weapon.get("paths",[]).is_empty() or combat.bow_equipped: error="请先装备自己的手绘武器；试用短弓先按Q返回"
	elif not (draft if draw_mode==2 else mode_drafts.get(2,[])).is_empty(): error="武器画布已有草稿，已保留；请先确认或主动清空"
	if not error.is_empty():
		message(error)
		if weapon_lab_panel != null: weapon_lab_panel.notice(error)
		return false
	set_draw_mode(2)
	var offset: Vector2 = player.position + Vector2(facing*1.4,1.0) - equipped_weapon.get("grip",Vector2.ZERO)
	draft=[]
	for path in equipped_weapon.paths:
		var points: Array=[]
		for p in path.points: points.append(p+offset)
		draft.append({"points":points})
	mode_drafts[2]=_clone(draft)
	refine_weapon_type=PaperWeaponTypes.kind(equipped_weapon)
	refine_model_fill=equipped_weapon.get("model_fill",false)
	message("原装备保留 · 已复制完整笔迹；可补画，再按3重选握点与类型")
	refresh_buttons()
	return true

func bridge_trial_action(action: String) -> void:
	if medieval_world == null or action not in ["prepare","start"]: return
	if network_session != null:
		network_session.send_op("bridge_trial",{"action":action})
		return
	if player.position.distance_to(Vector2(133.5,5.2)) > 12:
		message("请走近磨坊渡口的试桥台")
		return
	var result: Dictionary = medieval_world.bridge_trial.call(action)
	if not result.ok: message(result.error)
	else: message("试桥台已布置 · 先画出桥，再投放货物" if action == "prepare" else "货物出发 · 让桥真正承住它")

func screen_to_world(screen_pos: Vector2) -> Vector2:
	if knowledge_world != null and knowledge_world.overview:
		return knowledge_world.overview_to_world(screen_pos)
	var viewport_size := get_viewport().get_visible_rect().size
	if feedback != null: screen_pos -= feedback.screen_offset
	return Vector2(
		camera_x + (screen_pos.x - viewport_size.x * 0.5) / PIXELS_PER_UNIT,
		(viewport_size.y - _ground_margin() + GROUND_Y * PIXELS_PER_UNIT - screen_pos.y) / PIXELS_PER_UNIT + camera_y
	)

func select_world(kind: String) -> void:
	if kind not in ["paper", "knowledge-v1", "medieval-v1", "nature-v1"]: return
	if weapon_lab != null: weapon_lab.stop()
	if structure_links != null: structure_links.clear()
	if medieval_world != null:
		remove_child(medieval_world)
		medieval_world.queue_free()
		medieval_world = null
	if knowledge_world != null:
		remove_child(knowledge_world)
		knowledge_world.queue_free()
		knowledge_world = null
	for body in ground_chunks.values(): body.queue_free()
	ground_chunks.clear()
	world_kind = kind
	camera_y = 0
	if kind in ["knowledge-v1", "nature-v1"]:
		knowledge_world = preload("res://scripts/nature_world.gd").new() if kind == "nature-v1" else preload("res://scripts/knowledge_world.gd").new()
		knowledge_world.game = self
		add_child(knowledge_world)
		_resize_world()
	elif kind == "medieval-v1":
		medieval_world = preload("res://scripts/medieval_world.gd").new()
		medieval_world.game = self
		add_child(medieval_world)
		paper = "draft"
		camera_x = 3
		player.reset_movement()
		player.position = medieval_world.safe_spawn_position(3)
		player.linear_velocity = Vector2.ZERO
		PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, player.position))
		onboarding.visible = false
		onboarding.persist = false
		if combat != null: combat.set_natives(false)
		_resize_world()
		get_window().title = "纸间 · 墨线边境"
	else:
		_resize_world()
	if map_controls != null: map_controls.refresh()
	_update_world_chunks()
	get_window().title = "纸间 · " + PaperExperience.VERSION + " · " + ("自然沙盒（实验）" if kind == "nature-v1" else "课本文字世界" if kind == "knowledge-v1" else "墨线边境" if kind == "medieval-v1" else "纸面创作")

func change_map(kind: String) -> void:
	if network_session != null:
		message("房间地图固定；退出后可另开房间")
		return
	if kind not in ["knowledge-v1", "nature-v1", "medieval-v1"] or kind == world_kind: return
	retain_active_stroke()
	cancel_pointer()
	sync_objects()
	map_workspaces[world_kind] = {"objects": _clone(objects), "world": _world_details(), "player_x": player.position.x, "camera_x": camera_x}
	mode_drafts[draw_mode] = _clone(draft)
	cancel_weapon_grip(false)
	pending_building = {}
	placement_preview = {}
	placing_blueprint_id = -1
	selected = -1
	var saved: Dictionary = map_workspaces.get(kind, {})
	select_world(kind)
	objects = _clone(saved.get("objects", []))
	_rebuild_objects()
	structure_links.restore(saved.get("world", {}).get("connections", []))
	if not saved.is_empty():
		if knowledge_world != null: knowledge_world.restore_state(saved.world)
		if medieval_world != null: medieval_world.restore_state(saved.world.get("entities", []),int(saved.world.get("terrain_version",1)),int(saved.world.get("content_version",1)),saved.world.get("bridge_trial",{}))
		player.position = Vector2(saved.player_x, saved.world.player_y)
		if medieval_world != null and int(saved.world.get("terrain_version",1)) < medieval_world.terrain.VERSION:
			migrate_medieval_objects(objects, int(saved.world.get("terrain_version",1)))
			_rebuild_objects()
			player.position = medieval_world.terrain.upgrade_position(player.position, int(saved.world.get("terrain_version",1)))
			player.position=medieval_world.safe_legacy_player_position(player.position)
		PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, player.position))
		camera_x = saved.camera_x
		camera_y = saved.world.camera_y
		if medieval_world != null and int(saved.world.get("terrain_version",1)) < medieval_world.terrain.VERSION:
			camera_y += medieval_world.terrain.upgrade_position(Vector2(player.position.x, 0), int(saved.world.get("terrain_version",1))).y
	player.reset_movement()
	player.linear_velocity = Vector2.ZERO
	wall_climb.reset(player)
	combat.reset()
	undo_stack.clear()
	redo_stack.clear()
	if experience != null: experience.close()
	refresh_buttons()
	message("已切换地图 · 各地图搭建分别保留，图纸与装备共用；作品菜单可保存")

func migrate_medieval_objects(records: Array, from_version: int = 1) -> void:
	if medieval_world == null: return
	for object in records:
		var at := Vector2(float(object.x), float(object.get("y",GROUND_Y)))
		object.y = medieval_world.terrain.upgrade_position(at, from_version).y

func respawn_medieval() -> void:
	if network_session != null:
		network_session.send_op("respawn")
		return
	if medieval_world == null: return
	retain_active_stroke()
	cancel_pointer()
	player.reset_movement()
	player.position=medieval_world.safe_spawn_position(player.position.x)
	player.linear_velocity=Vector2.ZERO
	PhysicsServer2D.body_set_state(player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,player.position))
	camera_x=player.position.x
	camera_y=camera_target_y()
	if wall_climb!=null: wall_climb.reset(player)
	if combat!=null: combat.cancel_draw()

func ground_height_at(x: float) -> float:
	if medieval_world != null: return medieval_world.travel_height(x)
	return knowledge_world.surface_height(x) if knowledge_world != null else GROUND_Y

func camera_target_y() -> float:
	if toolbar == null or player == null: return 0.0
	var size := get_viewport_rect().size
	var amount := PaperGuiScale.factor(size)
	var logical := size / amount
	var compact := logical.x < 600 or logical.y < 500
	# Camera framing uses the same physical rectangles that receive GUI input.
	var top: float = toolbar.bottom.get_global_rect().end.y if compact else toolbar.header.get_global_rect().end.y
	if knowledge_world != null and knowledge_world.controls != null and knowledge_world.controls.panel.is_visible_in_tree():
		top = maxf(top, knowledge_world.controls.panel.get_global_rect().end.y)
	elif map_controls != null and map_controls.panel != null and map_controls.panel.is_visible_in_tree() and not (compact and logical.y < 500 and not toolbar.navigation_open):
		top = maxf(top, map_controls.panel.get_global_rect().end.y)
	var bottom: float = size.y - 100 * amount if compact else toolbar.bottom.get_global_rect().position.y
	if touch_controls != null and touch_controls.enabled():
		bottom = minf(bottom, touch_controls.attack_rect.position.y - 8 * amount)
	var playable := maxf(30 * amount, bottom - top)
	# Keep medieval roads low, with room to see and climb the routes above.
	var target_pixel := top + playable * (0.76 if medieval_world != null else 0.5)
	# In the short landscape viewport, the side event panel leaves a lower
	# central lane free. Keep both the player and elevated load test in that lane.
	if medieval_world != null and compact and logical.y < 500 and not toolbar.navigation_open and player.position.distance_to(Vector2(133.5,5.2)) <= 12:
		target_pixel = minf(size.y-45*amount,maxf(target_pixel,top+100*amount))
	return player.position.y - GROUND_Y + (target_pixel - size.y + _ground_margin()) / PIXELS_PER_UNIT

func terrain_spawn(x: float) -> Vector2:
	if medieval_world != null: return medieval_world.safe_spawn_position(x)
	if knowledge_world != null:
		x = clampf(x, knowledge_world.terrain_rects.front().position.x + 0.6, knowledge_world.terrain_rects.back().end.x - 0.6)
	return Vector2(x, ground_height_at(x) + 0.7)

func terrain_hit(a: Vector2, b: Vector2) -> Dictionary:
	if medieval_world != null:
		var nearest:Dictionary={}
		for polygon in medieval_world.terrain.collision_geometry:
			var hit:Dictionary=medieval_world._polygon_segment(a,b,polygon)
			if not hit.is_empty() and hit.time<nearest.get("time",INF): nearest=hit
		return nearest
	var query := PhysicsRayQueryParameters2D.create(a, b, 1)
	query.hit_from_inside = true
	var excluded: Array[RID] = []
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	while not hit.is_empty() and hit.collider is BuildObject:
		excluded.append(hit.collider.get_rid())
		query.exclude = excluded
		hit = get_world_2d().direct_space_state.intersect_ray(query)
	return hit

func world_save_state() -> Dictionary:
	var state := _world_details()
	state.maps = _clone(map_workspaces)
	state.maps.erase(world_kind)
	return state

func _world_details() -> Dictionary:
	var state := {"id": world_kind, "player_y": player.position.y, "camera_y": camera_y}
	state.connections = structure_links.snapshot() if structure_links != null else []
	if knowledge_world != null:
		state.checkpoint = knowledge_world.checkpoint
		state.bookmarks = knowledge_world.collected.keys()
	if medieval_world != null:
		state.entities = medieval_world.save_state()
		state.terrain_version = medieval_world.terrain.VERSION
		state.content_version = medieval_world.CONTENT_VERSION
		state.bridge_trial = medieval_world.bridge_trial.snapshot()
	return state

func object_point(obj: Dictionary, p: Vector2) -> Vector2:
	var angle: float = obj.get("angle", 0.0)
	var c := cos(angle)
	var s := sin(angle)
	return Vector2(obj.x + p.x * c - p.y * s, obj.y + p.x * s + p.y * c)

func object_bounds(obj: Dictionary) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for path in obj.paths:
		for p in path.points:
			var pt := object_point(obj, p)
			min_x = min(min_x, pt.x)
			min_y = min(min_y, pt.y)
			max_x = max(max_x, pt.x)
			max_y = max(max_y, pt.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func message(text: String) -> void:
	if toolbar:
		toolbar.set_status(text)

func creation_ink_allowed(object: Dictionary) -> bool:
	if network_session != null: return true # Authority validates and commits the price.
	var price: float = PaperInkReserve.cost(object)
	if ink.can_spend(price): return true
	message("墨水不足，需要%d，当前%d；图形与旧武器已保留" % [price, ink.amount])
	return false

func charge_creation_ink(object: Dictionary) -> void:
	if network_session == null: ink.spend(PaperInkReserve.cost(object))

func celebrate_creation(object: Dictionary, label: String = "CREATED!", from_drawing:bool=true) -> void:
	if from_drawing and first_work!=null:first_work.note_created(object)
	if feedback != null:
		feedback.emit_event("create", object_bounds(object).get_center(), label)

func refresh_buttons() -> void:
	if toolbar:
		toolbar.update_buttons()

func _clone(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _clone(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_clone(item))
		return result
	return value

func snapshot() -> Dictionary:
	return {
		"objects": _clone(objects),
		"draft": _clone(draft),
		"paper": paper,
		"bag": _clone(bag),
		"selected_blueprint_id": selected_blueprint_id,
		"equipped_weapon": _clone(equipped_weapon),
		"mode_drafts": _clone(mode_drafts),
		"draw_mode": draw_mode,
		"sculpt_return_mode": sculpt_return_mode,
		"world": world_save_state(),
		"player_position": player.position,
		"camera_position": Vector2(camera_x, camera_y),
	}

func record(before: Variant = null) -> void:
	var snap: Dictionary = before if before else snapshot()
	undo_stack.append(snap)
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()

func restore(snap: Dictionary) -> void:
	var saved_world: Dictionary = snap.get("world", {"id": "paper"})
	if not preload("res://scripts/structure_links.gd").valid_state(saved_world.get("connections", []), snap.get("objects", [])):
		message("结构连接状态无效，当前作品已保留")
		return
	if saved_world.get("id", "paper") == "medieval-v1" and not preload("res://scripts/medieval_world.gd").validate_snapshot(saved_world):
		message("作品状态或版本无效，当前世界已保留")
		return
	map_workspaces = _clone(saved_world.get("maps", {}))
	if saved_world.id != world_kind:
		select_world(saved_world.id)
		if knowledge_world != null: knowledge_world.restore_state(saved_world)
		if medieval_world != null: medieval_world.restore_state(saved_world.get("entities", []),int(saved_world.get("terrain_version",1)),int(saved_world.get("content_version",1)),saved_world.get("bridge_trial",{}))
		player.position = snap.get("player_position", terrain_spawn(camera_x))
		if medieval_world != null and int(saved_world.get("terrain_version",1)) < medieval_world.terrain.VERSION:
			player.position = medieval_world.terrain.upgrade_position(player.position, int(saved_world.get("terrain_version",1)))
			player.position=medieval_world.safe_legacy_player_position(player.position)
		PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, player.position))
		var saved_camera: Vector2 = snap.get("camera_position", Vector2(player.position.x, 0))
		camera_x = saved_camera.x
		camera_y = saved_camera.y
		if medieval_world != null and int(saved_world.get("terrain_version",1)) < medieval_world.terrain.VERSION:
			camera_y += medieval_world.terrain.upgrade_position(Vector2(player.position.x, 0), int(saved_world.get("terrain_version",1))).y
	selecting_weapon_type = false
	if weapon_type_wheel != null: weapon_type_wheel.hide()
	selecting_weapon_grip = false
	selected_weapon_grip = null
	objects = _clone(snap.objects)
	if medieval_world != null and int(saved_world.get("terrain_version",1)) < medieval_world.terrain.VERSION: migrate_medieval_objects(objects, int(saved_world.get("terrain_version",1)))
	draft = _clone(snap.draft)
	building_wait = -1
	equipped_weapon = _clone(snap.get("equipped_weapon", {}))
	mode_drafts = _clone(snap.get("mode_drafts", {}))
	draw_mode = snap.get("draw_mode", draw_mode)
	sculpt_return_mode = snap.get("sculpt_return_mode", 1)
	pending_building = {}
	placement_preview = {}
	tool = "move" if draw_mode == 4 else "draw"
	paper = snap.paper
	bag = _clone(snap.bag)
	selected_blueprint_id = snap.selected_blueprint_id
	placing_blueprint_id = -1
	active_stroke = null
	pending_match = []
	preview_paths = null
	selected = -1
	drag = null
	carried_id = ""
	carried_previous.clear()
	_rebuild_objects()
	structure_links.restore(saved_world.get("connections", []))
	refresh_buttons()
	if backpack_ui:
		backpack_ui.refresh()

func undo() -> void:
	if network_session != null:
		network_session.send_op("undo")
		return
	if undo_stack.is_empty():
		message("没有可撤销的操作")
		return
	redo_stack.append(snapshot())
	restore(undo_stack.pop_back())
	message("已撤销")

func redo() -> void:
	if network_session != null:
		message("联机撤销逐件执行，暂不提供重做")
		return
	if redo_stack.is_empty():
		message("没有可重做的操作")
		return
	undo_stack.append(snapshot())
	restore(redo_stack.pop_back())
	message("已重做")

func clear_candidate() -> void:
	pending_match = []
	preview_paths = null
	candidate_index = 0
	refresh_buttons()

func toggle_bag() -> void:
	if personal_overlay_open(): return
	if not bag_open: retain_active_stroke()
	cancel_pointer()
	down_tap_timer = 0
	if touch_controls != null: touch_controls.reset()
	bag_open = not bag_open
	backpack_panel.visible = bag_open
	if bag_open:
		backpack_ui.refresh()

func select_blueprint(id: int) -> void:
	blueprint_selection_context += 1
	selected_blueprint_id = id
	backpack_ui.refresh()

func rename_blueprint(value: String) -> void:
	var entry := BlueprintBag.find_entry(bag, selected_blueprint_id)
	if entry.is_empty():
		message("先选择图纸")
		return
	var name := value.strip_edges()
	if name.is_empty():
		message("图纸名称不能为空")
		return
	if name.length() > 72:
		message("图纸名称过长")
		return
	record()
	entry.name = name
	backpack_ui.refresh()
	message("图纸已改名")

func favorite_blueprint() -> void:
	var entry := BlueprintBag.find_entry(bag, selected_blueprint_id)
	if entry.is_empty():
		message("先选择图纸")
		return
	record()
	entry.favorite = not entry.favorite
	backpack_ui.refresh()

func duplicate_blueprint() -> void:
	if selected_blueprint_id < 0:
		message("先选择图纸")
		return
	var before := snapshot()
	var result := BlueprintBag.duplicate_entry(bag, selected_blueprint_id)
	if result.error:
		message(result.error)
		return
	record(before)
	blueprint_selection_context += 1
	selected_blueprint_id = result.entry.id
	backpack_ui.refresh()
	message("已复制图纸")

func delete_blueprint() -> void:
	if selected_blueprint_id < 0:
		message("先选择图纸")
		return
	record()
	BlueprintBag.remove_entry(bag, selected_blueprint_id)
	blueprint_selection_context += 1
	selected_blueprint_id = -1
	backpack_ui.refresh()
	message("图纸已删除，纸上的建筑保留")

func equip_blueprint() -> void:
	var entry := BlueprintBag.find_entry(bag, selected_blueprint_id)
	if entry.is_empty():
		message("先选择图纸")
		return
	var chosen_weapon := BlueprintBag.make_object(entry, 0, 0) if entry.get("role", "") == "weapon" else {}
	if not chosen_weapon.is_empty() and equipped_weapon != chosen_weapon and not creation_ink_allowed(chosen_weapon): return
	cancel_weapon_grip(false)
	bag_open = false
	backpack_panel.visible = false
	if entry.get("role", "") == "weapon":
		record()
		if equipped_weapon != chosen_weapon: charge_creation_ink(chosen_weapon)
		equipped_weapon = chosen_weapon
		combat.bow_equipped = false
		combat.cancel_draw()
		feedback.emit_event("grip", player.position + Vector2(facing * 0.25, 0.1))
		message("已装备「" + entry.name + "」：右键攻击")
		return
	set_draw_mode(3 if entry.get("role", "") == "building" else 1)
	placing_blueprint_id = entry.id
	message("已拿起「" + entry.name + "」：左键点击纸面放置，Esc 取消")

func bind_hotbar(slot: int) -> void:
	if selected_blueprint_id < 0:
		message("先选择图纸，再绑定快捷格")
		return
	record()
	if BlueprintBag.bind_hotbar(bag, slot, selected_blueprint_id):
		backpack_ui.refresh()
		message("已将图纸绑定到快捷格 " + str(slot + 1))

func equip_hotbar(slot: int) -> void:
	var id: int = bag.hotbar[slot]
	var entry := BlueprintBag.find_entry(bag, id)
	if entry.is_empty():
		message("快捷格 " + str(slot + 1) + " 是空的")
		return
	selected_blueprint_id = id
	equip_blueprint()
	message("快捷格 " + str(slot + 1) + "：左键点击纸面摆放「" + entry.name + "」")

func place_blueprint(x: float, y: float) -> void:
	var entry := BlueprintBag.find_entry(bag, placing_blueprint_id)
	if entry.is_empty():
		placing_blueprint_id = -1
		return
	if objects.size() >= MAX_OBJECTS:
		message("纸面实体已达上限，请先删除一些")
		return
	var object := BlueprintBag.make_object(entry, x, y)
	var body := _drop_candidate(object)
	if body == null: return
	record()
	charge_creation_ink(object)
	objects.append(object)
	onboarding.note_built()
	object_nodes.append(_attach_body(body, object))
	selected = objects.size() - 1
	placing_blueprint_id = -1
	celebrate_creation(object,"CREATED!",false)
	message(_spawn_notice(body, "已按图纸摆放「" + entry.name + "」"))

func _grounded_spawn_y(paths: Array, requested_y: float, angle: float = 0.0) -> float:
	if knowledge_world != null: return requested_y
	var lowest := INF
	for path in paths:
		for point in path.points:
			lowest = minf(lowest, point.rotated(angle).y)
	if lowest == INF: return requested_y
	# Initial placement only: subsequent contact and rotation belong to the physics server.
	return maxf(requested_y, GROUND_Y - lowest + PaperShapePhysics.INK_RADIUS + 0.005)

func _build_physics_for_object(object: Dictionary) -> RigidBody2D:
	if medieval_world == null: object.y = _grounded_spawn_y(object.get("paths", []), float(object.get("y", GROUND_Y)), float(object.get("angle", 0)))
	var node := build_object_scene.instantiate()
	node.setup(object)
	return _attach_body(node, object)

func _attach_body(node: RigidBody2D, object: Dictionary) -> RigidBody2D:
	preload("res://scripts/structure_links.gd").ensure_key(object)
	add_child(node)
	if object.get("dynamic", true) and object.get("kind", "") == "ladder" and player != null:
		node.add_collision_exception_with(player)
	return node

func _drop_candidate(object: Dictionary) -> RigidBody2D:
	if network_session != null: return network_session.spawn_candidate(object)
	if not creation_ink_allowed(object): return null
	var node: RigidBody2D = build_object_scene.instantiate()
	node.setup(object)
	if Vector2(object.x, object.y).distance_to(player.position) > DrawingRules.BUILD_RANGE:
		node.free()
		message("离角色太远，请在 12 米内生成；草稿和图纸选择已保留")
		return null
	if node.get_child_count() == 0:
		node.free()
		message("没有有效的碰撞轮廓，笔迹已保留")
		return null
	var clearance := PaperSpawnClearance.resolve(self, node, object)
	if not clearance.valid:
		node.free()
		message("未找到合法落点，图形已保留；请检查作品范围或轮廓")
		return null
	var offset: Vector2 = clearance.offset
	object.x += offset.x
	object.y += offset.y
	node.position += offset
	node.set_meta("spawn_adjusted", not offset.is_zero_approx())
	node.set_meta("spawn_offset", offset)
	return node

func _spawn_notice(body: RigidBody2D, normal: String) -> String:
	return "已自动移到最近安全空位 · " + normal if body.get_meta("spawn_adjusted", false) else normal

func sync_objects() -> bool:
	for i in object_nodes.size():
		if i < objects.size() and object_nodes[i]:
			object_nodes[i].sync_to_data()
	return structure_links.step() if structure_links != null else false

func _update_world_chunks() -> void:
	if medieval_world != null:
		_update_object_activity()
		return
	if knowledge_world != null:
		knowledge_world._update_chunks()
		_update_object_activity()
		return
	var wanted := {}
	for x in physics_centers():
		var chunk_center := floori(float(x) / 16.0)
		for index in range(chunk_center - 4, chunk_center + 5): wanted[index] = true
	for index in wanted:
		if not ground_chunks.has(index):
			var ground := StaticBody2D.new()
			ground.position = Vector2(index * 16 + 8, GROUND_Y - 0.12)
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2(16.05, 0.24)
			shape.shape = box
			ground.add_child(shape)
			ground.collision_layer = 1
			add_child(ground)
			ground_chunks[index] = ground

	var to_remove := []
	for index in ground_chunks:
		if not wanted.has(index):
			ground_chunks[index].queue_free()
			to_remove.append(index)
	for index in to_remove:
		ground_chunks.erase(index)

	_update_object_activity()

func _update_object_activity() -> void:
	if network_session != null:
		for body in object_nodes: body.freeze = true
		return
	var active: Dictionary = structure_links.active_keys(network_centers()) if structure_links != null else {}
	var carried := carried_index()
	for i in object_nodes.size():
		if i < objects.size() and object_nodes[i]:
			var object: Dictionary = objects[i]
			if object.get("dynamic", true):
				var far := not active.has(object.get("structure_id", ""))
				if object_nodes[i] is RigidBody2D:
					object_nodes[i].freeze = far or (drag != null and selected == i) or carried == i

func _rebuild_objects() -> void:
	if structure_links != null:
		for id in structure_links.joints.keys(): structure_links._drop_joint(id)
	for node in object_nodes:
		if node:
			node.queue_free()
	object_nodes.clear()
	for object in objects:
		object_nodes.append(_build_physics_for_object(object))
	if structure_links != null: structure_links.rebuild()

func toggle_mode() -> void:
	if mode == "build" and draft.size() > 0:
		message("请先生成待处理的笔画，再开始试玩")
		return
	mode = "play" if mode == "build" else "build"
	active_stroke = null
	_finish_drag()
	clear_candidate()
	if mode == "play":
		if not has_played:
			player.position = terrain_spawn(camera_x - 5.6)
			has_played = true
		player.linear_velocity = Vector2(0, player.linear_velocity.y)
		player.freeze = false
		onboarding.note_play(player.position.x)
		message("试玩开始：走进你画的城堡")
	else:
		player.linear_velocity = Vector2.ZERO
		message("建造模式：可继续画、选择和移动部件")
	refresh_buttons()

func pan_camera(distance: float) -> void:
	if mode != "build":
		return
	camera_x += distance
	_update_world_chunks()

func _track_page() -> void:
	var page := int(floor(camera_x / 20.0))
	if page != last_page:
		last_page = page
		flip_timer = 0.36

func toggle_tool() -> void:
	if mode != "build":
		message("请先返回建造模式")
		return
	_finish_drag()
	tool = "move" if tool == "draw" else "draw"
	active_stroke = null
	message("移动：选中并拖拽部件" if tool == "move" else "画笔：拖动鼠标描线")
	refresh_buttons()

func toggle_generator() -> void:
	creation_context += 1
	generator = "library" if generator == "own" else "own"
	clear_candidate()
	message("画完后按相近形状推荐素材" if generator == "library" else "将保留你的原始笔迹")
	refresh_buttons()

func delete_selected() -> void:
	if network_session != null:
		if selected >= 0 and selected < objects.size():
			if objects[selected].get("author","")!=network_session.player_id:message("拆除仍归作者，协作只允许搬动／连接");return
			network_session.send_op("delete", {"id":objects[selected].id,"version":objects[selected].version})
			drag = null
		return
	if selected < 0:
		message("先用移动工具选中一个部件")
		return
	_finish_drag()
	record()
	objects.remove_at(selected)
	selected = -1
	_rebuild_objects()
	message("部件已删除")

func pointer_down(screen_pos: Vector2) -> void:
	if network_session != null and network_session.local_dead_time > 0: return
	if personal_overlay_open(): return
	if map_controls != null and map_controls.blocks_canvas(screen_pos): return
	if knowledge_world != null and knowledge_world.overview:
		if not toolbar.blocks_canvas(screen_pos):
			knowledge_world.visit(clampi(int(floor(screen_to_world(screen_pos).x / knowledge_world.STEP)), 0, 5))
		return
	if bag_open:
		return
	var p := screen_to_world(screen_pos)
	aim_world = p
	if draw_mode == 4 and connection_tool != "move":
		connection_pointer(p)
		return
	if selecting_weapon_type: return
	if selecting_weapon_grip:
		select_weapon_grip(p)
		return
	if not pending_building.is_empty():
		place_pending(p)
		return
	if placing_blueprint_id >= 0:
		place_blueprint(p.x, p.y)
		return
	if draw_mode != 4:
		if draft.size() >= MAX_DRAW_STROKES:
			message("当前作品笔画已达上限，请确认生成后继续画下一件")
			return
		building_wait = -1
		creation_context += 1
		active_stroke = {"points": [p]}
		draw_cursor = screen_pos
		pose = "draw"
		selected = -1
		clear_candidate()
	else:
		selected = -1
		for index in range(objects.size() - 1, -1, -1):
			var object: Dictionary = objects[index]
			var bounds := object_bounds(object)
			var margin := 0.18
			if p.x >= bounds.position.x - margin and p.x <= bounds.end.x + margin \
				and p.y >= bounds.position.y - margin and p.y <= bounds.end.y + margin:
				if not can_cooperate(object):
					message("请作者先在双人协作中开放部件，或等朋友结束编辑")
					return
				selected = index
				if structure_links.linked(object.get("structure_id", "")):
					message("部件已有连接，先解除连接再移动；仍可拆除")
					return
				if network_session != null: network_session.send_op("lock", {"id":object.id,"version":object.version})
				drag = {
					"start": p,
					"origin_x": object.x,
					"origin_y": object.y,
					"before": snapshot(),
					"moved": false,
				}
				var node: RigidBody2D = object_nodes[index]
				if node:
					node.freeze = true
					node.linear_velocity = Vector2.ZERO
				node.angular_velocity = 0
				message("已选中部件；拖动移动，或点击删除")
				break

func pointer_move(screen_pos: Vector2) -> void:
	var p := screen_to_world(screen_pos)
	aim_world = p
	if selecting_weapon_grip:
		grip_hover = p
		return
	if not pending_building.is_empty():
		placement_world = p
		update_placement()
		return
	if active_stroke:
		draw_cursor = screen_pos
		var pts: Array = active_stroke.points
		_append_ink_point(pts, p, 0.06)
	elif drag and selected >= 0:
		var object: Dictionary = objects[selected]
		var desired: Vector2 = Vector2(drag.origin_x, drag.origin_y) + p - drag.start
		if object.get("role", "") == "building" and not object.get("dynamic", true):
			var others: Array = objects.duplicate()
			others.remove_at(selected)
			var placed := DrawingRules.placement(object, desired, others, player.position)
			if not placed.valid: return
			desired = Vector2(placed.object.x, placed.object.y)
		object.x = desired.x
		object.y = desired.y
		var node: Node2D = object_nodes[selected]
		if node:
			node.position = Vector2(object.x, object.y)
		if absf(object.x - drag.origin_x) + absf(object.y - drag.origin_y) > 0.02:
			drag.moved = true

func _finish_drag() -> void:
	if not drag:
		return
	if network_session != null:
		if selected >= 0 and selected < objects.size() and drag.moved:
			var online_object: Dictionary = objects[selected]
			network_session.send_op("move", {"id":online_object.id,"version":online_object.version,"position":Vector2(online_object.x,online_object.y)})
		drag = null
		return
	if drag.moved:
		record(drag.before)
		if first_work!=null and selected>=0 and selected<objects.size():first_work.note_moved(objects[selected],Vector2(drag.origin_x,drag.origin_y),Vector2(objects[selected].x,objects[selected].y))
	var node: RigidBody2D = object_nodes[selected] if selected >= 0 and selected < object_nodes.size() else null
	var object: Dictionary = objects[selected] if selected >= 0 and selected < objects.size() else {}
	if node and not object.is_empty():
		node.freeze = not object.get("dynamic", true)
		node.linear_velocity = Vector2.ZERO
		node.angular_velocity = 0
		node.sleeping = false
	drag = null

func _append_ink_point(points: Array, point: Vector2, spacing: float) -> void:
	if not points.is_empty() and points.back().distance_to(point) < spacing: return
	# Accepted ink is immutable: continuing a stroke must not erase earlier detail.
	points.append(point)

func pointer_up(screen_pos: Vector2) -> void:
	if active_stroke:
		var pts: Array = active_stroke.points
		var p := screen_to_world(screen_pos)
		_append_ink_point(pts, p, 0.03)
		var length := 0.0
		for i in range(1, pts.size()):
			length += pts[i - 1].distance_to(pts[i])
		if length < 0.25:
			message("笔画太短，请画长一点")
		elif pts.size() >= 4 and pts[0].distance_to(pts[pts.size() - 1]) < 0.18:
			record()
			pts.append(pts[0])
			draft.append(active_stroke)
			onboarding.note_drawn()
			message("已闭合轮廓；可继续画或生成")
		else:
			record()
			draft.append(active_stroke)
			onboarding.note_drawn()
			message("已记录第 " + str(draft.size()) + " 笔；可继续画或生成")
		if length>=.25 and first_work!=null:first_work.note_drawn(draw_mode)
		if length >= 0.25 and feedback != null:
			feedback.emit_event("stroke", p)
		active_stroke = null
		var artist_point := screen_to_world(screen_pos)
		artist_world = Vector2(artist_point.x - facing * 27 / PIXELS_PER_UNIT, artist_point.y - 20 / PIXELS_PER_UNIT)
		draw_cursor = null
		pose = "idle"
		if draw_mode == 3 and not draft.is_empty():
			building_wait = -1
			message("可继续多笔补画 · 再按 2 确认生成")
		if draw_mode == 5:
			message("自动塑形 · 已画 %d 笔 · 可继续补画，再按 5 确认" % draft.size())
	elif drag:
		_finish_drag()

func solidify(screen_pos: Vector2) -> void:
	if draw_mode in [2, 3, 5]:
		if active_stroke: pointer_up(screen_pos)
		generate()
		return
	if bag_open:
		return
	if active_stroke:
		pointer_up(screen_pos)
	if draft.is_empty():
		message("先按住左键画出笔画")
		return
	if generator == "own":
		generate()
	else:
		if pending_match.is_empty():
			generate()
		if not pending_match.is_empty():
			confirm_candidate()

func make_own_object() -> Dictionary:
	var b := ShapeMatcher.bounds(draft)
	if b.is_empty() or b.count < 2:
		return {}
	var cx: float = (float(b.min_x) + float(b.max_x)) * 0.5
	var cy: float = (float(b.min_y) + float(b.max_y)) * 0.5
	var paths: Array = []
	var segments := 0
	var vertical_strokes := 0
	var horizontal_strokes := 0
	for stroke in draft:
		var points: Array = []
		for p in stroke.points:
			points.append(Vector2(p.x - cx, p.y - cy))
		var first: Vector2 = stroke.points[0]
		var last: Vector2 = stroke.points[stroke.points.size() - 1]
		var dx := absf(last.x - first.x)
		var dy := absf(last.y - first.y)
		if dx < 0.3 and dy > 0.7:
			vertical_strokes += 1
		if dy < 0.18 and dx > 0.3:
			horizontal_strokes += 1
		segments += points.size() - 1
		paths.append({"points": points, "collision": true})
	if segments < 1:
		return {}
	var is_ladder: bool = float(b.height) > 1.2 and float(b.width) < 1.5 and vertical_strokes >= 2 and horizontal_strokes >= 2
	if is_ladder:
		for path in paths:
			path.collision = false
	return {
		"source": "own",
		"kind": "ladder" if is_ladder else "freehand",
		"x": cx, "y": cy,
		"paths": paths,
		"dynamic": true,
		"angle": 0.0,
	}

func generate() -> void:
	if bag_open: return
	if selecting_weapon_type:
		if selected_weapon_grip != null: equip_weapon_at(selected_weapon_grip)
		return
	if selecting_weapon_grip:
		if selected_weapon_grip != null:
			selecting_weapon_type = true
			weapon_type_wheel.show()
			combat.cancel_draw()
			message("选择剑、锤、弓、长枪或火枪 · 再按 3 确认装备")
			refresh_buttons()
		else:
			message("先点击武器笔迹上的握持位置，再按 3 确认；Esc 返回绘画")
		return
	if active_stroke: pointer_up(draw_cursor if draw_cursor != null else get_viewport().get_mouse_position())
	if not pending_building.is_empty():
		place_pending(placement_world)
		return
	if draw_mode == 4: return
	if draft.is_empty():
		message("先在纸上画几笔")
		return
	var point_count := 0
	for stroke in draft: point_count += stroke.points.size()
	if point_count > DrawingRules.MAX_POINTS:
		message("这件作品笔迹过多，请拆成多件生成；完整草稿已保留")
		return
	if objects.size() >= MAX_OBJECTS:
		message("纸面实体已达上限，请先删除一些")
		return
	if draw_mode == 2:
		create_weapon()
		return
	if draw_mode == 3:
		release_building()
		return
	if draw_mode == 5:
		confirm_sculpt()
		return
	if draw_mode == 1 and not pending_match.is_empty():
		confirm_candidate()
		return
	if generator == "own":
		var object := make_own_object()
		if object.is_empty():
			message("笔画无效，请再画完整一些")
			return
		var body := _drop_candidate(object)
		if body == null: return
		var before := snapshot()
		var result := BlueprintBag.add_entry(bag, object)
		if result.error:
			body.free()
			message(result.error)
			return
		record(before)
		object.blueprint_id = result.entry.id
		charge_creation_ink(object)
		objects.append(object)
		onboarding.note_built()
		object_nodes.append(_attach_body(body, object))
		draft = []
		selected = objects.size() - 1
		selected_blueprint_id = result.entry.id
		backpack_ui.refresh()
		celebrate_creation(object)
		message(_spawn_notice(body, "已实体化；图纸已收入背包，物件正在下坠"))
	else:
		var result := ShapeMatcher.rank(draft)
		if result.error:
			message(result.error)
			return
		pending_match = result.ranked
		creation_context += 1
		candidate_index = 0
		_update_candidate()

func _update_candidate() -> void:
	if pending_match.is_empty():
		return
	var b := ShapeMatcher.bounds(draft)
	if b.is_empty():
		return
	var candidate: Dictionary = pending_match[candidate_index]
	preview_paths = ShapeMatcher.make_prefab(candidate.id, b)
	preview_x = (b.min_x + b.max_x) * 0.5
	preview_y = (b.min_y + b.max_y) * 0.5
	message("匹配到「" + candidate.label + "」；可换候选，再按 1 确认")
	refresh_buttons()

func next_candidate() -> void:
	if pending_match.is_empty():
		message("先在素材库模式点击生成部件")
		return
	creation_context += 1
	candidate_index = (candidate_index + 1) % pending_match.size()
	_update_candidate()

func confirm_candidate() -> void:
	if pending_match.is_empty() or preview_paths == null:
		message("没有待确认的素材")
		return
	if objects.size() >= MAX_OBJECTS:
		message("纸面实体已达上限，请先删除一些")
		return
	var candidate: Dictionary = pending_match[candidate_index]
	var object := {
		"source": "library", "kind": candidate.id,
		"x": preview_x, "y": preview_y,
		"paths": _clone(preview_paths),
		"dynamic": true, "angle": 0.0,
	}
	var body := _drop_candidate(object)
	if body == null: return
	var before := snapshot()
	var result := BlueprintBag.add_entry(bag, object)
	if result.error:
		body.free()
		message(result.error)
		return
	record(before)
	object.blueprint_id = result.entry.id
	charge_creation_ink(object)
	objects.append(object)
	onboarding.note_built()
	object_nodes.append(_attach_body(body, object))
	draft = []
	selected = objects.size() - 1
	selected_blueprint_id = result.entry.id
	clear_candidate()
	backpack_ui.refresh()
	celebrate_creation(object)
	message(_spawn_notice(body, "已实体化「" + candidate.label + "」；图纸已收入背包"))

func save_game() -> bool:
	if network_session != null:
		network_session.request_save()
		return false # Success is shown only after the server confirms.
	sync_objects()
	var player_x: float = player.position.x if player else -5.6
	var result := SaveStore.save_game(paper, objects, bag, camera_x, player_x, equipped_weapon, world_save_state())
	message(result.message)
	if first_work!=null:first_work.note_saved(result.ok)
	return result.ok

func load_game() -> void:
	if network_session != null:
		network_session.import_local()
		return
	var result := SaveStore.load_game("medieval-v1" if world_kind == "medieval-v1" else "")
	if result.error:
		message(result.error)
		return
	selecting_weapon_type = false
	if weapon_type_wheel != null: weapon_type_wheel.hide()
	selecting_weapon_grip = false
	selected_weapon_grip = null
	record()
	mode = "play"
	cancel_pointer()
	mode_drafts = {}
	building_wait = -1
	pending_building = {}
	placement_preview = {}
	equipped_weapon = result.data.get("equipped_weapon", {})
	var loaded_world: Dictionary = result.data.get("world", {"id": "paper"})
	map_workspaces = _clone(loaded_world.get("maps", {}))
	select_world(loaded_world.id)
	if knowledge_world != null: knowledge_world.restore_state(loaded_world)
	if medieval_world != null: medieval_world.restore_state(loaded_world.get("entities", []),int(loaded_world.get("terrain_version",1)),int(loaded_world.get("content_version",1)),loaded_world.get("bridge_trial",{}))
	player.reset_movement()
	player.linear_velocity = Vector2.ZERO
	player.gravity_scale = 1.0
	move_direction = 0
	paper = result.data.paper
	objects = result.data.objects
	if medieval_world != null and int(loaded_world.get("terrain_version",1)) < medieval_world.terrain.VERSION: migrate_medieval_objects(objects, int(loaded_world.get("terrain_version",1)))
	camera_x = result.data.get("cameraX", 0.0)
	camera_y = loaded_world.get("camera_y", 0.0)
	last_page = int(floor(camera_x / 20.0))
	bag = result.data.bag
	selected_blueprint_id = -1
	placing_blueprint_id = -1
	player.position = Vector2(result.data.get("playerX", camera_x - 5.6), loaded_world.get("player_y", GROUND_Y + 0.54))
	if medieval_world != null and int(loaded_world.get("terrain_version",1)) < medieval_world.terrain.VERSION:
		var source_version := int(loaded_world.get("terrain_version",1))
		player.position = medieval_world.terrain.upgrade_position(player.position, source_version)
		player.position=medieval_world.safe_legacy_player_position(player.position)
		camera_y += medieval_world.terrain.upgrade_position(Vector2(player.position.x, 0), source_version).y
	PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, player.position))
	last_player_x = player.position.x
	if combat != null: combat.reset()
	draft = []
	selected = -1
	carried_id = ""
	carried_previous.clear()
	clear_candidate()
	_rebuild_objects()
	_update_world_chunks()
	structure_links.restore(loaded_world.get("connections", []))
	backpack_ui.refresh()
	refresh_buttons()
	if not objects.is_empty(): onboarding.note_built()
	if first_work!=null:first_work.world_changed()
	message("已读取城堡：" + str(objects.size()) + " 个实体、" + str(bag.entries.size()) + " 张图纸")

func _assist_slope(direction: int) -> void:
	if direction == 0 or not player:
		return
	var ahead_x := player.position.x + float(direction) * 0.34
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(ahead_x, player.position.y + 0.45),
		Vector2(ahead_x, player.position.y - 0.75),
		1
	)
	var excluded: Array[RID] = [player.get_rid()]
	for body in player.get_collision_exceptions():
		if is_instance_valid(body): excluded.append(body.get_rid())
	query.exclude = excluded
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target_y: float = float(hit.position.y) + 0.31
	var rise := target_y - player.position.y
	if rise > 0.015 and rise <= 0.42:
		player.position.y = target_y
		player.linear_velocity = Vector2(player.linear_velocity.x, maxf(0.0, player.linear_velocity.y))

func _physics_process(delta: float) -> void:
	if network_session != null:
		network_session.tick(delta)
		return
	ink.step(delta)
	if weapon_lab != null: weapon_lab.step(delta)
	elapsed += delta
	flip_timer = max(0.0, flip_timer - delta)
	land_timer = max(0.0, land_timer - delta)
	climb_lock_timer = max(0.0, climb_lock_timer - delta)
	down_tap_timer = maxf(0.0, down_tap_timer - delta)
	if player: player.update_drop_through(delta)
	sync_objects()
	if medieval_world != null: medieval_world.step(delta)
	if first_work!=null:first_work.step(delta)
	if combat != null: combat.step(delta)
	if not pending_building.is_empty(): update_placement()
	update_carried_object()
	if personal_overlay_open():
		player.linear_velocity.x = 0
		move_direction = 0
		wall_climb.reset(player)
		down_tap_timer = 0
		down_was_down = Input.is_action_pressed("move_down")
		jump_was_down = Input.is_action_pressed("jump") or Input.is_action_pressed("move_up")
		if Input.is_action_just_pressed("cancel"): close_personal_overlay()
		if medieval_world != null: medieval_world.terrain.apply_water_body(player,delta)
		return

	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		wall_climb.reset(player)
		if player: player.linear_velocity.x = 0
		if medieval_world != null: medieval_world.terrain.apply_water_body(player,delta)
		down_tap_timer = 0
		down_was_down = Input.is_action_pressed("move_down")
		return
	if Input.is_action_just_pressed("toggle_bow") and not bag_open and not selecting_weapon_grip:
		combat.toggle_bow()
	if Input.is_action_just_pressed("toggle_natives") and not bag_open and medieval_world == null:
		combat.set_natives(not combat.natives_enabled)
		message("纸间土著开始游荡 · 刀碰刀、箭碰箭可以交击" if combat.natives_enabled else "纸间土著已离场")

	if Input.is_action_just_pressed("toggle_bag"):
		toggle_bag()
	if Input.is_action_just_pressed("cancel"):
		if bag_open:
			toggle_bag()
		else:
			cancel_pointer()
			selecting_weapon_type = false
			if weapon_type_wheel != null: weapon_type_wheel.hide()
			selecting_weapon_grip = false
			selected_weapon_grip = null
			placing_blueprint_id = -1
			pending_building = {}
			placement_preview = {}
			if draw_mode == 5: set_draw_mode(sculpt_return_mode)

	for slot in range(6):
		if Input.is_action_just_pressed("hotbar_" + str(slot + 1)):
			if Input.is_key_pressed(KEY_SHIFT):
				if bag_open: bind_hotbar(slot)
				else: equip_hotbar(slot)
			elif slot == 5:
				toggle_bag()
			elif not bag_open:
				# Number keys match toolbar order; internal weapon/building IDs stay stable.
				activate_draw_mode([1, 3, 2, 4, 5][slot])
	for entry in [["draw_free", 1], ["draw_building", 3], ["draw_weapon", 2], ["draw_edit", 4]]:
		if Input.is_action_just_pressed(entry[0]): activate_draw_mode(entry[1])
	if Input.is_action_just_pressed("auto_sculpt"):
		toggle_sculpt()
	elif Input.is_action_just_pressed("generate"): input_command("generate")
	if Input.is_action_just_pressed("attack"): attack()
	if Input.is_action_just_pressed("carry"): toggle_carry()
	if Input.is_action_just_pressed("delete_object") and draw_mode == 4: delete_selected()

	if not player:
		return
	if knowledge_world != null and knowledge_world.overview:
		player.linear_velocity.x = 0
		wall_climb.reset(player)
		return
	onboarding.note_play(player.position.x)
	if bag_open:
		player.linear_velocity = Vector2(0, player.linear_velocity.y)
		if medieval_world != null: medieval_world.terrain.apply_water_body(player,delta)
		wall_climb.reset(player)
		down_tap_timer = 0
		down_was_down = Input.is_action_pressed("move_down")
		return

	var stick: Vector2 = touch_controls.movement_vector() if touch_controls != null else Vector2.ZERO
	step_locomotion(delta, {
		"left": Input.is_action_pressed("move_left") or stick.x < -0.25,
		"right": Input.is_action_pressed("move_right") or stick.x > 0.25,
		"up": Input.is_action_pressed("move_up") or stick.y < -0.5,
		"down": Input.is_action_pressed("move_down") or stick.y > 0.5,
		"jump_pressed": Input.is_action_just_pressed("jump"),
	})

	var player_x := player.position.x
	onboarding.note_movement(player_x)
	walk_phase = fmod(walk_phase + absf(player_x - last_player_x) * PIXELS_PER_UNIT / 68.0, 1.0)
	last_player_x = player_x
	if active_stroke == null and drag == null and not selecting_weapon_grip:
		camera_x += (player_x - camera_x) * min(1.0, delta * 4.5)
		if knowledge_world != null or medieval_world != null:
			camera_y += (camera_target_y() - camera_y) * minf(1.0, delta * 3.5)
	_track_page()
	_update_world_chunks()

	if medieval_world != null:
		player.position.x = clampf(player.position.x, -4, medieval_world.LENGTH+4)
	if medieval_world != null and player.position.y < -10:
		respawn_medieval()
	elif knowledge_world != null and player.position.y < GROUND_Y - 4:
		knowledge_world.respawn()
	elif medieval_world == null and player.position.y < GROUND_Y - 4:
		player.reset_movement()
		player.position = Vector2(camera_x, GROUND_Y + 0.54)
		player.linear_velocity = Vector2.ZERO


func step_locomotion(delta: float, controls: Dictionary) -> void:
	var left := bool(controls.get("left", false))
	var right := bool(controls.get("right", false))
	var up := bool(controls.get("up", false))
	var down := bool(controls.get("down", false))
	var down_tapped := down and not down_was_down
	down_was_down = down
	var supported: bool = on_ground and not player.support_bodies().is_empty()
	if supported and player.linear_velocity.y <= 0.5:
		jumps_used = 0
	var dropped := false
	if down_tapped:
		if down_tap_timer > 0:
			down_tap_timer = 0
			if on_ground and not climbing: dropped = player.begin_drop_through()
		else:
			down_tap_timer = DOWN_DOUBLE_TAP_WINDOW
	if dropped:
		climbing = false
		climb_lock_timer = 0.25
		player.gravity_scale = 1
		player.linear_velocity.y = minf(player.linear_velocity.y, -3.0)
		jumps_used = 1 # Stepping/dropping off leaves one aerial jump.
	crouching = down and on_ground and not climbing
	var direction := (1 if right else 0) - (1 if left else 0)
	var vertical := (1 if up else 0) - (1 if down else 0)
	move_direction = direction
	if direction != 0:
		facing = direction

	var velocity := player.linear_velocity
	var ladder := _find_ladder()
	var jump_requested := bool(controls.get("jump_pressed", false)) or (up and not jump_was_down and not ladder and (not climbing or wall_climb.active))
	jump_was_down = up
	if ladder and climb_lock_timer == 0 and (vertical != 0 or climbing):
		climbing = true
		player.gravity_scale = 0
		var rail := Vector2(0, 1).rotated(float(ladder.get("angle", 0)))
		var ride_velocity := Vector2.ZERO
		var ladder_index: int = objects.find(ladder)
		if ladder_index >= 0 and ladder_index < object_nodes.size():
			var support: RigidBody2D = object_nodes[ladder_index]
			var offset := player.position - support.position
			ride_velocity = support.linear_velocity + Vector2(-offset.y, offset.x) * support.angular_velocity
		player.linear_velocity = ride_velocity + Vector2(direction * 2.3, 0) + rail * vertical * 3.0
		pose = "climb"
	else:
		climbing = false
		player.gravity_scale = 1
		player.linear_velocity = Vector2(direction * (2.3 if crouching else 4.6) + combat.player_push, velocity.y)
		if on_ground:
			_assist_slope(direction)

	if jump_requested and not dropped and (supported or climbing or wall_climb.active or jumps_used < 2):
		var from_wall: bool = wall_climb.active
		jumps_used = 1 if supported or climbing or from_wall else maxi(1, jumps_used) + 1
		climbing = false
		climb_lock_timer = 0.25
		player.gravity_scale = 1
		player.linear_velocity = Vector2(direction * 4.6, 7.8)
		if from_wall: wall_climb.jump_off(player)
		player.clear_foot_contacts()
		down_tap_timer = 0

	if not jump_requested:
		if ladder and climbing:
			wall_climb.reset()
		elif wall_climb.step(player,direction,delta,not down and not dropped and climb_lock_timer <= 0):
			climbing = true
			pose = "climb"

	if medieval_world != null: medieval_world.terrain.apply_water_body(player,delta)
	if not climbing:
		if not on_ground:
			pose = "jump" if player.linear_velocity.y >= 0 else "fall"
		elif direction != 0:
			pose = "walk"
		else:
			pose = "idle"


func _ready_server_world() -> void:
	player = preload("res://scenes/player.tscn").instantiate()
	player.game = self
	add_child(player)
	player.position = Vector2(-5.6, GROUND_Y + .54)
	player.freeze = true
	player.collision_layer = 0
	player.collision_mask = 0
	combat = PaperCombat.new(self)
	select_world(world_kind)
	if knowledge_world != null: knowledge_world.set_process(false)
	set_physics_process(false)

func network_centers() -> Array:
	var result: Array = [camera_x]
	for body in network_players:
		if is_instance_valid(body) and not body.freeze: result.append(body.position.x)
	return result

func physics_centers() -> Array:
	var centers := network_centers()
	if structure_links == null or structure_links.records.is_empty(): return centers
	var active: Dictionary = structure_links.active_keys(centers)
	var seen: Dictionary = {}
	for link in structure_links.records:
		for key in [link.a, link.b]:
			if not active.has(key) or seen.has(key): continue
			seen[key] = true
			var body = structure_links.body(key)
			if body != null: centers.append(body.position.x)
	return centers

func _find_ladder() -> Dictionary:
	for object in objects:
		if object.kind != "ladder": continue
		var local: Vector2 = (player.position - Vector2(object.x, object.y)).rotated(-float(object.get("angle", 0)))
		var bounds := ShapeMatcher.bounds(object.paths)
		if bounds.is_empty(): continue
		if local.x >= bounds.min_x - 0.25 and local.x <= bounds.max_x + 0.25 and local.y >= bounds.min_y - 0.4 and local.y <= bounds.max_y + 0.65:
			return object
	return {}

func set_draw_mode(slot: int) -> void:
	if slot < 1 or slot > 5 or bag_open: return
	if slot == draw_mode: return
	creation_context += 1
	if slot == 5: sculpt_return_mode = draw_mode
	selecting_weapon_type = false
	if weapon_type_wheel != null: weapon_type_wheel.hide()
	selecting_weapon_grip = false
	selected_weapon_grip = null
	if active_stroke != null and draw_cursor != null: pointer_up(draw_cursor)
	building_wait = -1
	cancel_pointer()
	mode_drafts[draw_mode] = _clone(draft)
	draw_mode = slot
	draft = _clone(mode_drafts.get(slot, []))
	tool = "move" if slot == 4 else "draw"
	placing_blueprint_id = -1
	pending_building = {}
	placement_preview = {}
	clear_candidate()
	selected = -1
	message(["", "自由造物：多笔画轮廓，再按 1 生成", "武器：画轮廓 → 3 选握点 → 3 选类型 → 3 装备", "建筑：多笔补画，再按 2 生成并落下，碰到文字会自动避让", "移动／拆除：按住已有造物拖动；选中后点拆除或按 Delete", "自动塑形：可画多笔，再按 5 规整并生成 · Esc 返回"][slot])
	refresh_buttons()

func activate_draw_mode(slot: int) -> void:
	if bag_open: return
	if draw_mode != slot:
		set_draw_mode(slot)
	elif slot != 4 and (selecting_weapon_grip or active_stroke != null or not draft.is_empty() or not pending_building.is_empty()):
		generate()

func toggle_sculpt() -> void:
	if bag_open: return
	if draw_mode != 5:
		set_draw_mode(5)
	else:
		generate()

func confirm_sculpt() -> void:
	var fitted := AutoSculpt.fit(draft)
	if not fitted.error.is_empty():
		message(fitted.error)
		return
	var object: Dictionary = fitted.object
	if Vector2(object.x, object.y).distance_to(player.position) > DrawingRules.BUILD_RANGE:
		message("离角色太远，走近后按 5；草稿已保留")
		return
	var body := _drop_candidate(object)
	if body == null: return
	var before := snapshot()
	var result := BlueprintBag.add_entry(bag, object)
	if result.error:
		body.free()
		message(result.error)
		return
	record(before)
	object.blueprint_id = result.entry.id
	charge_creation_ink(object)
	objects.append(object)
	object_nodes.append(_attach_body(body, object))
	selected_blueprint_id = result.entry.id
	draft = []
	mode_drafts[5] = []
	onboarding.note_built()
	backpack_ui.refresh()
	set_draw_mode(sculpt_return_mode)
	celebrate_creation(object, "SHAPED!")
	message(_spawn_notice(body, "已塑形成「%s」并收入图纸 · 5 再画一件 · 4 移动部件" % AutoSculpt.label(object.kind)))

func cancel_pointer() -> void:
	connection_source.clear()
	active_stroke = null
	draw_cursor = null
	_finish_drag()
	if carried_id != "" and network_session == null: drop_carried()

func set_connection_tool(value: String) -> void:
	if value not in ["move", "fixed", "hinge", "unlink"]: return
	_finish_drag()
	connection_source.clear()
	connection_tool = value
	selected = -1
	message({"move":"按住部件拖动；已连接部件先解除连接", "fixed":"固定连接：依次点两件相邻部件的接缝", "hinge":"转轴：依次点两件相邻部件的接缝，让它们自由转动", "unlink":"解除连接：点击纸面上的绿色连接点"}[value])
	refresh_buttons()

func connection_pointer(point: Vector2) -> void:
	if point.distance_to(player.position) > 12:
		message("请走近部件，在12米内连接")
		return
	if connection_tool == "unlink":
		var link: Dictionary = structure_links.at_point(point)
		if link.is_empty(): message("请点击绿色连接点"); return
		connection_action({"action":"unlink", "id":link.id})
		return
	var source_key: String = connection_source.get("key", "")
	var key: String = structure_links.pick(point, source_key)
	if key.is_empty(): message("请点在部件的实际材料上；Esc取消选点"); return
	var object: Dictionary = structure_links.object(key)
	if not can_cooperate(object):
		message("请作者先开放部件协作，或等朋友结束编辑")
		return
	if connection_source.is_empty():
		connection_source = {"key":key, "point":structure_links.body(key).to_local(point)}
		message("已选第一个锚点，点击相邻部件接缝；Esc取消")
		return
	var source = structure_links.body(source_key)
	if source == null: connection_source.clear(); message("原部件已不存在，请重新选择"); return
	var first: Vector2 = source.to_global(connection_source.point)
	if first.distance_to(point) > .5: message("两个锚点相距太远，请选同一接缝附近"); return
	connection_action({"action":"connect", "a":source_key, "b":key, "point":first.lerp(point,.5), "kind":connection_tool})
	connection_source.clear()

func connection_action(data: Dictionary) -> void:
	if network_session != null:
		network_session.send_op("structure_link", data)
		message("正在等待服务器确认连接…")
		return
	var before := snapshot()
	var result: Dictionary = structure_links.create(data.a,data.b,data.point,data.kind) if data.action == "connect" else structure_links.remove(data.id)
	if result.ok:
		record(before)
		message("转轴已连接 · 部件可以绕接缝转动" if data.get("kind", "") == "hinge" else "连接已解除 · 部件仍保留" if data.action == "unlink" else "固定连接完成 · 部件一起受力")
	else: message(result.error)

func retain_active_stroke() -> void:
	# Modal UI and focus loss finish valid ink as a draft, never as a world object.
	if active_stroke == null or active_stroke.points.is_empty(): return
	pointer_up(world_to_screen(active_stroke.points.back()))

func select_weapon_type(kind: String) -> void:
	if not selecting_weapon_type or not PaperWeaponTypes.valid(kind): return
	if selected_weapon_type != kind: creation_context += 1
	selected_weapon_type = kind
	refresh_buttons()

func create_weapon() -> void:
	if DrawingRules.weapon(draft).is_empty():
		message("画长一点，至少画出一条完整的武器轮廓")
		return
	creation_context += 1
	selecting_weapon_grip = true
	selecting_weapon_type = false
	selected_weapon_type = refine_weapon_type if PaperWeaponTypes.valid(refine_weapon_type) else "sword"
	refine_weapon_type = ""
	selected_weapon_grip = null
	grip_hover = draft[0].points[0]
	message("点击真实笔迹上的握持位置，再按 3 确认 · Esc 返回绘画")
	refresh_buttons()

func select_weapon_grip(point: Vector2) -> void:
	if not selecting_weapon_grip or selecting_weapon_type: return
	var snapped: Variant = PaperWeaponGrip.snap_point(draft, point)
	if snapped == null:
		message("这里没有武器笔迹，请点在线条上")
		return
	selected_weapon_grip = snapped
	creation_context += 1
	grip_hover = snapped
	if feedback != null: feedback.emit_event("grip", snapped)
	message("握持点已选中 · 可重新点选 · 3 选择武器类型")
	refresh_buttons()

func cancel_weapon_grip(show_message: bool = true) -> void:
	creation_context += 1
	selecting_weapon_type = false
	if weapon_type_wheel != null: weapon_type_wheel.hide()
	selecting_weapon_grip = false
	selected_weapon_grip = null
	if show_message: message("已返回绘画，笔迹保留")
	refresh_buttons()

func equip_weapon_at(point: Vector2) -> void:
	if not selecting_weapon_grip or not selecting_weapon_type: return
	var weapon := PaperWeaponGrip.make_weapon(draft, point)
	if weapon.is_empty():
		message("请点在武器轮廓上，选择手掌握住的位置")
		return
	weapon.weapon_type = selected_weapon_type
	if refine_model_fill != null: weapon.model_fill = refine_model_fill
	if network_session != null:
		network_session.equip_drawing(weapon)
		return
	if not creation_ink_allowed(weapon): return
	var before := snapshot()
	var result := BlueprintBag.add_entry(bag, weapon)
	if result.error:
		message(result.error)
		return
	record(before)
	weapon.blueprint_id = result.entry.id
	charge_creation_ink(weapon)
	equipped_weapon = weapon
	refine_model_fill = null
	combat.bow_equipped = false
	combat.cancel_draw()
	selecting_weapon_type = false
	if weapon_type_wheel != null: weapon_type_wheel.hide()
	selecting_weapon_grip = false
	selected_weapon_grip = null
	draft = []
	mode_drafts[draw_mode] = []
	selected_blueprint_id = result.entry.id
	onboarding.note_built()
	backpack_ui.refresh()
	refresh_buttons()
	if feedback != null: feedback.emit_event("create", player.position + Vector2(facing * 0.25, 0.1), "FORGED!")
	message(PaperWeaponTypes.label(weapon) + "已装备 · 图纸已保存 · 右键 / R 攻击")

func prepare_building() -> void:
	creation_context += 1
	pending_building = DrawingRules.building(draft, build_kind)
	if pending_building.is_empty():
		message("请画出完整的建筑轮廓")
		return
	placement_world = Vector2(pending_building.x, pending_building.y)
	update_placement()
	message("%s · %s" % [BlueprintBag.NAMES.get(pending_building.kind, "手绘建筑"), placement_preview.reason])

func update_placement() -> void:
	if pending_building.is_empty(): return
	placement_preview = DrawingRules.placement(pending_building, placement_world, objects, player.position)

func place_pending(pos: Vector2) -> void:
	if pending_building.is_empty(): return
	placement_world = pos
	update_placement()
	if not placement_preview.valid:
		message(placement_preview.reason)
		return
	if objects.size() >= MAX_OBJECTS:
		message("实体已达上限，请先拆除一些")
		return
	var before := snapshot()
	var object: Dictionary = _clone(placement_preview.object)
	if not creation_ink_allowed(object): return
	var result := BlueprintBag.add_entry(bag, object)
	if result.error:
		message(result.error)
		return
	record(before)
	object.blueprint_id = result.entry.id
	charge_creation_ink(object)
	objects.append(object)
	object_nodes.append(_build_physics_for_object(object))
	selected_blueprint_id = result.entry.id
	pending_building = {}
	placement_preview = {}
	draft = []
	mode_drafts[draw_mode] = []
	onboarding.note_built()
	backpack_ui.refresh()
	celebrate_creation(object)
	message("结构已固定：可以站立、攀爬或挡住练习弹丸")

func input_command(command: String) -> void:
	if bag_open or (personal_overlay_open()): return
	if command == "generate": generate()
	elif command == "secondary":
		if active_stroke or not draft.is_empty() or not pending_building.is_empty(): generate()
		else: attack()

func attack() -> void:
	if bag_open or selecting_weapon_grip or (personal_overlay_open()): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var origin: Vector2 = player.position + (Vector2(0,.43) if combat.is_bow() or combat.is_firearm() else Vector2.ZERO)
	if network_session != null:
		network_session.send_op("attack", {"direction": aim_world - origin})
		return
	if combat != null: combat.attack(aim_world - origin)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN] and network_session != null: network_session.focus_active = true
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if network_session != null: network_session.focus_active = false
		wall_climb.reset(player)
		if combat != null: combat.cancel_draw()
		building_wait = -1
		retain_active_stroke()
		cancel_pointer()
		jump_was_down = false
		down_was_down = false
		down_tap_timer = 0
		if touch_controls != null: touch_controls.reset()

func _ground_margin() -> float:
	var viewport := get_viewport().get_visible_rect().size
	var amount := PaperGuiScale.factor(viewport)
	var logical := viewport / amount
	var margin := 112.0 if logical.y < 500 else 170.0 if logical.x < 600 else 190.0
	# The combined tool dock is taller than the old actions-only strip. Flat
	# legacy worlds have no following camera, so reserve its actual height.
	if toolbar != null and toolbar.bottom != null and logical.x >= 600 and logical.y >= 500 and medieval_world == null and knowledge_world == null:
		margin = maxf(margin, toolbar.bottom.size.y + 52)
	return margin * amount

func _resize_world() -> void:
	cancel_pointer()
	var amount := PaperGuiScale.factor(get_viewport_rect().size)
	# Settle UI transforms before computing the physical camera exclusion bounds.
	if toolbar != null: toolbar._layout()
	if backpack_panel != null: backpack_panel._layout()
	if experience != null: experience._layout()
	if touch_controls != null: touch_controls._layout()
	if knowledge_world != null:
		knowledge_world.normal_ppu = (58.0 if get_viewport_rect().size.y < 500 else 60.0) * amount
		if knowledge_world.overview: knowledge_world.resize_overview()
		else: PIXELS_PER_UNIT = knowledge_world.normal_ppu
		if player != null and not knowledge_world.overview: camera_y = camera_target_y()
		return
	if medieval_world != null:
		PIXELS_PER_UNIT = (48.0 if get_viewport_rect().size.y < 500 else 60.0) * amount
		if player != null and toolbar != null: camera_y = camera_target_y()
		return
	PIXELS_PER_UNIT = (58.0 if get_viewport().get_visible_rect().size.y < 500 else 78.0) * amount

func release_building() -> void:
	building_wait = -1
	if draw_mode != 3 or draft.is_empty() or bag_open: return
	if objects.size() >= MAX_OBJECTS:
		message("纸面实体已满，先拆除一些；草稿已保留")
		return
	var object := DrawingRules.building(draft, build_kind)
	if object.is_empty():
		message("轮廓无效，请继续补画；草稿已保留")
		return
	if Vector2(object.x, object.y).distance_to(player.position) > DrawingRules.BUILD_RANGE:
		message("离角色太远，走近后按 2；草稿已保留")
		return
	var body := _drop_candidate(object)
	if body == null: return
	var before := snapshot()
	var result := BlueprintBag.add_entry(bag, object)
	if result.error:
		body.free()
		message(result.error)
		return
	record(before)
	object.blueprint_id = result.entry.id
	charge_creation_ink(object)
	objects.append(object)
	object_nodes.append(_attach_body(body, object))
	selected_blueprint_id = result.entry.id
	draft = []
	mode_drafts[3] = []
	pending_building = {}
	placement_preview = {}
	onboarding.note_built()
	backpack_ui.refresh()
	celebrate_creation(object)
	message(_spawn_notice(body, "已实体化：底边形状和重心决定下落、翻滚与堆叠"))

func return_to_map_select(destination: String = "res://scenes/map_select.tscn") -> void:
	if network_session != null:
		network_session.return_to_selector(destination)
		return
	# Keep both unfinished ink and unsaved map damage in a dormant local session.
	retain_active_stroke()
	cancel_pointer()
	if combat != null: combat.cancel_draw()
	if touch_controls != null: touch_controls.reset()
	if experience != null: experience.close()
	_return_to_selector.call_deferred(destination)

func save_and_return_to_title() -> void:
	if network_session != null:
		network_session.save_and_return_to_selector("res://scenes/title_menu.tscn")
	elif save_game():
		return_to_map_select("res://scenes/title_menu.tscn")

func _return_to_selector(destination: String = "res://scenes/map_select.tscn") -> void:
	var tree := get_tree()
	var holder := tree.root.get_node_or_null("MapSessions")
	if holder == null:
		holder = Node.new()
		holder.name = "MapSessions"
		tree.root.add_child(holder)
	if tree.current_scene == self: tree.current_scene = null
	reparent(holder)
	for node in find_children("*", "CanvasLayer", true, false): node.hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	tree.change_scene_to_file(destination)
