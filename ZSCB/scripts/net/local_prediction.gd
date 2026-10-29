extends RefCounted
## Only this player's locomotion is predicted. Combat/world changes stay authoritative.
## Optional r2 input ACK/age ties the authority pose to a local simulation sample.
## Old servers retain a rate-limited fallback; ping never determines ACK timing.
var history: Array = []
var correction := Vector2.ZERO
var initialized := false
var alive := false
var last_authority := Vector2.ZERO
var received_at := 0
var was_running := false
var jump_down := false
var health := 100.0
var motion_x := 0.0
var simulation_clock := 0.0
var last_sample_clock := 0.0
var input_records: Dictionary = {}
var previous_controls: Dictionary = {}
var changed_seq := -1
var reset_serial := -1
var ack_enabled := false
var server_input_stale := false
var correction_count := 0
var max_correction_step := 0.0
const CORRECTION_SPEED := .9

func clear() -> void:
	history.clear()
	correction = Vector2.ZERO
	initialized = false
	was_running = false
	jump_down = Input.is_action_pressed("jump")
	motion_x = 0
	simulation_clock = 0
	input_records.clear()
	previous_controls.clear()
	changed_seq = -1
	reset_serial = -1
	server_input_stale = false

func sent_input(number: int, controls: Dictionary) -> void:
	if number < 1: return
	input_records[number] = {"clock": last_sample_clock}
	if controls != previous_controls:
		changed_seq = number
		previous_controls = controls.duplicate()
	while input_records.size() > 256: input_records.erase(input_records.keys().front())

func relocate(game, state: Dictionary, now: int, new_life: bool = false) -> void:
	var jumps: int = game.jumps_used
	var up_held: bool = game.jump_was_down
	var down_held: bool = game.down_was_down
	game.player.reset_movement()
	# A correction is not a respawn and cannot grant another aerial jump.
	game.jumps_used = (1 if state.get("pose", "idle") in ["jump", "fall"] else 0) if new_life else jumps
	game.jump_was_down = Input.is_action_pressed("move_up") if new_life else up_held
	game.down_was_down = Input.is_action_pressed("move_down") if new_life else down_held
	if new_life: jump_down = Input.is_action_pressed("jump")
	game.player.position = state.position
	PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, state.position))
	game.player.linear_velocity = state.get("velocity", Vector2.ZERO)
	game.player.sleeping = false
	game.facing = int(state.get("facing", 1))
	game.pose = state.get("pose", "idle")
	game.crouching = state.get("crouching", false)
	history.clear()
	correction = Vector2.ZERO
	history.append({"at": now, "clock": simulation_clock, "position": game.player.position, "motion_x": motion_x})

func receive(game, state: Dictionary, now: int, rtt_ms: int) -> void:
	var active: bool = float(state.get("dead", 0)) <= 0 and bool(state.get("connected", true))
	var serial: int = int(state.get("movement_reset", -1))
	var teleport: bool = initialized and ((serial >= 0 and reset_serial >= 0 and serial != reset_serial) or (serial < 0 and last_authority.distance_to(state.position) > 12))
	var hurt: bool = float(state.get("health", health)) < health
	ack_enabled = state.has("input_ack") and state.has("input_age")
	var ack: int = int(state.get("input_ack", -1))
	var age: float = maxf(0, float(state.get("input_age", 0)))
	server_input_stale = ack_enabled and age > .5
	var pending_change: bool = ack_enabled and ack < changed_seq
	var past = null
	if ack_enabled and input_records.has(ack) and not pending_change:
		past = sample_clock(float(input_records[ack].clock) + age)
	elif not ack_enabled and rtt_ms >= 0:
		past = sample_at(now - clampi(rtt_ms, 0, 1200))
	if not initialized or active != alive or teleport:
		relocate(game, state, now, true)
		initialized = true
	elif active:
		if not was_running:
			# Restore physics velocity, but keep display position. The delayed pose
			# must not rewind several metres merely because a state gap ended.
			game.player.linear_velocity = state.get("velocity", Vector2.ZERO)
		if not pending_change:
			var error: Vector2 = state.position - (past.position if past != null else game.player.position)
			# No ACK sample during startup is not evidence of a position error.
			if past != null or not was_running:
				correction = error if error.length() > .18 else Vector2.ZERO
				if correction.length() > 0: correction_count += 1
		else:
			correction = Vector2.ZERO
		if hurt:
			game.player.linear_velocity = state.get("velocity", Vector2.ZERO)
			var push := 0.0
			if past != null:
				push = float(state.get("velocity", Vector2.ZERO).x) - float(past.motion_x)
			elif state.get("pose", "") in ["idle", "walk"]:
				var base := 0.0
				if state.pose == "walk": base = int(state.get("facing", 1)) * (2.3 if state.get("crouching", false) else 4.6)
				push = float(state.get("velocity", Vector2.ZERO).x) - base
			# Airborne/climbing motion without history cannot reveal recoil reliably.
			game.combat.player_push = clampf(push, -3, 3)
	else:
		game.player.position = state.position
		game.player.linear_velocity = Vector2.ZERO
	last_authority = state.position
	received_at = now
	alive = active
	reset_serial = serial
	health = float(state.get("health", health))
	if not active:
		game.player.freeze = true
		game.player.collision_layer = 0
		game.player.collision_mask = 0
		history.clear()
		correction = Vector2.ZERO
		was_running = false

