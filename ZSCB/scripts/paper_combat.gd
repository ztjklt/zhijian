class_name PaperCombat
extends RefCounted

var game = null
var targets: Array = []
var projectiles: Array = []
var effects: Array = []
var cooldown := 0.0
var swing := 0.0
var swing_direction := Vector2.RIGHT
var health := 100.0
var invulnerable := 0.0
var training := false
var fire_clock := 0.0
var score := 0
var emitter := Vector2.ZERO
const SWING_DURATION := 0.36
const MAX_PROJECTILES := 64
var natives: Array = []
var natives_enabled := false
var bow_equipped := false
var bow_charge := 0.0
var bow_direction := Vector2.RIGHT
var shot_recoil := 0.0
var recoil := 0.0
var player_push := 0.0
var hit_ids: Dictionary = {}
var swing_weapon: Dictionary = {}
var swing_ticket: Dictionary = {}
var bow_ticket: Dictionary = {}
var player_paths: Array = []
var previous_player_paths: Array = []
var blade_delta := 1.0 / 60.0
var previous_swing := 0.0
var impact_hold := 0.0
var motion_index := 0
var chain_window := 0.0
var queued_attack := 0.0
var queued_direction := Vector2.RIGHT
# Map ink is immutable after its ready-time layout. Index its actual paths once;
# the conservative cells only reject distant paths, never determine a contact.
const TERRAIN_CELL_SIZE := 2.0
var terrain_grid: Dictionary = {}
var terrain_geometry: Array = []
var terrain_geometry_count := -1
var terrain_world_id := 0

func _nearby_terrain(area: Rect2) -> Array:
	var world = game.knowledge_world
	var geometry: Array = world.collision_geometry
	if terrain_world_id != world.get_instance_id() or not is_same(terrain_geometry, geometry) or terrain_geometry_count != geometry.size():
		terrain_world_id = world.get_instance_id()
		terrain_geometry = geometry
		terrain_geometry_count = geometry.size()
		terrain_grid.clear()
		for index in geometry.size():
			var box := PaperBladeSweep.bounds([geometry[index]])
			for x in range(floori(box.position.x / TERRAIN_CELL_SIZE), floori(box.end.x / TERRAIN_CELL_SIZE) + 1):
				for y in range(floori(box.position.y / TERRAIN_CELL_SIZE), floori(box.end.y / TERRAIN_CELL_SIZE) + 1):
					var cell := Vector2i(x, y)
					if not terrain_grid.has(cell): terrain_grid[cell] = []
					terrain_grid[cell].append(index)
	var indices := {}
	for x in range(floori(area.position.x / TERRAIN_CELL_SIZE), floori(area.end.x / TERRAIN_CELL_SIZE) + 1):
		for y in range(floori(area.position.y / TERRAIN_CELL_SIZE), floori(area.end.y / TERRAIN_CELL_SIZE) + 1):
			for index in terrain_grid.get(Vector2i(x, y), []): indices[index] = true
	var ordered: Array = indices.keys()
	ordered.sort()
	var result: Array = []
	for index in ordered: result.append(geometry[index])
	return result

func melee_weapon() -> Dictionary:
	return game.equipped_weapon if not game.equipped_weapon.is_empty() else {"reach": 0.85, "damage": 12.0, "cooldown": 0.40, "paths": []}

func is_bow() -> bool:
	return bow_equipped or PaperWeaponTypes.kind(game.equipped_weapon) == "bow"

func is_firearm() -> bool:
	return not bow_equipped and PaperWeaponTypes.kind(game.equipped_weapon) == "firearm"

func swing_duration() -> float:
	return PaperWeaponTypes.duration(game.equipped_weapon)

func shoot_bullet(origin: Vector2, direction: Vector2, team: String, stamp: Dictionary = {}) -> void:
	if projectiles.size() >= MAX_PROJECTILES: return
	if direction.length_squared() < .001: direction = Vector2.RIGHT
	projectiles.append({"position":origin,"velocity":direction.normalized()*34.0,"life":1.8,"kind":"bullet","team":team,"damage":28.0,"lab_ticket":stamp,"lab_origin":origin})

func toggle_bow() -> void:
	if game.network_session != null:
		game.network_session.send_op("bow")
		return
	bow_equipped = not bow_equipped
	cancel_draw()
	swing = 0
	game.message("试用短弓 · R 拉弓放箭 · Q 返回手绘武器" if bow_equipped else PaperWeaponTypes.label(game.equipped_weapon) + " · R / 右键使用")

func cancel_draw() -> void:
	bow_charge = 0
	bow_ticket = {}
	queued_attack = 0
	chain_window = 0

