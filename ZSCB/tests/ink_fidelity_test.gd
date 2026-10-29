extends SceneTree

var failures: Array[String] = []
var count := 0

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("INK FIDELITY: " + label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	game.camera_x = 0
	game.camera_y = 0
	# Each tooth is intentional ink, not redundant collinear sampling.
	# Continuing past the old 72-point threshold must never rewrite the prefix.
	for tool_mode in [1, 2, 3, 5]:
		game.set_draw_mode(tool_mode)
		game.draft = []
		game.pointer_down(game.world_to_screen(Vector2(-1.5, 0)))
		for index in range(1, 71):
			game.pointer_move(game.world_to_screen(Vector2(-1.5 + index * 0.01, 0.15 if index % 2 else 0.0)))
		var prefix: Array = game.active_stroke.points.duplicate()
		for index in range(71, 241):
			game.pointer_move(game.world_to_screen(Vector2(-1.5 + index * 0.01, 0.15 if index % 2 else 0.0)))
		check(game.active_stroke.points.slice(0, prefix.size()) == prefix, "earlier teeth stay unchanged while continuing tool %d" % tool_mode)
		var before_release: Array = game.active_stroke.points.duplicate()
		game.pointer_up(game.world_to_screen(Vector2(0.9, 0)))
		check(game.draft.size() == 1 and game.draft[0].points == before_release, "pen-up preserves the complete open stroke for tool %d" % tool_mode)
		var first_stroke: Array = game.draft[0].points.duplicate()
		game.pointer_down(game.world_to_screen(Vector2(-1.5, 0.5)))
		game.pointer_move(game.world_to_screen(Vector2(0.9, 0.5)))
		game.pointer_up(game.world_to_screen(Vector2(0.9, 0.5)))
		check(game.draft[0].points == first_stroke and game.objects.is_empty(), "adding another stroke leaves existing ink untouched and ungenerated for tool %d" % tool_mode)
	# The same dense drawing must survive actual weapon, blueprint and JSON paths.
	var weapon := PaperWeaponGrip.make_weapon(game.draft, Vector2(-1.5, 0))
	check(weapon.paths[0].points.size() == 241, "weapon conversion retains all 241 intentional samples")
	var dense: Array = []
	for index in range(241): dense.append(Vector2(-1.5 + index * 0.01, 0.15 if index % 2 else 0.0))
	weapon = PaperWeaponGrip.make_weapon([{"points": dense}], Vector2(-1.5, 0))
	check(PaperNetValidation.weapon(weapon).ok, "detailed weapon remains valid for the existing server")
	var bag := BlueprintBag.new_bag()
	BlueprintBag.add_entry(bag, weapon)
	var object := DrawingRules.building([{"points": dense}], "freehand")
	check(object.paths[0].points.size() == 241 and PaperNetValidation.object(object).ok, "detailed freehand building keeps its samples and passes server validation")
	var saved := SaveStore.save_game("draft", [object], bag, 0, 0, weapon)
	check(saved.ok, "detailed equipped weapon and blueprint can be saved")
	if saved.ok:
		var loaded := SaveStore.load_game()
		check(loaded.error.is_empty(), "detailed drawing can be loaded")
		if loaded.error.is_empty():
			check(loaded.data.equipped_weapon.paths == weapon.paths, "equipped weapon round-trips without losing detail")
			check(loaded.data.bag.entries[0].paths == weapon.paths, "blueprint round-trips without losing detail")
			check(loaded.data.objects[0].paths == object.paths, "building round-trips without losing detail")
	# Over-complex drawings are retained with explicit failure, never thinned or submitted.
	game.set_draw_mode(1)
	var excessive: Array = []
	for index in range(8193): excessive.append(Vector2(float(index % 80) * 0.01, float(index % 2) * 0.15))
	game.draft = [{"points": excessive}]
	var old_ink: float = game.ink.amount
	game.generate()
	check(game.objects.is_empty() and game.draft.size() == 1 and game.draft[0].points == excessive, "over-budget generation preserves the entire draft without creating an unsavable object")
	check(game.ink.amount == old_ink, "over-budget generation does not charge ink")
	var valid_limit: Dictionary = object.duplicate(true)
	valid_limit.paths[0].points = excessive.slice(0, 8192)
	check(PaperNetValidation.object(valid_limit).ok and SaveStore.save_game("draft", [valid_limit], bag, 0, 0).ok, "8192 samples remain accepted by network validation and local saves")
	var invalid_limit: Dictionary = object.duplicate(true)
	invalid_limit.paths[0].points = excessive
	check(not PaperNetValidation.object(invalid_limit).ok and not SaveStore.save_game("draft", [invalid_limit], bag, 0, 0).ok, "8193-sample path is rejected without silently reducing it")
	game.queue_free()
	await process_frame
	print("INK FIDELITY TESTS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
