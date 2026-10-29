extends SceneTree

var failures: Array[String] = []
func check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/title_menu.tscn", "startup opens approved cover before map selection")
	check(ResourceLoader.exists("res://scenes/medieval.tscn"), "independent medieval scene exists")
	if not failures.is_empty():
		finish()
		return
	var selector = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(selector)
	check(selector.has_method("start_map"), "selector has real map actions")
	root.size = Vector2i(1440, 960)
	await process_frame
	await process_frame
	root.size = Vector2i(390, 844)
	await process_frame
	await process_frame
	await process_frame
	check_selector_bounds(selector, "desktop to narrow")
	selector.free()
	selector = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(selector)
	await process_frame
	await process_frame
	check_selector_bounds(selector, "direct narrow startup")
	selector.free()
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/medieval.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	check(game.world_kind == "medieval-v1", "medieval world selected")
	check(game.knowledge_world == null and game.medieval_world != null, "worlds remain independent")
	check(not game.combat.natives_enabled, "medieval starts without unrelated native actors")
	check(game.medieval_world.entities.size() >= 15, "complete village and castle populated")
	var original_save := "user://paper_castle_v3.json"
	var sentinel := FileAccess.open(original_save, FileAccess.WRITE)
	sentinel.store_string("knowledge sentinel")
	sentinel.close()
	var entity = game.medieval_world.entities.front()
	game.medieval_world.damage_entity(entity, 12, entity.position, Vector2(0.5, 0.2))
	var before: Array = game.medieval_world.save_state()
	check(game.save_game(), "medieval save succeeds")
	check(FileAccess.get_file_as_string(original_save) == "knowledge sentinel", "medieval save does not overwrite knowledge")
	var loaded: Dictionary = SaveStore.load_game("medieval-v1")
	check(loaded.error.is_empty(), "medieval independently loads: " + loaded.error)
	check(loaded.data.get("world", {}).get("id") == "medieval-v1", "saved map ID preserved")
	check(loaded.data.get("world", {}).get("entities", []).size() == before.size(), "all medieval state persists")
	check(loaded.data.get("world", {}).get("entities", [{}]).front().get("health", 0) == before.front().health, "damaged health survives JSON roundtrip")
	check(loaded.data.get("world", {}).get("entities", [{}]).front().get("cuts", []).size() == before.front().cuts.size(), "local cuts survive JSON roundtrip")
	check(game.medieval_world.restore_state(loaded.data.world.entities), "loaded JSON restores real map entities")
	await process_frame
	check(is_equal_approx(game.medieval_world.entities.front().health, before.front().health), "restored physical entity keeps damage")
	game.toolbar.map_button.pressed.emit()
	await process_frame
	game.map_controls.panel.reset_size()
	var menu_point: Vector2 = game.map_controls.menu_button.get_global_rect().get_center()
	check(game.toolbar.blocks_canvas(menu_point), "map navigation blocks touch ink")
	check(game.toolbar.touch_button_at(menu_point) == game.map_controls.menu_button, "touch router finds map menu button")
	var good := FileAccess.get_file_as_string("user://paper_castle_medieval_v1.json")
	var invalid: Dictionary = game.world_save_state()
	invalid.entities = [before.front(), before.front()]
	var bad: Dictionary = SaveStore.save_game(game.paper, game.objects, game.bag, game.camera_x, game.player.position.x, game.equipped_weapon, invalid)
	check(not bad.ok, "duplicate medieval IDs rejected")
	check(FileAccess.get_file_as_string("user://paper_castle_medieval_v1.json") == good, "invalid state preserves good save")
	game.select_world("knowledge-v1")
	await physics_frame
	check(game.medieval_world == null and game.knowledge_world != null, "switch removes medieval world")
	game.select_world("medieval-v1")
	await physics_frame
	check(game.knowledge_world == null and game.medieval_world != null, "switch removes knowledge world")
	game.draft = [{"points": [Vector2(1, 1), Vector2(2, 2)]}]
	game.return_to_map_select()
	await process_frame
	await process_frame
	var menu = current_scene
	check(is_instance_valid(menu) and menu.has_method("start_map"), "game returns to selector")
	if is_instance_valid(menu) and menu.has_method("start_map"):
		var dormant_age: float = game.medieval_world.elapsed
		menu.start_map("knowledge-v1", false)
		await physics_frame
		await physics_frame
		await process_frame
		var knowledge = current_scene
		check(knowledge.world_kind == "knowledge-v1", "selector opens separate knowledge session")
		check(is_equal_approx(game.medieval_world.elapsed, dormant_age), "cached medieval physics step stays dormant")
		check(game.process_mode == Node.PROCESS_MODE_DISABLED, "dormant game disables its simulation")
		var layers_hidden := true
		for layer in game.find_children("*", "CanvasLayer", true, false):
			if layer.visible: layers_hidden = false
		check(layers_hidden, "cached world UI cannot bleed into selected map")
		knowledge.return_to_map_select()
		await process_frame
		await process_frame
		menu = current_scene
		menu.start_map("medieval-v1", true)
		await process_frame
		check(current_scene == game and not game.draft.is_empty(), "resume retains active drafts and game across another map")
	game.free()
	await test_selector_isolation()
	finish()