func set_natives(enabled: bool) -> void:
	if game.network_session != null and enabled:
		game.message("当前联机房间共享地图角色，练习土著仅供单人使用")
		return
	natives_enabled = enabled
	for native in natives:
		if is_instance_valid(native): native.queue_free()
	natives.clear()
	projectiles = projectiles.filter(func(p: Dictionary) -> bool: return p.get("team", "") != "native")
	if not enabled: return
	for i in range(6):
		var native := FingertipNative.new()
		native.game = game
		native.home_x = game.player.position.x + [7.5, 12.0, -10.0, 22.0, -23.0, 34.0][i]
		native.position = game.terrain_spawn(native.home_x)
		native.home_x = native.position.x
		native.weapon_kind = "bow" if i % 3 == 1 else "blade"
		native.patrol_direction = -1.0 if i % 2 == 0 else 1.0
		native.decision_clock = 1.2 + i * 0.35
		game.add_child(native)
		var rig = load("res://scenes/character.tscn").instantiate()
		rig.game = game
		rig.native = native
		rig.z_index = 9
		native.visual = rig
		game.add_child(rig)
		native.blade_paths = rig.sample_weapon()
		native.previous_blade_paths = native.blade_paths
		natives.append(native)

func shoot_arrow(origin: Vector2, direction: Vector2, team: String, stamp: Dictionary = {}) -> void:
	if projectiles.size() >= MAX_PROJECTILES: return
	if direction.length_squared() < 0.001: direction = Vector2.RIGHT
	projectiles.append({"position": origin, "velocity": direction.normalized() * 16.0, "life": 3.0, "kind": "arrow", "team": team, "damage": 24.0 if team == "player" else 12.0,"lab_ticket":stamp,"lab_origin":origin})

func add_damage_text(at: Vector2, amount: float) -> void:
	if game.get("feedback") != null and game.feedback.has_method("record_damage"):
		game.feedback.record_damage(at, amount)
		return
	if effects.size() >= 32: effects.pop_front()
	effects.append({"position": at, "text": "−%d" % amount, "time": 0.8, "color": Color("b52335")})

func blade_active() -> bool:
	var remaining := swing / swing_duration()
	return remaining > 0.12 / SWING_DURATION and remaining <= 1.0 - 0.07 / SWING_DURATION and recoil <= 0

func clash(at: Vector2, native = null, contact_time: float = 1.0) -> void:
	cancel_draw()
	game.feedback.emit_event("clash", at)
	if native != null:
		native.parry()
		hit_ids[native.get_instance_id()] = true
	player_push = -swing_direction.x * 1.8
	recoil = 0.18
	swing = lerpf(previous_swing, swing, contact_time)
	impact_hold = 0.055

func hurt_player(amount: float, direction: Vector2, contact: Vector2 = Vector2.INF, weapon_type: String = "sword") -> void:
	if invulnerable > 0: return
	var lost := minf(health, maxf(0, amount))
	health = maxf(0, health - lost)
	invulnerable = 0.7
	recoil = 0.20
	cancel_draw()
	game.player.linear_velocity += direction.normalized() * 2.0
	player_push = direction.normalized().x * 3.0
	var at: Vector2 = contact if contact.is_finite() else game.player.position
	PaperCombatAudio.impact(game.feedback,"hurt",at,weapon_type)
	add_damage_text(at, lost)
	if health <= 0:
		if game.carried_id != "": game.drop_carried()
		if _lab()!=null:_lab().stop()
		PaperCombatAudio.cry(game.feedback,"player",at)
		health = 100
		invulnerable = 2.0
		if game.knowledge_world != null: game.knowledge_world.respawn()
		elif _medieval_world()!=null: game.respawn_medieval()
		else: game.player.position = Vector2(game.camera_x - 3.0, game.GROUND_Y + 0.7)
		game.player.linear_velocity = Vector2.ZERO
		game.message("本机试打重新开始 · 图纸与装备保留")

func _init(owner_game = null) -> void:
	game = owner_game

func reset() -> void:
	projectiles.clear()
	effects.clear()
	cooldown = 0
	swing = 0
	health = 100
	invulnerable = 0
	cancel_draw()
	shot_recoil = 0
	recoil = 0
	player_push = 0
	player_paths.clear()
	previous_player_paths.clear()
	impact_hold = 0
	if natives_enabled: set_natives(true)
	if training: set_training(true)

