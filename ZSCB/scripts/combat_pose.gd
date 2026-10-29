class_name PaperCombatPose
extends Node
## Upper-body overlay after AnimationPlayer; locomotion keeps running underneath.

var character: Node2D

func _ready() -> void:
	process_priority = 5

func _process(_delta: float) -> void:
	if character == null or character.game == null: return
	var game = character.game
	var battle = character.actor_state()
	if battle == null: return
	if character.native == null and game.active_stroke != null and battle.swing <= 0:
		_release_overlay()
		return
	var facing: int = character.actor_facing()
	var torso: Node2D = character.get_node("Skeleton/Hips/Torso")
	var front: Node2D = torso.get_node("FrontArm")
	var rear: Node2D = torso.get_node("BackArm")
	var head: Node2D = torso.get_node("Head")
	var bow: bool = battle.is_bow() if battle.has_method("is_bow") else battle.bow_equipped
	var firearm: bool = battle.is_firearm() if battle.has_method("is_firearm") else false
	if bow or firearm:
		var charge: float = 1.0 - battle.bow_charge / 0.42 if battle.bow_charge > 0 else 0.0
		var kick: float = battle.shot_recoil / 0.22
		torso.rotation = -0.12 - charge * 0.12 + kick * 0.30
		head.rotation = -torso.rotation * 0.65
		var aim: Vector2 = battle.bow_direction if battle.bow_charge > 0 or battle.shot_recoil > 0 else (game.aim_world - game.player.position).normalized()
		var angle := Vector2(aim.x * facing, -aim.y).angle()
		angle = clampf(angle, -1.1, 1.1)
		var center := Vector2(0, -34)
		var forward := Vector2.from_angle(angle)
		if firearm: grip_to(front,center + forward * (25 - kick*5),angle, -1.0)
		else: grip_to(front,center + forward * (29 - kick*5),angle-PI*.5,-1.0)
		arm_to(rear, center + forward * (14 - charge * 27 - kick * 6), 1.0)
	elif not character.actor_weapon().is_empty():
		var kind := PaperWeaponTypes.kind(character.actor_weapon())
		var hold := hold_pose(kind)
		var grip := Vector2(hold.x, hold.y)
		var blade_angle := hold.z
		var lean := hold.w
		var rear_grip := hold_rear(kind)
		if battle.swing > 0:
			var p: float = 1.0 - battle.swing / (battle.swing_duration() if battle.has_method("swing_duration") else battle.SWING_DURATION)
			var pose := PaperWeaponMotion.pose(battle.motion_index, p)
			grip = Vector2(pose.x, pose.y)
			blade_angle = pose.z
			lean = pose.w
			rear_grip = PaperWeaponMotion.rear_hand(battle.motion_index, p)
		if battle.recoil > 0 and battle.impact_hold <= 0:
			var bounce: float = minf(1.0, battle.recoil / 0.18)
			grip = grip.lerp(Vector2(15, -31), bounce)
			blade_angle = lerpf(blade_angle, -1.05, bounce)
			lean = -0.12 * bounce
		torso.rotation = lean
		head.rotation = -lean * 0.65
		grip_to(front, grip, blade_angle, 1.0)
		arm_to(rear, rear_grip, 1.0)
	elif battle.recoil <= 0:
		_release_overlay()
	if battle.recoil > 0 and battle.impact_hold <= 0 and character.actor_weapon().is_empty():
		var strength: float = minf(1, battle.recoil / 0.13)
		torso.rotation = -0.30 * strength
		head.rotation = 0.30 * strength
		front.rotation = -2.0 - sin(battle.recoil * 90) * 0.15 * strength

func hold_pose(kind: String) -> Vector4:
	match kind:
		"hammer": return Vector4(18, -18, -0.28, 0.07)
		"spear": return Vector4(29, -27, -0.12, 0.04)
		_: return Vector4(23, -23, -0.65, 0.10)

func hold_rear(kind: String) -> Vector2:
	match kind:
		"hammer": return Vector2(3, -27)
		"spear": return Vector2(7, -26)
		_: return Vector2(4, -29)

func _release_overlay() -> void:
	var animator: AnimationPlayer = character.get_node_or_null("AnimationPlayer")
	if animator != null:
		animator.advance(0)

func grip_to(arm: Node2D, target: Vector2, blade_angle: float, bend: float) -> void:
	var hand: Node2D = arm.get_node("Forearm/Hand")
	var marker: Node2D = hand.get_node("WeaponGrip")
	var wrist_angle := blade_angle + PI / 2
	# Solve for the hand joint after accounting for the palm's actual grip offset.
	var joint_target := target - marker.position.rotated(wrist_angle)
	arm_to(arm, joint_target, bend)
	var parent_basis: Transform2D = character.global_transform.affine_inverse() * hand.get_parent().global_transform
	hand.rotation = wrapf(wrist_angle - parent_basis.get_rotation(), -PI, PI)

func arm_to(arm: Node2D, target: Vector2, bend: float) -> void:
	var local: Vector2 = arm.get_parent().to_local(character.to_global(target)) - arm.position
	var distance := clampf(local.length(), 2.0, 26.8)
	var shoulder_angle := acos(clampf((13.0 * 13.0 + distance * distance - 14.0 * 14.0) / (2.0 * 13.0 * distance), -1, 1))
	var elbow_angle := PI - acos(clampf((13.0 * 13.0 + 14.0 * 14.0 - distance * distance) / (2.0 * 13.0 * 14.0), -1, 1))
	arm.rotation = local.angle() - PI / 2 + bend * shoulder_angle
	arm.get_node("Forearm").rotation = -bend * elbow_angle
