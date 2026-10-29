class_name PaperHeldWeapon
extends Node2D

var character: Node2D
var weapon: Dictionary = {}
var pixels_per_unit := 78.0
var trace := PaperWeaponTrace.new()
var trace_weapon: Dictionary = {}
var trace_facing := 0
var trace_origin := Vector2.INF
var edge_light := false

func _ready() -> void:
	process_priority = 10 # Update after the character and AnimationPlayer.

func local_point(point: Vector2) -> Vector2:
	var offset: Vector2 = point - weapon.get("grip", Vector2.ZERO)
	return Vector2(offset.x, -offset.y) * pixels_per_unit

func _process(delta: float) -> void:
	if character == null or character.get("game") == null:
		visible = false
		trace.clear()
		return
	var game = character.get("game")
	weapon = character.actor_weapon()
	var battle = character.actor_state()
	var facing: int = character.actor_facing()
	pixels_per_unit = game.PIXELS_PER_UNIT
	visible = not weapon.is_empty()
	if battle != null and battle.bow_equipped: visible = false
	if not visible:
		trace.clear()
		return
	# The hand owns orientation; the same transform is sampled for collisions.
	# Keep world size independent of crouching, with the selected grip at local zero.
	var anchor: Node2D = get_parent()
	var tip := Vector2.ZERO
	for path in weapon.paths:
		for point in path.points:
			var candidate := local_point(point)
			if candidate.length_squared() > tip.length_squared(): tip = candidate
	var wrist_axis := -anchor.global_transform.y.normalized()
	if PaperWeaponTypes.ranged(weapon) and battle != null:
		var direction: Vector2 = battle.bow_direction if battle.bow_charge > 0 or battle.shot_recoil > 0 else (game.aim_world - game.player.position).normalized()
		if direction.length_squared()<.01: direction = Vector2(facing,0)
		wrist_axis = Vector2(direction.x,-direction.y)
		if PaperWeaponTypes.kind(weapon)=="bow": wrist_axis = wrist_axis.rotated(-PI*.5)
	var source_axis := Vector2(tip.x * facing, tip.y)
	var turn := wrist_axis.angle() - source_axis.angle()
	var held_transform := Transform2D(turn, anchor.global_position)
	held_transform.x *= facing
	global_transform = held_transform
	edge_light = battle != null and battle.blade_active() and not PaperWeaponTypes.ranged(weapon)
	if delta > 0:
		_update_trace(delta,game,facing)
	queue_redraw()

func world_paths() -> Array:
	var result: Array = []
	if not visible or weapon.is_empty(): return result
	for path in weapon.paths:
		var points := PackedVector2Array()
		for point in path.points:
			points.append(character.game.screen_to_world(to_global(local_point(point))))
		if points.size() > 1: result.append(points)
	return result

func _update_trace(delta: float, game, facing: int) -> void:
	if DisplayServer.get_name()=="headless" or not is_visible_in_tree():
		trace.clear()
		return
	var origin: Vector2 = game.screen_to_world(global_position)
	if not is_same(trace_weapon,weapon) or trace_facing!=facing or (trace_origin.is_finite() and trace_origin.distance_to(origin)>3): trace.clear()
	trace_weapon=weapon
	trace_facing=facing
	trace_origin=origin
	if PaperWeaponTypes.ranged(weapon) or game.bag_open or game.selecting_weapon_grip:
		trace.clear()
		return
	var vertices:=0
	for path in weapon.paths: vertices+=path.points.size()
	# Oversized drawings retain their exact rendering and full collision paths;
	# only optional copies are omitted to keep their frame cost bounded.
	if vertices>PaperWeaponTrace.MAX_VERTICES:
		trace.clear()
		return
	trace.advance(delta,world_paths() if edge_light else [],edge_light)

func _draw_echoes() -> void:
	if character==null or character.game==null: return
	for snapshot in trace.snapshots:
		if snapshot.age<=0: continue
		var color:=Color("33262e")
		color.a=PaperWeaponTrace.opacity(snapshot.age)
		for path in snapshot.paths:
			var points:=PackedVector2Array()
			for point in path: points.append(to_local(character.game.world_to_screen(point)))
			if points.size()>1: draw_polyline(points,color,2,true)

func _draw() -> void:
	_draw_echoes()
	for path in weapon.get("paths", []):
		var points := PackedVector2Array()
		for point in path.points: points.append(local_point(point))
		if points.size() >= 2:
			if weapon.get("model_fill", false) and points.size() > 3 and points[0].is_equal_approx(points[-1]):
				draw_colored_polygon(points, Color("c9d8dc"))
			draw_polyline(points, Color("28323b"), 3.5, true)
			if edge_light:
				var colors:=PackedColorArray()
				for point in path.points:
					var distance: float = point.distance_to(weapon.get("grip",Vector2.ZERO))
					var light:=smoothstep(.12,maxf(.3,weapon.get("reach",1.0)),distance)
					colors.append(Color(.78,.16,.23,.65*light))
				draw_polyline_colors(points,colors,1.2,true)
			for point in [points[0], points[-1]]: draw_circle(point, 1.75, Color("28323b"))