func set_training(enabled: bool) -> void:
	if game.network_session != null and enabled:
		game.message("联机直接与朋友互动；练习场仅供单人使用")
		return
	training = enabled
	targets.clear()
	projectiles.clear()
	fire_clock = 2.5
	health = 100
	score = 0
	if not enabled: return
	var origin: Vector2 = game.player.position
	for offset in [2.8, 5.8, 9.2]:
		targets.append({"position": Vector2(origin.x + offset, game.ground_height_at(origin.x + offset) + 0.6), "health": 80.0, "flash": 0.0, "respawn": 0.0})
	emitter = Vector2(origin.x + 11.8, game.ground_height_at(origin.x + 11.8) + 1.0)

func attack(direction: Vector2) -> void:
	if recoil > 0: return
	if cooldown > 0:
		# One late press survives recovery. Early mashing never creates a backlog.
		if not is_bow() and not is_firearm() and chain_window > 0 and swing <= 0.14 and cooldown <= 0.18 and queued_attack <= 0:
			queued_attack = 0.20
			queued_direction = direction
		return
	var weapon: Dictionary = melee_weapon()
	if direction.length_squared() < 0.01: direction = Vector2(game.facing, 0)
	direction = direction.normalized()
	game.aim_world = game.player.position + direction * 5.0
	game.facing = 1 if direction.x >= 0 else -1
	if is_firearm():
		var reserve = game.get("ink")
		if reserve != null and not reserve.spend(PaperInkReserve.ARROW_COST):
			game.message("墨水不足，火枪射击需要4")
			return
		bow_direction = direction
		shoot_bullet(game.player.position + Vector2(0,.43), direction, "player", _lab().ticket() if _lab()!=null else {})
		shot_recoil = .22
		cooldown = .75
		PaperCombatAudio.impact(game.feedback,"shoot",game.player.position + direction*.45,"firearm")
		return
	if is_bow():
		var reserve = game.get("ink")
		if reserve != null and not reserve.can_spend(PaperInkReserve.ARROW_COST):
			game.message("墨水不足，射箭需要4；近战仍可使用")
			return
		bow_direction = direction
		bow_charge = 0.42
		bow_ticket = _lab().ticket() if _lab()!=null else {}
		cooldown = 0.78
		PaperCombatAudio.impact(game.feedback,"draw_bow",game.player.position,"bow")
		return
	if weapon.get("paths", []).is_empty():
		game.message("按 3 画武器，选握点和类型后装备")
		return
	player_paths = game.character_visual.sample_weapon()
	previous_player_paths = player_paths
	var kind := PaperWeaponTypes.kind(weapon)
	motion_index = 3 if kind=="hammer" else 2 if kind=="spear" else (motion_index + 1) % PaperWeaponMotion.MOVES.size() if chain_window > 0 else 0
	chain_window = 0.65
	queued_attack = 0
	swing_direction = direction
	cooldown = PaperWeaponTypes.attack_cooldown(weapon)
	swing = PaperWeaponTypes.duration(weapon)
	previous_swing = swing
	swing_weapon = weapon.duplicate(true)
	swing_ticket = _lab().ticket() if _lab()!=null else {}
	hit_ids.clear()
	var origin: Vector2 = game.player.position + Vector2(0, 0.06)
	PaperCombatAudio.impact(game.feedback,"swing",origin,kind)

func _object_paths(index: int, obj: Dictionary) -> Array:
	if index<game.object_nodes.size():
		var body=game.object_nodes[index]
		if is_instance_valid(body) and body is BuildObject and is_same(body.data,obj):return body.damage_paths
	return PaperObjectDamage.prepare(obj).paths if obj.has("damage_cuts") else obj.get("paths",[])

func first_structure(a: Vector2, b: Vector2) -> Dictionary:
	var result := {}
	var nearest := INF
	for index in game.objects.size():
		var obj: Dictionary = game.objects[index]
		if not PaperObjectDamage.destructible(obj): continue
		for path in _object_paths(index,obj):
			if not path.get("collision", true): continue
			for i in range(1, path.points.size()):
				var p: Vector2 = game.object_point(obj, path.points[i - 1])
				var q: Vector2 = game.object_point(obj, path.points[i])
				var hit = Geometry2D.segment_intersects_segment(a, b, p, q)
				if hit != null and a.distance_squared_to(hit) < nearest:
					nearest = a.distance_squared_to(hit)
					result = {"index": index, "position": hit}
	if game.knowledge_world != null:
		var terrain: Dictionary = game.terrain_hit(a, b)
		if not terrain.is_empty() and a.distance_squared_to(terrain.position) < nearest:
			nearest = a.distance_squared_to(terrain.position)
			result = {"index": -1, "position": terrain.position}
	var world = _medieval_world()
	if world != null:
		var contact: Dictionary = world.segment_contact(a, b)
		if not contact.is_empty() and a.distance_squared_to(contact.position) < nearest:
			result = {"index": contact.get("index",-2), "position": contact.position, "time": contact.time}
			if contact.has("entity"): result.entity=contact.entity
	return result

