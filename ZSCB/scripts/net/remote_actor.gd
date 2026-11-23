extends "res://scripts/net/actor.gd"
var display_game = null
var target_position := Vector2.ZERO
var received_position := false
var smooth_motion := bool(ProjectSettings.get_setting("paper/network/smooth_remote_motion", false))
var last_movement_reset := -1
func _ready() -> void:
	super._ready()
	var visual := PaperCombatVisual.new()
	visual.game = self
	add_child(visual)
func _process(delta: float) -> void:
	var step := (target_position - player.position) * minf(1, delta * 24)
	if smooth_motion:
		# Batches of late snapshots can move the target several normal steps at once.
		# Bound the displayed catch-up without waiting for future packets or overshooting the server.
		var catch_up_speed := maxf(8.0, player.linear_velocity.length() * 1.25)
		step = step.limit_length(catch_up_speed * delta)
	player.position += step
	if display_game != null: PIXELS_PER_UNIT = display_game.PIXELS_PER_UNIT
	queue_redraw()
func world_to_screen(pos: Vector2) -> Vector2:
	return display_game.world_to_screen(pos)
func screen_to_world(pos: Vector2) -> Vector2:
	return display_game.screen_to_world(pos)
func apply(state: Dictionary) -> void:
	target_position = state.position
	var reset := int(state.get("movement_reset", -1))
	var relocated := smooth_motion and reset >= 0 and last_movement_reset >= 0 and reset != last_movement_reset
	last_movement_reset = reset
	if not received_position or relocated or player.position.distance_to(target_position)>5:
		player.position=target_position
		received_position=true
	player.linear_velocity = state.get("velocity",Vector2.ZERO)
	facing = int(state.get("facing",1))
	pose = state.get("pose","idle")
	crouching = state.get("crouching",false)
	if state.has("weapon"): equipped_weapon = state.weapon
	aim_world = state.get("aim_world",player.position+Vector2(facing,0))
	display_name = state.get("name","朋友")
	if state.has("preview"): preview = state.preview
	dead_time = float(state.get("dead",0))
	connected = state.get("connected",true)
	combat.invulnerable = float(state.get("protected",0))
	for key in ["impact_hold","swing","motion_index","bow_equipped","bow_charge","bow_direction","swing_direction","recoil","shot_recoil","health","projectiles"]:
		if state.has(key): combat.set(key,state[key])
	character_visual.visible = connected and dead_time<=0
	PIXELS_PER_UNIT=display_game.PIXELS_PER_UNIT
	queue_redraw()
func _draw() -> void:
	if display_game==null: return
	var color := Color("397f8b") if connected else Color("8c8c87")
	for path in preview:
		var points:=PackedVector2Array()
		for point in path.points: points.append(display_game.world_to_screen(point))
		if points.size()>1: draw_polyline(points,color,2,true)
	var at:Vector2=display_game.world_to_screen(player.position)+Vector2(-35,-95)
	var caption := display_name
	if not connected: caption += " · 重连中"
	elif dead_time>0: caption += " · %.1f秒后重生" % dead_time
	elif combat.invulnerable>0: caption += " · 保护中"
	draw_string(ThemeDB.fallback_font,at,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
	draw_rect(Rect2(at+Vector2(0,6),Vector2(62,4)),Color("ddd6c4"))
	draw_rect(Rect2(at+Vector2(0,6),Vector2(62*combat.health/100.0,4)),color)
