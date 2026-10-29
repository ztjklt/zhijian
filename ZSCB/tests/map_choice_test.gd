extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("MAP CHOICE: " + label)
func frames() -> void:
	for i in range(4): await process_frame
func run() -> void:
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await frames()
	game.set_physics_process(false)
	game.player.freeze = true
	game.combat.set_natives(false)
	check(game.has_method("change_map"), "map alternatives are selectable in the core game")
	if not game.has_method("change_map"):
		game.queue_free()
		await frames()
		quit(1)
		return
	var original: Dictionary = DrawingRules.building([{"points": [Vector2(11,6), Vector2(12,6)]}], "freehand")
	game.objects.append(original)
	game.object_nodes.append(game._build_physics_for_object(original))
	game.equipped_weapon = PaperWeaponGrip.practice_sword()
	var weapon: Dictionary = game.equipped_weapon.duplicate(true)
	var bag: Dictionary = game.bag.duplicate(true)
	game.draft = [{"points": [Vector2(13,5),Vector2(14,5)]}]
	game.change_map("nature-v1")
	await frames()
	check(game.world_kind == "nature-v1" and game.knowledge_world.map_title().contains("自然"), "selected nature alternative uses the actual nature terrain")
	check(game.objects.is_empty(), "nature map has its own building workspace instead of burying textbook creations")
	check(game.draft.size() == 1 and game.equipped_weapon == weapon and game.bag == bag, "switching maps retains drafts, equipment and reusable blueprints")
	var natural: Dictionary = DrawingRules.building([{"points": [Vector2(11,12), Vector2(13,12)]}], "freehand")
	game.objects.append(natural)
	game.object_nodes.append(game._build_physics_for_object(natural))
	game.change_map("knowledge-v1")
	await frames()
	check(game.objects.size() == 1 and game.objects[0].paths == original.paths, "returning restores that map's previous building")
	check(game.save_game(), "saving includes retained alternate-map work")
	game.change_map("nature-v1")
	await frames()
	check(game.objects.size() == 1 and game.objects[0].paths == natural.paths, "natural-map work survives switching away and back")
	game.load_game()
	await frames()
	check(game.world_kind == "knowledge-v1", "loading restores the saved active map")
	game.change_map("nature-v1")
	await frames()
	check(game.objects.size() == 1 and game.objects[0].paths == natural.paths, "inactive map work also survives a real save and load")
	check(game.objects[0].paths[0].points[0] is Vector2, "alternate map ink vectors restore as actual geometry")
	game.change_map("unknown-map")
	check(game.world_kind == "nature-v1", "unknown map IDs leave the current work intact")
	game.queue_free()
	await frames()
	var menu = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await frames()
	check(not menu.continue_buttons.has("nature-v1") and menu.legacy_nature_button != null, "the fused startup keeps an explicit continuation for existing nature work")
	if menu.legacy_nature_button != null:
		menu.legacy_nature_button.pressed.emit()
		await frames()
		var selected = current_scene
		check(selected is PaperCastleMain and selected.world_kind == "nature-v1", "the legacy continuation starts the real saved natural sandbox")
		if selected is PaperCastleMain:
			check(selected.objects.size()==1 and selected.objects[0].paths==natural.paths,"legacy continuation restores existing nature ink rather than a blank map")
		if selected != null: selected.queue_free()
	else: menu.queue_free()
	await frames()
	print("MAP CHOICE TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