func _medieval_world():
	# Older map fixtures need not provide this optional world at all.
	return game.medieval_world if "medieval_world" in game else null

func _damage_medieval(entity,amount: float,at: Vector2,impulse: Vector2,weapon_type: String) -> void:
	var world=_medieval_world()
	if world is MedievalWorld:world.damage_entity(entity,amount,at,impulse,weapon_type)
	elif world!=null:world.damage_entity(entity,amount,at,impulse)

func _medieval_target_alive(entity) -> bool:
	return is_instance_valid(entity) and entity.alive and entity.health > 0

func damage_building(index: int, amount: float, contact: Vector2 = Vector2.INF, weapon_type: String = "sword") -> void:
	if index < 0 or index >= game.objects.size(): return
	var obj: Dictionary = game.objects[index]
	if not PaperObjectDamage.destructible(obj): return
	PaperObjectDamage.normalize(obj)
	var lost := minf(obj.get("health", 120.0), maxf(0, amount))
	if lost<=0:return
	obj.health = maxf(0, obj.get("health", 120.0) - lost)
	var at: Vector2 = contact if contact.is_finite() else Vector2(obj.x,obj.y)
	if obj.health>0 and obj.has("paths"):
		PaperObjectDamage.add_cut(obj,at,lost)
		if index<game.object_nodes.size() and is_instance_valid(game.object_nodes[index]) and game.object_nodes[index] is BuildObject:
			game.object_nodes[index].rebuild_damage()
			if game.object_nodes[index].damage_prepared.shapes.is_empty():obj.health=0
	PaperCombatAudio.impact(game.feedback,"break" if obj.health <= 0 else "hit",at,weapon_type)
	add_damage_text(at, lost)
	if obj.health <= 0:
		game.cancel_pointer()
		var body: Node = game.object_nodes[index]
		body.queue_free()
		game.object_nodes.remove_at(index)
		game.objects.remove_at(index)
		game.selected = -1
		game.message("建筑已破坏 · 图纸仍可重复搭建")

func step(delta: float, advance_projectiles: bool = true) -> void:
	blade_delta = maxf(delta, 0.0001)
	if (swing > 0 or queued_attack > 0 or chain_window > 0) and game.equipped_weapon != swing_weapon:
		cancel_draw()
		swing = 0
		impact_hold = 0
		player_paths.clear()
		previous_player_paths.clear()
	cooldown = maxf(0, cooldown - delta)
	previous_swing = swing
	if impact_hold <= 0: swing = maxf(0, swing - delta)
	impact_hold = maxf(0, impact_hold - delta)
	invulnerable = maxf(0, invulnerable - delta)
	recoil = maxf(0, recoil - delta)
	player_push = move_toward(player_push, 0.0, delta * 12.0)
	shot_recoil = maxf(0, shot_recoil - delta)
	if swing <= 0: chain_window = maxf(0, chain_window - delta)
	var focus: Control = game.get_viewport().gui_get_focus_owner()
	if game.bag_open or game.selecting_weapon_grip or focus is LineEdit or focus is TextEdit: cancel_draw()
	if queued_attack > 0:
		if cooldown <= 0 and swing <= 0 and recoil <= 0:
			attack(queued_direction)
		else:
			queued_attack = maxf(0, queued_attack - delta)
	if bow_charge > 0:
		bow_charge = maxf(0, bow_charge - delta)
		if bow_charge == 0:
			var reserve = game.get("ink")
			if reserve == null or reserve.spend(PaperInkReserve.ARROW_COST):
				shoot_arrow(game.player.position + Vector2(0, 0.43), bow_direction, "player", bow_ticket)
				shot_recoil = 0.22
				PaperCombatAudio.impact(game.feedback,"shoot",game.player.position + bow_direction * 0.45,"bow")
			else: game.message("墨水不足，箭未射出；近战仍可使用")
	for native in natives:
		native.previous_blade_paths = native.blade_paths
		var relocated := false
		if absf(native.position.x - game.player.position.x) > 52:
			native.home_x = game.player.position.x + (25.0 if game.facing > 0 else -25.0) + fmod(native.home_x, 9.0)
			native.position = game.terrain_spawn(native.home_x)
			native.home_x = native.position.x
			native.velocity = Vector2.ZERO
			native.state = "wander" if native.health > 0 else "down"
			native.cooldown = 1.5
			native.impact_hold = 0
			relocated = true
		native.step(delta)
		native.blade_paths = native.visual.sample_weapon()
		if relocated: native.previous_blade_paths = native.blade_paths
	previous_player_paths = player_paths
	player_paths = game.character_visual.sample_weapon()
	if previous_player_paths.is_empty(): previous_player_paths = player_paths
	_resolve_blades()
	for effect in effects: effect.time -= delta
	effects = effects.filter(func(e: Dictionary) -> bool: return e.time > 0)
	for target in targets:
		target.flash = maxf(0, target.flash - delta)
		if target.get("respawn", 0) > 0:
			target.respawn -= delta
			if target.respawn <= 0: target.health = 80.0
	if training: fire_clock -= delta
	if training and fire_clock <= 0:
		fire_clock = 2.8
		if emitter.distance_to(game.player.position) <= 16.0:
			var direction: Vector2 = (game.player.position - emitter).normalized()
			if projectiles.size() < MAX_PROJECTILES: projectiles.append({"position": emitter, "velocity": direction * 4.2, "life": 6.0})
	if advance_projectiles: _step_projectiles(delta)
	if effects.size() > 32: effects = effects.slice(effects.size() - 32)

