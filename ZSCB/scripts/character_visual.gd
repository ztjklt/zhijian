extends Node2D

var game = null
var native = null
var current_pose := ""
@onready var animator: AnimationPlayer = $AnimationPlayer
@onready var pencil: Node2D = $Skeleton/Hips/Torso/FrontArm/Forearm/Hand/Pencil

func _ready() -> void:
	var held := PaperHeldWeapon.new()
	held.name = "HeldWeapon"
	held.character = self
	held.z_index = -1
	$Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip.add_child(held)
	var combat_pose := PaperCombatPose.new()
	combat_pose.name = "CombatPose"
	combat_pose.character = self
	add_child(combat_pose)
	if native != null:
		material = ShaderMaterial.new()
		material.shader = preload("res://scripts/native_white.gdshader")
		_white_children(self)

func _white_children(node: Node) -> void:
	for child in node.get_children():
		if child is PaperHeldWeapon: continue
		if child is CanvasItem: child.use_parent_material = true
		_white_children(child)

func actor_body():
	return native if native != null else game.player

func actor_facing() -> int:
	return native.facing if native != null else game.facing

func actor_weapon() -> Dictionary:
	return native.weapon_model if native != null else game.equipped_weapon

func actor_state():
	return native if native != null else game.combat

func sample_weapon() -> Array:
	_process(0)
	animator.advance(0)
	$CombatPose._process(0)
	var held = $Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon
	# Restore the clean locomotion base after sampling to prevent additive drift.
	held._process(0)
	return held.world_paths()

func _process(_delta: float) -> void:
	if game == null or not is_instance_valid(actor_body()):
		return
	var body = actor_body()
	# Wrist rotations belong to the sword overlay, not the base drawing/bow clips.
	$Skeleton/Hips/Torso/FrontArm/Forearm/Hand.rotation = 0
	$Skeleton/Hips/Torso/BackArm/Forearm/Hand.rotation = 0
	position = game.world_to_screen(body.position)
	scale.x = float(actor_facing()) * game.PIXELS_PER_UNIT / 78.0
	scale.y = game.PIXELS_PER_UNIT / 78.0 * (0.78 if native == null and game.crouching else 1.0)
	var speed: float = body.velocity.x if native != null else body.linear_velocity.x
	var next_pose: String = ("walk" if absf(speed) > 0.2 else "idle") if native != null else game.pose
	rotation = 0
	modulate.a = 1
	if native != null and native.health <= 0:
		rotation = native.facing * 1.35
		modulate.a = minf(0.65, native.respawn * 0.3)
	elif native == null and game.active_stroke:
		next_pose = "draw"
	elif native == null and game.land_timer > 0.0 and next_pose in ["idle", "walk"]:
		next_pose = "land"
	if not animator.has_animation(next_pose):
		next_pose = "idle"
	if next_pose != current_pose:
		animator.play(next_pose, 0.10)
		current_pose = next_pose
	animator.speed_scale = clampf(absf(speed) / 3.0, 0.7, 1.6) if next_pose == "walk" else 1.0
	pencil.visible = next_pose == "draw"
