extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("BLADE MODEL: " + label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var native = game.combat.natives[0]
	check("visual" in native, "native reuses the protagonist scene with a color-only material")
	if not "visual" in native or not ResourceLoader.exists("res://scripts/blade_sweep.gd"):
		game.queue_free()
		await process_frame
		quit(1)
		return
	var rig: Node2D = native.visual
	check(rig.scene_file_path == game.character_visual.scene_file_path, "native and protagonist instantiate the exact same model scene")
	var head_path := "Skeleton/Hips/Torso/Head/Ink"
	check(rig.get_node(head_path).texture == game.character_visual.get_node(head_path).texture, "gray native preserves the original protagonist artwork")
	check(rig.material is ShaderMaterial and game.character_visual.material == null, "only the native gets the gray color conversion")
	check(rig.get_node("AnimationPlayer").get_animation("walk") == game.character_visual.get_node("AnimationPlayer").get_animation("walk"), "running uses the original animation resource")
	var sweep = load("res://scripts/blade_sweep.gd")
	var short_blade: Array = [PackedVector2Array([Vector2.ZERO, Vector2(0.5, 0)])]
	check(sweep.circle_contact(short_blade, short_blade, Vector2(2, 0), 0.1).is_empty(), "short sword cannot hit a target in an invented long reach")
	check(sweep.circle_contact(short_blade, short_blade, Vector2(0.3, 0.7), 0.1).is_empty(), "being near a sword's owner is insufficient when the blade misses")
	var old: Array = [PackedVector2Array([Vector2(0, -1), Vector2(0, 1)])]
	var now: Array = [PackedVector2Array([Vector2(1, -1), Vector2(1, 1)])]
	check(not sweep.circle_contact(old, now, Vector2(0.5, 0), 0.1).is_empty(), "sword sweep catches a body crossed between rendered frames")
	var other: Array = [PackedVector2Array([Vector2(0.4, 0), Vector2(0.6, 0)])]
	check(not sweep.blade_contact(old, now, other, other).is_empty(), "two actual sword models crossing create a contact")
	var far: Array = [PackedVector2Array([Vector2(3, 2), Vector2(4, 2)])]
	check(sweep.blade_contact(old, now, far, far).is_empty(), "nearby attacks do not clash without blade contact")
	var hollow: Array = [PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])]
	check(sweep.circle_contact(hollow, hollow, Vector2(0.8, 0.2), 0.1).is_empty(), "an irregular sword's empty region is not a filled hit box")
	var outline: Array = [PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)])]
	check(sweep.circle_contact(outline, outline, Vector2.ZERO, 0.1).is_empty(), "a closed ink outline preserves its empty interior unless its model is filled")
	var small := {"grip": Vector2.ZERO, "paths": [{"points": [Vector2.ZERO, Vector2(0.5, 0)]}], "reach": 99, "damage": 999}
	var large := {"grip": Vector2.ZERO, "paths": [{"points": [Vector2.ZERO, Vector2(1.5, 0)]}], "reach": 0.1, "damage": 1}
	check(sweep.model_damage(large, 10) > sweep.model_damage(small, 10), "damage derives from actual sword size rather than metadata reach/damage")
	check(sweep.model_damage(large, 15) > sweep.model_damage(large, 2), "a faster moving sword model delivers a stronger impact")
	# World paths come from the very same held sword node that draws the model.
	var held = rig.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	var paths: Array = rig.sample_weapon()
	check(not paths.is_empty(), "native carries a real sword model attached to the original hand bone")
	if not paths.is_empty():
		var point: Vector2 = held.weapon.paths[0].points[0]
		check(paths[0][0].is_equal_approx(game.screen_to_world(held.to_global(held.local_point(point)))), "collision traces and displayed sword use identical grip and transforms")
	var battle = game.combat
	var player_y: float = game.player.position.y
	native.position = Vector2(-70, player_y)
	native.state = "strike"
	native.action_time = 0.1
	native.blade_paths = [PackedVector2Array([Vector2(-70, player_y - 1), Vector2(-70, player_y + 1)])]
	native.previous_blade_paths = native.blade_paths
	battle.health = 100
	battle.invulnerable = 0
	battle.step(1.0 / 60.0)
	check(battle.health == 100 and native.state == "wander", "streaming a distant native resets its old attack instead of sweeping across the whole map")
	battle.reset()
	game.combat.set_natives(false)
	game.equipped_weapon = small.duplicate(true)
	game.equipped_weapon.cooldown = 0.4
	var at: Vector2 = game.player.position
	game.combat.targets = [{"position": at + Vector2(2, 0.2), "health": 100.0, "flash": 0.0, "respawn": 0.0}]
	game.combat.attack(Vector2.RIGHT)
	check(game.combat.targets[0].health == 100, "pressing attack starts a motion rather than an invisible instant damage ray")
	for frame in range(20): game.combat.step(1.0 / 60.0)
	check(game.combat.targets[0].health == 100, "fake reach metadata cannot extend the actual half-meter sword in the game")
	game.combat.targets[0].position = at + Vector2(0.65, 0.2)
	game.combat.cooldown = 0
	game.combat.attack(Vector2.RIGHT)
	for frame in range(20): game.combat.step(1.0 / 60.0)
	check(game.combat.targets[0].health < 100 and game.combat.targets[0].health >= 60, "a real short sword sweep hits at its displayed length with bounded model-derived damage")
	game.combat.cooldown = 0
	game.combat.attack(Vector2.RIGHT)
	game.equipped_weapon = large.duplicate(true)
	game.equipped_weapon.cooldown = 0.4
	game.combat.step(1.0 / 60.0)
	check(game.combat.swing == 0, "replacing a sword cancels the old swing instead of morphing its collision across models")
	var wall: Dictionary = DrawingRules.building([{"points": [Vector2(0, -0.2), Vector2(0, 0.2)]}], "freehand")
	wall.x = 1
	wall.y = 0
	game.objects.append(wall)
	var before_wall: Array = [PackedVector2Array([Vector2(0.8, -1), Vector2(0.8, 1)])]
	var after_wall: Array = [PackedVector2Array([Vector2(1.2, -1), Vector2(1.2, 1)])]
	check(not game.combat._blade_structure(before_wall, after_wall).is_empty(), "a sword's middle collides with a small structure crossed between frames, even when both tip traces miss")
	game.objects.clear()
	game.queue_free()
	await process_frame
	print("BLADE MODEL TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