func _resolve_blades() -> void:
	# Compare both moving sword models first. Merely attacking nearby never parries.
	var player_wall := _blade_structure(previous_player_paths, player_paths, _held_blade_origin()) if blade_active() else {}
	if blade_active():
		for native in natives:
			if not native.blade_active() or hit_ids.has(native.get_instance_id()): continue
			var contact := PaperBladeSweep.blade_contact(previous_player_paths, player_paths, native.previous_blade_paths, native.blade_paths)
			var native_wall := _blade_structure(native.previous_blade_paths, native.blade_paths, _held_blade_origin(native.visual))
			if not contact.is_empty() and player_wall.get("time", INF) > contact.time and native_wall.get("time", INF) > contact.time:
				clash(contact.position, native, contact.time)
				break
	if blade_active():
		var damage := PaperWeaponTypes.damage(swing_weapon, PaperBladeSweep.motion_distance(previous_player_paths, player_paths) / blade_delta)
		var wall: Dictionary = player_wall
		if wall.has("entity") and _medieval_target_alive(wall.entity):
			var key := "medieval_" + str(wall.entity.get_instance_id())
			if not hit_ids.has(key):
				hit_ids[key] = true
				var impulse := swing_direction.normalized() * 3.0 * PaperWeaponTypes.impulse(swing_weapon)
				if wall.entity.has_method("is_actor") and wall.entity.is_actor(): impulse.y = maxf(0,impulse.y) + 2.4
				_damage_medieval(wall.entity,damage,wall.position,impulse,PaperWeaponTypes.kind(swing_weapon))
		elif not wall.is_empty() and wall.index >= 0:
			var key := "wall_" + str(game.object_nodes[wall.index].get_instance_id())
			if not hit_ids.has(key):
				hit_ids[key] = true
				damage_building(wall.index,damage,wall.position,PaperWeaponTypes.kind(swing_weapon))
		for native in natives:
			if native.health <= 0 or hit_ids.has(native.get_instance_id()): continue
			var contact := PaperBladeSweep.circle_contact(previous_player_paths, player_paths, native.position + Vector2(0, 0.20), 0.33)
			if not contact.is_empty() and player_wall.get("time", INF) > contact.time:
				hit_ids[native.get_instance_id()] = true
				native.take_hit(damage,swing_direction,PaperWeaponTypes.impulse(swing_weapon),contact.position,PaperWeaponTypes.kind(swing_weapon))
		for i in targets.size():
			var target: Dictionary = targets[i]
			var key := "target_" + str(i)
			if target.health <= 0 or hit_ids.has(key): continue
			var contact := PaperBladeSweep.circle_contact(previous_player_paths, player_paths, target.position, 0.26)
			if contact.is_empty() or player_wall.get("time", INF) <= contact.time: continue
			hit_ids[key] = true
			var lost: float = minf(target.health, damage)
			target.health = maxf(0, target.health - lost)
			target.flash = 0.18
			add_damage_text(contact.position, lost)
			PaperCombatAudio.impact(game.feedback,"break" if target.health <= 0 else "hit",contact.position,PaperWeaponTypes.kind(swing_weapon))
			if target.health <= 0:
				score += 1
				target.respawn = 3.0
		var lab = _lab()
		if lab != null and lab.accepts(swing_ticket) and not hit_ids.has("weapon_lab"):
			var contact := PaperBladeSweep.circle_contact(previous_player_paths,player_paths,lab.position,.26,swing_weapon.get("model_fill",false))
			if not contact.is_empty() and player_wall.get("time",INF)>contact.time:
				hit_ids["weapon_lab"]=true
				lab.hit(swing_ticket,damage,contact.position,game.player.position)
				PaperCombatAudio.impact(game.feedback,"hit",contact.position,PaperWeaponTypes.kind(swing_weapon))
				add_damage_text(contact.position,damage)
	for native in natives:
		if not native.blade_active() or native.state != "strike" or native.hit_done: continue
		var contact := PaperBladeSweep.circle_contact(native.previous_blade_paths, native.blade_paths, game.player.position + Vector2(0, 0.20), 0.25 if game.crouching else 0.33, native.weapon_model.get("model_fill", false))
		if contact.is_empty(): continue
		var wall := _blade_structure(native.previous_blade_paths, native.blade_paths, _held_blade_origin(native.visual))
		if wall.get("time", INF) <= contact.time: continue
		native.hit_done = true
		var speed := PaperBladeSweep.motion_distance(native.previous_blade_paths, native.blade_paths) / blade_delta
		hurt_player(PaperBladeSweep.model_damage(native.weapon_model, speed), Vector2(native.facing, 0), contact.position)

