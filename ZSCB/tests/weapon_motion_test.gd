extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("WEAPON MOTION: " + label)

func ticks(battle, count: int) -> void:
	for i in count: battle.step(0.01)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	game.combat.set_natives(false)
	game.player.position = Vector2(0, game.GROUND_Y + 2)
	game.equipped_weapon = {"paths": [{"points": [Vector2.ZERO, Vector2(0, 0.8)]}], "grip": Vector2.ZERO, "cooldown": 0.40, "damage": 20.0, "reach": 0.8}
	var battle = game.combat
	var rig = game.character_visual
	var anchor: Node2D = rig.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip")
	var held = anchor.get_node("HeldWeapon")
	var directions: Array[Vector2] = []
	# Deleting variation would make the four real blade directions identical.
	for move in range(4):
		battle.attack(Vector2.RIGHT)
		ticks(battle, 16)
		rig.sample_weapon()
		directions.append((held.to_global(held.local_point(Vector2(0, 0.8))) - held.global_position).normalized())
		ticks(battle, 29)
	for i in range(4):
		for j in range(i + 1, 4):
			check(directions[i].distance_to(directions[j]) > 0.10, "successive attacks visibly differ: %d / %d" % [i, j])
	battle.reset()
	game.feedback.events.clear()
	battle.attack(Vector2.RIGHT)
	ticks(battle, 28)
	battle.attack(Vector2.RIGHT) # A late input should survive the remaining cooldown.
	battle.attack(Vector2.RIGHT) # Repeated inputs must not enqueue several attacks.
	ticks(battle, 15)
	check(battle.swing > 0.20, "a recovery input starts the next attack when cooldown finishes")
	ticks(battle, 95)
	check(game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "swing").size() == 2, "one buffered input produces exactly one additional attack")
	check(battle.swing == 0, "the chain stops without further input")
	battle.reset()
	game.equipped_weapon.cooldown = 0.62
	game.feedback.events.clear()
	battle.attack(Vector2.RIGHT)
	ticks(battle, 46)
	battle.attack(Vector2.RIGHT)
	ticks(battle, 18)
	check(battle.swing > 0.30, "heavier weapons also accept a late press after the visible recovery")
	battle.reset()
	game.feedback.events.clear()
	battle.attack(Vector2.RIGHT)
	ticks(battle, 46)
	battle.attack(Vector2.RIGHT)
	game.equipped_weapon.grip = Vector2(0, 0.03)
	ticks(battle, 20)
	check(game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "swing").size() == 1, "changing a weapon during cooldown cancels the queued attack")
	game.equipped_weapon.grip = Vector2.ZERO
	game.equipped_weapon.cooldown = 0.40
	for cancel in ["focus", "bow", "bag", "weapon", "hurt"]:
		battle.reset()
		battle.bow_equipped = false
		battle.attack(Vector2.RIGHT)
		ticks(battle, 28)
		battle.attack(Vector2.RIGHT)
		var count_before: int = game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "swing").size()
		match cancel:
			"focus": game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"bow": battle.toggle_bow()
			"bag": game.bag_open = true
			"weapon": game.equipped_weapon.grip = Vector2(0, 0.03)
			"hurt": battle.hurt_player(1, Vector2.LEFT)
		ticks(battle, 70)
		check(game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "swing").size() == count_before, "cancelled input never attacks later: " + cancel)
		game.bag_open = false
		game.equipped_weapon.grip = Vector2.ZERO
	# No discontinuity on an idle-to-attack boundary; check actual blade vertices.
	if battle.get("motion_index") != null:
		for move in range(4):
			battle.reset()
			battle.bow_equipped = false
			battle.targets = [{"position": game.player.position + Vector2(0.70, 0.30), "health": 100.0, "flash": 0.0}]
			battle.attack(Vector2.RIGHT)
			battle.motion_index = move
			ticks(battle, 5)
			check(battle.targets[0].health == 100, "windup does not deal damage in move " + str(move))
			ticks(battle, 30)
			var hp: float = battle.targets[0].health
			check(hp < 100 and hp >= 60, "each real sword motion reaches a nearby target once: " + str(move))
			ticks(battle, 15)
			check(battle.targets[0].health == hp, "recovery cannot repeat the same target damage")
		battle.targets.clear()
		for facing in [-1, 1]:
			game.facing = facing
			for move in range(4):
				battle.bow_equipped = false
				battle.motion_index = move
				battle.recoil = 0
				var last: Array = []
				for frame in range(73):
					battle.swing = 0.36 * (1.0 - float(frame) / 72)
					var paths: Array = rig.sample_weapon()
					check(held.global_position.distance_to(anchor.global_position) < 0.01, "every move keeps the sword in the palm")
					if not last.is_empty():
						check(PaperBladeSweep.motion_distance(last, paths) < 0.22, "continuous blade motion, including the recovery boundary")
					last = paths
	else:
		check(false, "attack variation is available to the shared character rig")
	game.queue_free()
	await process_frame
	print("WEAPON MOTION TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