func finish() -> void:
	if failures.is_empty(): print("MEDIEVAL_INTEGRATION_OK")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_selector_bounds(selector, label: String) -> void:
	var viewport_width := root.get_visible_rect().size.x
	print("SELECTOR GEOMETRY ", label, " viewport=", viewport_width, " scroll=", selector.scroll.size.x, " scroll_min=", selector.scroll.get_combined_minimum_size().x, " content=", selector.content.size.x, " cards=", selector.cards.size.x)
	for card in selector.cards.get_children():
		var bounds: Rect2 = card.get_global_rect()
		check(bounds.position.x >= 0 and bounds.end.x <= viewport_width, label + " card stays within screen")
		var column = card.get_child(0)
		var actions = column.get_child(column.get_child_count() - 1)
		for button in actions.get_children():
			var button_bounds: Rect2 = button.get_global_rect()
			check(button_bounds.position.x >= bounds.position.x and button_bounds.end.x <= minf(bounds.end.x, viewport_width), label + " both actions fit card")

func clear_cached_sessions() -> void:
	var holder := root.get_node_or_null("MapSessions")
	if holder != null:
		for child in holder.get_children(): child.free()

func add_marker(game, at: float) -> void:
	game.objects.append({"kind":"freehand", "x":at, "y":-1.0, "dynamic":false, "paths":[{"points":[Vector2.ZERO,Vector2(1,0)], "collision":true}]})
	game._rebuild_objects()

func test_selector_isolation() -> void:
	clear_cached_sessions()
	var original = load("res://scenes/sandbox.tscn").instantiate()
	root.add_child(original)
	current_scene = original
	add_marker(original, 12.0)
	original.change_map("nature-v1")
	check(original.save_game(), "common save contains knowledge workspace with nature active")
	original.free()
	var menu = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.start_map("knowledge-v1", true)
	await process_frame
	var loaded = current_scene
	check(loaded.world_kind == "knowledge-v1", "knowledge load selects requested saved workspace when nature was active")
	check(loaded.objects.size() == 1 and is_equal_approx(float(loaded.objects.front().x), 12.0), "requested knowledge objects restored from common save")
	loaded.free()
	for active_requested in [false, true]:
		clear_cached_sessions()
		var cached = load("res://scenes/medieval.tscn").instantiate()
		root.add_child(cached)
		current_scene = cached
		cached.change_map("knowledge-v1")
		add_marker(cached, 14.0)
		cached.draft = [{"points":[Vector2(10,2),Vector2(11,3)]}]
		if active_requested: cached.change_map("medieval-v1")
		cached.return_to_map_select()
		await process_frame
		await process_frame
		menu = current_scene
		menu.start_map("medieval-v1", false)
		await process_frame
		var fresh = current_scene
		check(fresh.world_kind == "medieval-v1" and fresh != cached, "explicit new opens a fresh medieval session")
		check(is_instance_valid(cached), "new medieval preserves other cached map session " + str(active_requested))
		if is_instance_valid(cached):
			check(not cached.draft.is_empty(), "new medieval preserves unrelated cached draft " + str(active_requested))
		fresh.return_to_map_select()
		await process_frame
		await process_frame
		menu = current_scene
		var preserved = menu._cached_game("knowledge-v1")
		check(preserved != null, "knowledge session remains resumable after new medieval " + str(active_requested))
		if preserved != null:
			menu.start_map("knowledge-v1", true)
			await process_frame
			check(current_scene.objects.size() == 1 and is_equal_approx(float(current_scene.objects.front().x), 14.0), "unrelated knowledge objects survive new medieval " + str(active_requested))
			check(not current_scene.draft.is_empty(), "unrelated draft survives resumed knowledge " + str(active_requested))
			current_scene.free()
		else: menu.free()
	clear_cached_sessions()
	var legacy = load("res://scenes/main.tscn").instantiate()
	root.add_child(legacy)
	current_scene = legacy
	add_marker(legacy, 16.0)
	legacy.change_map("medieval-v1")
	legacy.draft = [{"points":[Vector2(1,1),Vector2(2,2)]}]
	legacy.return_to_map_select()
	await process_frame
	await process_frame
	menu = current_scene
	menu.start_map("medieval-v1", false)
	await process_frame
	check(is_instance_valid(legacy) and legacy.world_kind == "paper", "new medieval parks and preserves legacy flat workspace")
	var newest = current_scene
	newest.return_to_map_select()
	await process_frame
	await process_frame
	menu = current_scene
	check(menu._cached_game("knowledge-v1") == legacy, "notebook card can resume retained legacy flat work")
	menu.start_map("knowledge-v1", true)
	await process_frame
	check(current_scene == legacy and legacy.world_kind == "paper" and legacy.objects.size() == 1 and not legacy.draft.is_empty(), "legacy flat map, objects and draft remain intact on resume")
	legacy.free()
	clear_cached_sessions()