func _lab():
	return game.weapon_lab if "weapon_lab" in game else null

func _held_blade_origin(visual = null) -> Vector2:
	if visual == null and "character_visual" in game: visual = game.character_visual
	if not is_instance_valid(visual): return Vector2.INF
	var held = visual.get_node_or_null("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	return game.screen_to_world(held.global_position) if held != null else Vector2.INF

func _earlier_blade_contact(candidate: Dictionary, nearest: Dictionary, origin: Vector2) -> bool:
	if candidate.is_empty(): return false
	if nearest.is_empty() or candidate.time < nearest.time: return true
	return is_equal_approx(candidate.time,nearest.time) and origin.is_finite() and origin.distance_squared_to(candidate.position) < origin.distance_squared_to(nearest.position)

func _blade_geometry_contact(old: Array, current: Array, geometry: Array, origin: Vector2) -> Dictionary:
	var contact := PaperBladeSweep.blade_contact(old,current,geometry,geometry)
	if contact.is_empty() or not origin.is_finite(): return contact
	# The sweep supplies the first actual contact time. Inspect every contacting
	# segment at that instant so a reversed/multi-stroke model cannot reorder walls.
	var nearest := contact
	# Reject only separated ink. Keep the full edge radius plus a rounding margin;
	# the exact predicates and original edge order still select every contact.
	var margin := PaperBladeSweep.EDGE_RADIUS * 2 + 0.00001
	var geometry_bounds := PaperBladeSweep.bounds(geometry)
	var edges: Array = []
	for outline in geometry:
		for j in range(1, outline.size()):
			var a: Vector2 = outline[j - 1]
			var b: Vector2 = outline[j]
			edges.append({"a": a, "b": b, "bounds": Rect2(a, Vector2.ZERO).expand(b)})
	for path in PaperBladeSweep.at_time(old,current,contact.time):
		for i in range(1,path.size()):
			var a: Vector2 = path[i - 1]
			var b: Vector2 = path[i]
			var segment_bounds := Rect2(a, Vector2.ZERO).expand(b).grow(margin)
			if not segment_bounds.intersects(geometry_bounds, true): continue
			for edge in edges:
				if not segment_bounds.intersects(edge.bounds, true): continue
				var crossing = Geometry2D.segment_intersects_segment(a,b,edge.a,edge.b)
				var pair := Geometry2D.get_closest_points_between_segments(a,b,edge.a,edge.b)
				if crossing == null and pair[0].distance_squared_to(pair[1]) > (PaperBladeSweep.EDGE_RADIUS*2) ** 2: continue
				var point: Vector2 = crossing if crossing != null else (pair[0]+pair[1])*0.5
				var candidate := {"position":point,"time":contact.time}
				if _earlier_blade_contact(candidate,nearest,origin): nearest = candidate
	return nearest

func _blade_structure(old: Array, current: Array, origin: Vector2 = Vector2.INF) -> Dictionary:
	if current.is_empty(): return {}
	var nearest := {}
	var sweep_bounds := PaperBladeSweep.swept_bounds(old, current).grow(PaperBladeSweep.EDGE_RADIUS * 2)
	for index in game.objects.size():
		var obj: Dictionary = game.objects[index]
		if not PaperObjectDamage.destructible(obj): continue
		var geometry: Array = []
		for path in _object_paths(index,obj):
			if not path.get("collision", true): continue
			var points := PackedVector2Array()
			for point in path.points: points.append(game.object_point(obj, point))
			if points.size() > 1: geometry.append(points)
		var contact := _blade_geometry_contact(old, current, geometry, origin)
		if _earlier_blade_contact(contact,nearest,origin):
			nearest = {"index": index, "position": contact.position, "time": contact.time}
	if game.knowledge_world != null:
		var terrain: Array = _nearby_terrain(sweep_bounds)
		var hit := _blade_geometry_contact(old, current, terrain, origin)
		if _earlier_blade_contact(hit,nearest,origin):
			nearest = {"index": -1, "position": hit.position, "time": hit.time}
	var world = _medieval_world()
	if world != null:
		var hit: Dictionary = world.blade_contact(old, current, origin)
		if _earlier_blade_contact(hit,nearest,origin):
			nearest = {"index": hit.get("index",-2), "position": hit.position, "time": hit.time}
			if hit.has("entity"): nearest.entity=hit.entity
	return nearest

func _step_projectiles(delta: float) -> void:
	# Build contacts on the same frame interval, then resolve globally in time order.
	# A wall/body hit earlier in the frame invalidates a later arrow-arrow contact.
	var contacts: Array = []
	var ends: Array[Vector2] = []
	for i in projectiles.size():
		var p: Dictionary = projectiles[i]
		var a: Vector2 = p.position
		var b: Vector2 = a + p.velocity * minf(delta, p.life)
		ends.append(b)
		var wall := first_structure(a, b)
		if not wall.is_empty():
			var contact := {"t": a.distance_to(wall.position) / maxf(a.distance_to(b), 0.00001), "i": i, "position": wall.position}
			if wall.has("entity"):
				contact.kind = "medieval"
				contact.entity = wall.entity
			else:
				contact.kind = "wall" if wall.index >= 0 else "ground"
				contact.object = game.objects[wall.index] if wall.index >= 0 else {}
			contacts.append(contact)
		if p.get("team","")=="player":
			var lab = _lab()
			for peer in (game.network_peers if "network_peers" in game else []):
				if peer.player_id==p.get("shooter",""):lab=peer.weapon_lab if peer.connected and peer.ready_to_play and peer.dead_time<=0 else null;break
			if lab!=null and lab.accepts(p.get("lab_ticket",{})):
				var t:=_circle_hit_time(a,b,lab.position,.26)
				if t<=1:contacts.append({"t":t,"i":i,"kind":"weapon_lab","lab":lab,"position":a.lerp(b,t)})
			for peer in (game.network_peers if "network_peers" in game else []):
				if not is_instance_valid(peer) or peer==game or peer.player_id==p.get("shooter","") or not peer.connected or not peer.ready_to_play or peer.dead_time>0: continue
				var t:=_circle_hit_time(a,b,peer.player.position+Vector2(0,.20),.25 if peer.crouching else .33)
				if t<=1: contacts.append({"t":t,"i":i,"kind":"online_player","actor":peer,"position":a.lerp(b,t)})
				if p.get("kind", "") == "arrow" and peer.combat.blade_active():
					t=PaperBladeSweep.moving_point_time(peer.combat.previous_player_paths,peer.combat.player_paths,a,b,.055,peer.equipped_weapon.get("model_fill",false))
					if t<=1: contacts.append({"t":t,"i":i,"kind":"online_parry","actor":peer,"position":a.lerp(b,t)})
		if p.get("team", "native") != "player":
			var t := _circle_hit_time(a, b, game.player.position, 0.20 if game.crouching else 0.36)
			if t <= 1: contacts.append({"t": t, "i": i, "kind": "player", "position": a.lerp(b, t)})
			if p.get("kind", "") == "arrow" and blade_active():
				t = PaperBladeSweep.moving_point_time(previous_player_paths, player_paths, a, b, 0.055)
				if t <= 1: contacts.append({"t": t, "i": i, "kind": "parry", "position": a.lerp(b, t)})
		else:
			for native in natives:
				if native.health <= 0: continue
				var t := _circle_hit_time(a, b, native.position + Vector2(0, 0.12), 0.35)
				if t <= 1: contacts.append({"t": t, "i": i, "kind": "native", "native": native, "position": a.lerp(b, t)})
				if p.get("kind", "") == "arrow" and native.blade_active():
					t = PaperBladeSweep.moving_point_time(native.previous_blade_paths, native.blade_paths, a, b, 0.055, native.weapon_model.get("model_fill", false))
					if t <= 1: contacts.append({"t": t, "i": i, "kind": "native_parry", "native": native, "position": a.lerp(b, t)})
			for target in targets:
				if target.health <= 0: continue
				var t := _circle_hit_time(a, b, target.position, 0.3)
				if t <= 1: contacts.append({"t": t, "i": i, "kind": "target", "target": target, "position": a.lerp(b, t)})
		if game.knowledge_world==null and _medieval_world()==null and b.y < game.GROUND_Y and a.y >= game.GROUND_Y:
			var t: float = (a.y - game.GROUND_Y) / maxf(a.y - b.y, 0.00001)
			contacts.append({"t": t, "i": i, "kind": "ground", "position": a.lerp(b, t)})
	for i in projectiles.size():
		if projectiles[i].get("kind", "") != "arrow": continue
		for j in range(i + 1, projectiles.size()):
			if projectiles[j].get("kind", "") != "arrow" or (projectiles[i].get("team", "") == projectiles[j].get("team", "") and projectiles[i].get("shooter", "") == projectiles[j].get("shooter", "")): continue
			var relative_a: Vector2 = projectiles[i].position - projectiles[j].position
			var t := _circle_hit_time(relative_a, ends[i] - ends[j], Vector2.ZERO, 0.14)
			if t <= 1: contacts.append({"t": t, "i": i, "j": j, "kind": "clash", "position": projectiles[i].position.lerp(ends[i], t)})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	var spent := {}
	for contact in contacts:
		if spent.has(contact.i) or (contact.has("j") and spent.has(contact.j)): continue
		if contact.kind == "native_parry" and not contact.native.blade_active(): continue
		if contact.kind == "native" and contact.native.health <= 0: continue
		if contact.kind == "medieval" and not _medieval_target_alive(contact.entity): continue
		var p: Dictionary = projectiles[contact.i]
		spent[contact.i] = true
		match contact.kind:
			"weapon_lab":
				contact.lab.hit(p.get("lab_ticket",{}),p.get("damage",24.0),contact.position,p.get("lab_origin",p.position))
				PaperCombatAudio.impact(game.feedback,"hit",contact.position,PaperCombatAudio.projectile(p))
				add_damage_text(contact.position,p.get("damage",24.0))
			"clash":
				spent[contact.j] = true
				game.feedback.emit_event("clash", contact.position)
			"parry": clash(contact.position)
			"native_parry":
				contact.native.parry()
				game.feedback.emit_event("clash", contact.position)
			"wall":
				var index: int = game.objects.find(contact.object)
				if index >= 0: damage_building(index,p.get("damage",20.0),contact.position,PaperCombatAudio.projectile(p))
			"medieval":
				var world = _medieval_world()
				if world != null: _damage_medieval(contact.entity,p.get("damage",24.0),contact.position,p.velocity.normalized()*2.5,PaperCombatAudio.projectile(p))
			"online_player": contact.actor.hit(p.get("damage",24.0),p.velocity,1.0,contact.position,PaperCombatAudio.projectile(p))
			"online_parry": contact.actor.combat.clash(contact.position)
			"player": hurt_player(p.get("damage",15.0),p.velocity,contact.position,PaperCombatAudio.projectile(p))
			"native":
				if contact.native.health > 0: contact.native.take_hit(p.get("damage",24.0),p.velocity,1.0,contact.position,PaperCombatAudio.projectile(p))
			"target":
				var target: Dictionary = contact.target
				var lost: float = minf(target.health, p.get("damage", 24.0))
				target.health = maxf(0, target.health - lost)
				target.flash = 0.18
				if target.health <= 0:
					target.respawn = 3.0
					score += 1
				PaperCombatAudio.impact(game.feedback,"break" if target.health <= 0 else "hit",contact.position,PaperCombatAudio.projectile(p))
				add_damage_text(contact.position, lost)
			"ground": game.feedback.emit_event("stroke", contact.position)
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p.life -= delta
		p.position = ends[i]
		if spent.has(i) or p.life <= 0 or p.position.y < game.GROUND_Y:
			projectiles.remove_at(i)

func _circle_hit_time(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var offset := a - center
	if offset.length_squared() <= radius * radius: return 0.0
	var step_vector := b - a
	var aa := step_vector.length_squared()
	if aa < 0.0000001: return INF
	var bb := 2.0 * offset.dot(step_vector)
	var cc := offset.length_squared() - radius * radius
	var discriminant := bb * bb - 4.0 * aa * cc
	if discriminant < 0: return INF
	var time := (-bb - sqrt(discriminant)) / (2.0 * aa)
	return time if time >= 0.0 and time <= 1.0 else INF
