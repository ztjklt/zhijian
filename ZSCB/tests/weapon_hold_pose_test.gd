extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL HOLD POSE: ", label)

func pose(rig: Node2D) -> Array[float]:
	var torso: Node2D = rig.get_node("Skeleton/Hips/Torso")
	var front: Node2D = torso.get_node("FrontArm")
	var rear: Node2D = torso.get_node("BackArm")
	return [torso.rotation, front.rotation, front.get_node("Forearm").rotation, rear.rotation]

func different(a: Array[float], b: Array[float]) -> bool:
	for i in a.size():
		if absf(a[i] - b[i]) > 0.02:
			return true
	return false

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.combat.set_natives(false)
	var rig: Node2D = game.character_visual
	game.equipped_weapon = {}
	rig._process(0)
	var empty_pose := pose(rig)
	var weapon := PaperWeaponGrip.practice_sword()
	var poses: Dictionary = {}
	for kind in ["sword", "hammer", "spear"]:
		game.combat.reset()
		weapon = PaperWeaponGrip.practice_sword()
		weapon.weapon_type = kind
		game.equipped_weapon = weapon
		rig._process(0)
		rig.get_node("CombatPose")._process(0)
		poses[kind] = pose(rig)
	check(different(poses.sword, poses.hammer), "hammer has a distinct idle holding stance")
	check(different(poses.sword, poses.spear), "spear has a distinct idle holding stance")
	check(different(poses.hammer, poses.spear), "hammer and spear do not collapse to the same stance")
	game.equipped_weapon = {}
	game.combat.reset()
	rig._process(0)
	rig.get_node("CombatPose")._process(0)
	check(not different(empty_pose, pose(rig)), "empty hands release the held stance")
	game.queue_free()
	await process_frame
	print("WEAPON HOLD POSE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
