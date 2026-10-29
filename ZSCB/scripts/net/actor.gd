extends "res://scripts/main.gd"
## A server-controlled player, using the same locomotion, rig and sword sweep.
var room = null
var player_id := ""
var display_name := ""
var credential := ""
var connected := false
var ready_to_play := false
var input_state: Dictionary = {}
var input_age := 0.0
var disconnect_age := 0.0
var dead_time := 0.0
var pending_jump := false
var jump_down := false
var controls_blocked := false
var combat_blocked := false
var equipment_version := 0
var command_seq := 0
var input_seq := 0
var movement_reset := 0
var results: Dictionary = {}
var history: Array = []
var preview: Array = []
var upload: Dictionary = {}
var upload_age := 0.0
var carried_layer := 1
var carried_mask := 1
var carried_freeze := false

func _ready() -> void:
	weapon_lab = preload("res://scripts/weapon_lab.gd").new(self)
	player = preload("res://scenes/player.tscn").instantiate()
	player.game = self
	add_child(player)
	character_visual = preload("res://scenes/character.tscn").instantiate()
	character_visual.game = self
	add_child(character_visual)
	feedback = preload("res://scripts/net/feedback.gd").new()
	feedback.room = room
	feedback.source_id = player_id
	feedback.game = self
	feedback.audio_enabled = false
	add_child(feedback)
	combat = PaperCombat.new(self)
	set_physics_process(false)
	set_process_unhandled_input(false)
	set_active(false)

func message(_text: String) -> void:
	pass

func set_active(active: bool) -> void:
	movement_reset += 1
	if not active and weapon_lab != null: weapon_lab.stop()
	player.freeze = not active
	player.collision_layer = 2 if active else 0
	player.collision_mask = 9 if active else 0
	player.linear_velocity = Vector2.ZERO
	player.sleeping = false
	input_state.clear()
	pending_jump = false
	jump_down = false
	jump_was_down = false
	down_was_down = false
	down_tap_timer = 0
	controls_blocked = false
	combat_blocked = false
	wall_climb.reset(player)
	combat.cancel_draw()
	combat.swing = 0
	player.reset_movement()

func block_controls(blocked: bool = true) -> void:
	controls_blocked = blocked
	combat_blocked = blocked
	input_state.clear()
	pending_jump = false
	jump_down = false
	jump_was_down = false
	down_was_down = false
	down_tap_timer = 0
	wall_climb.reset(player)
	combat.cancel_draw()

func simulate(delta: float) -> void:
	input_age += delta
	if not upload.is_empty():
		upload_age += delta
		if upload_age>120: upload.clear()
	if not connected: disconnect_age += delta
	if not connected or not ready_to_play: return
	ink.step(delta)
	weapon_lab.step(delta)
	if dead_time > 0:
		dead_time = maxf(0, dead_time - delta)
		if dead_time == 0:
			var spawn=room.safe_spawn(3.0 if medieval_world!=null else 9.0 if knowledge_world!=null else -5.6)
			if spawn==null: dead_time=.2; return
			player.position = spawn
			PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, player.position))
			set_active(true)
			combat.health = 100
			combat.invulnerable = 2
		return
	if input_age > .5:
		block_controls(controls_blocked)
	land_timer = maxf(0, land_timer-delta)
	climb_lock_timer = maxf(0, climb_lock_timer-delta)
	down_tap_timer = maxf(0, down_tap_timer-delta)
	player.update_drop_through(delta)
	var controls := input_state.duplicate()
	controls.jump_pressed = pending_jump
	pending_jump = false
	step_locomotion(delta, controls)
	combat.step(delta, false)
	camera_x = player.position.x
	if medieval_world != null: player.position.x = clampf(player.position.x, -4, medieval_world.LENGTH+4)
	if player.position.y < -12:
		var spawn=room.safe_spawn(player.position.x)
		if spawn==null: player.linear_velocity=Vector2.ZERO; return
		movement_reset += 1
		player.position = spawn
		PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, player.position))
		player.linear_velocity = Vector2.ZERO

func hit(amount: float, direction: Vector2, strength: float = 1.0, contact: Vector2 = Vector2.INF, weapon_type: String = "sword") -> void:
	if not connected or not ready_to_play or dead_time > 0 or combat.invulnerable > 0: return
	var lost := minf(combat.health, clampf(amount, 5, 40))
	combat.health = maxf(0, combat.health - lost)
	combat.invulnerable = .7
	combat.recoil = .2
	combat.cancel_draw()
	combat.player_push = direction.normalized().x * 3 * clampf(strength,1,1.8)
	room.record_feedback("hurt", contact if contact.is_finite() else player.position, player_id,lost,PaperCombatAudio.cue("hurt",weapon_type))
	if combat.health == 0:
		feedback.emit_audio("death_human_low",player.position)
		dead_time = 3
		preview.clear()
		set_active(false)

func state() -> Dictionary:
	return {"input_ack":input_seq,"input_age":input_age,"movement_reset":movement_reset,"id":player_id,"name":display_name,"position":player.position,"velocity":player.linear_velocity,
		"facing":facing,"pose":pose,"crouching":crouching,"health":combat.health,"dead":dead_time,
		"ink":ink.amount,"ink_wait":ink.wait,"ink_spent":ink.last_cost,"ink_flash":ink.recent,
		"protected":combat.invulnerable,"connected":connected and ready_to_play,
		"aim_world":aim_world,"weapon":equipped_weapon,"swing":combat.swing,"motion_index":combat.motion_index,
		"bow_equipped":combat.bow_equipped,"bow_charge":combat.bow_charge,"bow_direction":combat.bow_direction,
		"swing_direction":combat.swing_direction,"impact_hold":combat.impact_hold,"recoil":combat.recoil,"shot_recoil":combat.shot_recoil,
		"preview":preview,"weapon_version":equipment_version,"projectiles":combat.projectiles,"weapon_lab":weapon_lab.snapshot(),"carried_id":carried_id}
