class_name FingertipNative
extends CharacterBody2D
## Physics stays in world units (this project uses positive Y upward).

var game = null
var health := 65.0
var max_health := 65.0
var home_x := 0.0
var facing := -1
var weapon_kind := "blade"
var state := "wander"
var action_time := 0.0
var cooldown := 1.2
var stagger := 0.0
var flash := 0.0
var knockback := Vector2.ZERO
var gait := 0.0
var age := 0.0
var respawn := 0.0
var hit_done := false
var patrol_direction := 1.0
var decision_clock := 1.0
var aim := Vector2.LEFT
var visual: Node2D
var weapon_model: Dictionary = {}
var blade_paths: Array = []
var previous_blade_paths: Array = []
var impact_hold := 0.0
var impact_swing := 0.0
var motion_index := 0
var attack_count := 0
const SWING_DURATION := 0.36
var swing: float:
	get:
		if weapon_kind != "blade" or health <= 0: return 0.0
		if impact_hold > 0: return impact_swing
		if stagger > 0: return 0.0
		if state == "windup": return 0.29 + 0.07 * clampf(action_time / 0.36, 0, 1)
		if state == "strike": return 0.12 + 0.17 * clampf(action_time / 0.16, 0, 1)
		if state == "recover": return 0.12 * clampf(action_time / 0.30, 0, 1)
		return 0.0
var swing_direction: Vector2:
	get: return Vector2(facing, 0)
var bow_equipped: bool:
	get: return weapon_kind == "bow"
var bow_charge: float:
	get: return action_time * 0.42 / 0.68 if state == "draw" else 0.0
var bow_direction: Vector2:
	get: return aim
var shot_recoil: float:
	get: return action_time * 0.22 / 0.32 if weapon_kind == "bow" and state == "recover" else 0.0
var recoil: float:
	get: return minf(stagger, 0.20)

func _ready() -> void:
	collision_layer = 16
	collision_mask = 9
	up_direction = Vector2(0, 1)
	safe_margin = 0.005
	floor_snap_length = 0.12
	var fixture := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 0.29
	fixture.shape = circle
	add_child(fixture)
	weapon_model = PaperWeaponGrip.practice_sword()

func _exit_tree() -> void:
	if is_instance_valid(visual): visual.queue_free()

func blade_active() -> bool:
	return health > 0 and stagger <= 0 and weapon_kind == "blade" and (state == "strike" or (state == "windup" and action_time <= 0.07))

func take_hit(amount: float, direction: Vector2, strength: float = 1.0, contact: Vector2 = Vector2.INF, weapon_type: String = "sword") -> void:
	if health <= 0: return
	var lost := minf(health, maxf(0, amount))
	health = maxf(0, health - lost)
	flash = 0.18
	stagger = 0.28
	knockback = direction.normalized() * 3.2 * clampf(strength,1,1.8) + Vector2(0, 1.2)
	state = "hurt" if health > 0 else "down"
	if health <= 0:
		respawn = 7.0
		set_collision_layer_value(5, false)
		game.combat.score += 1
	var at: Vector2 = contact if contact.is_finite() else position+Vector2(0,.15)
	PaperCombatAudio.impact(game.feedback,"break" if health <= 0 else "hit",at,weapon_type)
	game.combat.add_damage_text(at, lost)
	if health<=0:PaperCombatAudio.cry(game.feedback,"native",at)

func parry() -> void:
	impact_swing = swing
	impact_hold = 0.055
	stagger = 0.34
	state = "hurt"
	cooldown = 0.9
	knockback = Vector2(-facing * 2.6, 0.7)
	hit_done = true

func step(delta: float) -> void:
	age += delta
	impact_hold = maxf(0, impact_hold - delta)
	flash = maxf(0, flash - delta)
	cooldown = maxf(0, cooldown - delta)
	stagger = maxf(0, stagger - delta)
	if health <= 0:
		respawn -= delta
		velocity = Vector2.ZERO
		if respawn <= 0:
			health = max_health
			position = game.terrain_spawn(home_x)
			state = "wander"
			cooldown = 1.5
			set_collision_layer_value(5, true)
		return
	var offset: Vector2 = game.player.position - position
	var distance := offset.length()
	var line_clear: bool = game.combat.first_structure(position + Vector2(0, 0.12), game.player.position).is_empty()
	var sees_player := distance < 6.0 and line_clear
	var direction := 0.0
	if stagger > 0:
		state = "hurt"
	elif state in ["windup", "strike", "draw"]:
		action_time -= delta
		if action_time <= 0:
			if state == "windup":
				PaperCombatAudio.impact(game.feedback,"swing",position,"sword")
				state = "strike"
				action_time = 0.16
				hit_done = false
			elif state == "draw":
				PaperCombatAudio.impact(game.feedback,"shoot",position,"bow")
				game.combat.shoot_arrow(position + Vector2(facing * 0.42, 0.26), aim, "native")
				state = "recover"
				action_time = 0.32
			else:
				state = "recover"
				action_time = 0.30
	elif state == "recover":
		action_time -= delta
		if action_time <= 0: state = "wander"
	else:
		state = "wander"
		decision_clock -= delta
		if decision_clock <= 0:
			decision_clock = 1.4 + fmod(age + home_x * 0.4, 1.4)
			patrol_direction = -patrol_direction
		if absf(position.x - home_x) > 4.0: patrol_direction = signf(home_x - position.x)
		direction = patrol_direction * 0.58
		if sees_player:
			facing = 1 if offset.x >= 0 else -1
			var wanted := 3.7 if weapon_kind == "bow" else 0.95
			direction = float(facing) if distance > wanted else -float(facing) * 0.5 if weapon_kind == "bow" and distance < 2.6 else 0.0
			if cooldown <= 0 and distance < (5.5 if weapon_kind == "bow" else 1.3):
				motion_index = attack_count % PaperWeaponMotion.MOVES.size()
				attack_count += 1
				state = "draw" if weapon_kind == "bow" else "windup"
				action_time = 0.68 if weapon_kind == "bow" else 0.36
				aim = (game.player.position + Vector2(0, 0.25) - (position + Vector2(facing * 0.42, 0.26))).normalized()
				cooldown = 2.4 if weapon_kind == "bow" else 1.25
				hit_done = false
				direction = 0.0
		elif direction != 0:
			facing = 1 if direction > 0 else -1
	velocity.x = direction * 2.1 + knockback.x
	velocity.y = maxf(velocity.y - 17.0 * delta, -12.0)
	if knockback.y > 0.1: velocity.y = maxf(velocity.y, knockback.y)
	knockback = knockback.move_toward(Vector2.ZERO, delta * 14.0)
	if is_on_wall() and is_on_floor() and absf(direction) > 0.1:
		velocity.y = 5.8
	move_and_slide()
	gait += absf(velocity.x) * delta * 7.5
	if position.y < game.GROUND_Y - 4.0:
		position = game.terrain_spawn(home_x)
		velocity = Vector2.ZERO
