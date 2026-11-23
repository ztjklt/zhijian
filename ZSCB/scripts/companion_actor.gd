extends "res://scripts/net/actor.gd"
## Reuse the second player's rig and locomotion with a private control state.
var sandbox
var brush_target := Vector2.INF

func _ready() -> void:
	super._ready()
	set_active(true)
	_dress_actor()

func _dress_actor() -> void:
	var scarf := Polygon2D.new()
	scarf.color = Color("394f85")
	scarf.polygon = PackedVector2Array([Vector2(-5,-26),Vector2(5,-25),Vector2(5,-21),
		Vector2(-2,-20),Vector2(-9,-11),Vector2(-15,-12),Vector2(-9,-17),Vector2(-6,-22)])
	scarf.z_index = 2
	scarf.antialiased = true
	character_visual.get_node("Skeleton/Hips/Torso").add_child(scarf)
	var brush_arm = preload("res://scripts/companion_brush_arm.gd").new()
	brush_arm.actor = self
	add_child(brush_arm)

func world_to_screen(point: Vector2) -> Vector2:
	return sandbox.world_to_screen(point)

func screen_to_world(point: Vector2) -> Vector2:
	return sandbox.screen_to_world(point)

func drive(delta: float, direction: int, jump := false, down := false) -> void:
	PIXELS_PER_UNIT = sandbox.PIXELS_PER_UNIT
	medieval_world = sandbox.medieval_world
	objects = sandbox.objects
	object_nodes = sandbox.object_nodes
	land_timer = maxf(0.0, land_timer - delta)
	climb_lock_timer = maxf(0.0, climb_lock_timer - delta)
	down_tap_timer = maxf(0.0, down_tap_timer - delta)
	ink.step(delta)
	player.update_drop_through(delta)
	step_locomotion(delta, {"left": direction < 0, "right": direction > 0, "jump_pressed": jump, "down":down})

func relocate(at: Vector2) -> void:
	player.reset_movement()
	player.position = at
	player.linear_velocity = Vector2.ZERO
	PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, player.global_transform)
	PhysicsServer2D.body_set_state(player.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
	player.sleeping = false

func hand_world() -> Vector2:
	var hand: Node2D = character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip")
	var offset: Vector2 = hand.global_position - character_visual.global_position
	return player.position + Vector2(offset.x, -offset.y) / sandbox.PIXELS_PER_UNIT