func sample_at(stamp: int):
	return _sample(float(stamp), "at")

func sample_clock(stamp: float):
	return _sample(stamp, "clock")

func _sample(stamp: float, field: String):
	if history.is_empty() or stamp < float(history.front()[field]) - .0001 or stamp > float(history.back()[field]) + .0001: return null
	for i in range(1, history.size()):
		if float(history[i][field]) < stamp: continue
		var a: Dictionary = history[i-1]
		var b: Dictionary = history[i]
		var weight := (stamp - float(a[field])) / maxf(.0001, float(b[field]) - float(a[field]))
		return {"position": (a.position as Vector2).lerp(b.position, weight), "motion_x": lerpf(a.motion_x, b.motion_x, weight)}
	return history.back()

func step(game, delta: float, controls: Dictionary, enabled: bool, now: int) -> void:
	last_sample_clock = simulation_clock
	simulation_clock += delta
	if not enabled or not initialized or not alive or now - received_at > 750:
		game.player.freeze = true
		game.player.linear_velocity = Vector2.ZERO
		game.player.collision_layer = 0
		game.player.collision_mask = 0
		correction = Vector2.ZERO
		was_running = false
		return
	game.player.freeze = false
	game.player.collision_layer = 2
	game.player.collision_mask = 9
	game.player.sleeping = false
	was_running = true
	var shift := (correction * (1 - exp(-delta * 12))).limit_length(delta * CORRECTION_SPEED)
	max_correction_step = maxf(max_correction_step, shift.length())
	if shift.length() > .0001:
		game.player.position += shift
		PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, game.player.position))
		for sample in history: sample.position += shift
		correction -= shift
	history.append({"at": now, "clock": last_sample_clock, "position": game.player.position, "motion_x": motion_x})
	while history.size() > 256 or (not history.is_empty() and now - int(history.front().at) > 4000): history.pop_front()
	game.land_timer = maxf(0, game.land_timer - delta)
	game.climb_lock_timer = maxf(0, game.climb_lock_timer - delta)
	game.down_tap_timer = maxf(0, game.down_tap_timer - delta)
	game.player.update_drop_through(delta)
	# Resetting contacts while Area stays over a floor emits no new body_entered.
	for body in game.player.foot_sensor.get_overlapping_bodies(): game.player._foot_entered(body)
	var movement := controls.duplicate()
	if server_input_stale:
		for key in ["left", "right", "up", "down", "jump"]: movement[key] = false
	# A confirmed obstruction cannot be outrun forever. Ease back while waiting
	# for the real colliders/state to converge, rather than a hard position snap.
	if correction.x < -1: movement.right = false
	if correction.x > 1: movement.left = false
	var held: bool = bool(movement.get("jump", false))
	movement.jump_pressed = held and not jump_down
	jump_down = held
	game.combat.player_push = move_toward(game.combat.player_push, 0, delta * 12)
	game.step_locomotion(delta, movement)
	motion_x = game.player.linear_velocity.x - game.combat.player_push
	if game.medieval_world != null: game.player.position.x = clampf(game.player.position.x, -4, game.medieval_world.LENGTH + 4)
	game.walk_phase = fmod(game.walk_phase + absf(game.player.position.x - game.last_player_x) * game.PIXELS_PER_UNIT / 68.0, 1.0)
	game.last_player_x = game.player.position.x
