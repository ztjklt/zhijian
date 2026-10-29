extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SWORD POSE: " + label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	game.combat.set_natives(false)
	game.equipped_weapon = PaperWeaponGrip.make_weapon([{"points": [Vector2.ZERO, Vector2(0, 0.8), Vector2(0.08, 1), Vector2(0.16, 0.8), Vector2(0.16, 0), Vector2.ZERO]}], Vector2.ZERO)
	var rig = game.character_visual
	var anchor: Node2D = rig.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip")
	var held = anchor.get_node("HeldWeapon")
	var head: Node2D = rig.get_node("Skeleton/Hips/Torso/Head")
	for facing in [-1, 1]:
		game.facing = facing
		game.combat.swing_direction = Vector2(facing, 0)
		for remaining in [0.0, 0.35, 0.28, 0.22, 0.14, 0.06]:
			game.combat.swing = remaining
			game.combat.recoil = 0
			game.crouching = false
			rig.animator.play("idle", 0)
			rig.animator.seek(0, true)
			rig.sample_weapon()
			var farthest := Vector2.ZERO
			for path in held.weapon.paths:
				for point in path.points:
					var offset: Vector2 = held.local_point(point)
					if offset.length_squared() > farthest.length_squared(): farthest = offset
			var blade_axis: Vector2 = (held.to_global(farthest) - held.global_position).normalized()
			var wrist_axis := -anchor.global_transform.y.normalized()
			check(blade_axis.dot(wrist_axis) > 0.985, "blade and gripping wrist stay aligned: facing %d, swing %.2f" % [facing, remaining])
			check(held.global_position.distance_to(anchor.global_position) < 0.01, "selected grip remains in the palm throughout the swing")
			if remaining == 0:
				var grip_at: Vector2 = rig.to_local(anchor.global_position)
				var head_at: Vector2 = rig.to_local(head.global_position)
				check(grip_at.x > head_at.x + 10 and grip_at.y > head_at.y + 10, "ready hand sits ahead of the chest and below the face")
				check(blade_axis.x * facing > 0.3 and blade_axis.y < -0.15, "ready sword points diagonally forward rather than through the face")
				var shoulder_at: Vector2 = rig.to_local(anchor.get_parent().get_parent().get_parent().global_position)
				var elbow_at: Vector2 = rig.to_local(anchor.get_parent().get_parent().global_position)
				check(elbow_at.y > shoulder_at.y + 6, "ready elbow bends below the shoulder rather than lifting into a rigid triangle")
	game.combat.swing = 0
	game.equipped_weapon = {}
	rig.sample_weapon()
	check(is_zero_approx(anchor.get_parent().rotation), "leaving sword mode releases the wrist for drawing and unarmed animations")
	check(root.msaa_2d == Viewport.MSAA_4X, "the running 2D viewport enables 4x MSAA")
	check(game.get_node("VisualQuality").layer > 0 and game.get_node("VisualQuality").layer < game.get_node("UILayer").layer, "world sharpening renders after the world and before interactive UI")
	game.queue_free()
	await process_frame
	print("SWORD POSE TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
