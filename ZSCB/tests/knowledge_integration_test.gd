extends SceneTree

var failures: Array[String] = []
var count := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("KNOWLEDGE INTEGRATION: " + label)

func frames(amount: int) -> void:
	for i in range(amount): await physics_frame

func teleport(game, at: Vector2) -> void:
	game.knowledge_world.checkpoint = at
	game.knowledge_world.respawn()
	game.knowledge_world._update_chunks()
	await frames(3)

func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(2)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	var world = game.get("knowledge_world")
	check(world != null, "normal project launch enters the complete knowledge map with core gameplay")
	if world == null:
		game.queue_free()
		await process_frame
		finish()
		return
	game.combat.set_natives(false)
	check(world.semantic_blocks.size() >= 18 and world.terrain_rects.size() == 6, "all six complete knowledge chapters load in the core game")
	check(game.ground_chunks.is_empty(), "no legacy flat floor remains under the textbook terrain")
	for chapter in [0, 1, 3, 5]:
		world.visit(chapter)
		await frames(40)
		var expected_top: float = [-2.8, -2.16, -2.8, -1.52, -2.16, -2.8][chapter]
		check(absf(game.player.position.y - expected_top - 0.29) < 0.12, "player stands on actual chapter foundation " + str(chapter))
	var probe := Vector2(40, 9.5)
	game.camera_y = 7.0
	check(game.screen_to_world(game.world_to_screen(probe)).distance_to(probe) < 0.001, "vertical camera and drawing coordinates share one reversible transform")
	world.visit(0)
	await frames(3)
	game.player.freeze = true
	var old_count: int = game.objects.size()
	game.set_draw_mode(3)
	game.draft = [{"points": [Vector2(11, 3), Vector2(12, 3)]}]
	game.generate()
	check(game.objects.size() == old_count + 1, "core multi-stroke building flow generates on the knowledge map")
	await frames(80)
	if game.objects.size() > old_count:
		check(game.object_bounds(game.objects.back()).position.y > -2.9, "dynamic ink settles on the actual map foundation")
	game.set_draw_mode(5)
	game.draft = [{"points": [Vector2(12, 4), Vector2(13, 4)]}]
	game.generate()
	check(game.objects.size() == old_count + 2, "core automatic sculpting survives map integration")
	game.player.freeze = false
	# A raised summary is bypassable, whereas chapter foundations never are.
	await teleport(game, Vector2(11, 11.4))
	await frames(75)
	check(game.player.position.y > 10.7 and game.player.begin_drop_through(), "summary paragraph platform supports and permits an intentional drop")
	await frames(70)
	check(game.player.position.y < 10.6, "dropping actually passes below the thick summary paragraph")
	world.visit(1)
	await frames(40)
	check(not game.player.begin_drop_through(), "chapter foundation cannot be bypassed with the drop command")
	await tap("jump")
	await frames(5)
	await tap("jump")
	check(game.jumps_used == 2 and game.player.linear_velocity.y > 5, "second jump boosts the player above actual textbook terrain")
	await teleport(game, Vector2(25, -2.45))
	Input.action_press("move_right")
	await frames(90)
	Input.action_release("move_right")
	check(game.player.position.x > 27 and game.player.position.y > -1.95, "core automatic wall climb crosses the real chapter edge")
	world.visit(1)
	await teleport(game, Vector2(29, 5.5))
	await frames(60)
	check(absf(game.player.position.y - 5.125) < 0.12, "complete poem line supports the core character")
	await tap("move_down")
	await tap("move_down")
	await frames(18)
	check(game.player.position.y < 4.7 and game.player.position.y > 3.7, "double S drops one poem line and lands on the next")
	world.visit(3)
	game.combat.set_natives(true)
	var supported_spawns := true
	for native in game.combat.natives:
		supported_spawns = supported_spawns and native.position.y > world.surface_height(native.position.x) + 0.5 and native.position.x > 0 and native.position.x < 156
	check(supported_spawns, "roaming combat actors spawn above their actual chapter foundation")
	game.combat.set_natives(false)
	game.combat.cooldown = 1
	world.toggle_overview()
	await frames(5)
	check(game.is_physics_processing() and not game.player.freeze and game.combat.cooldown < 0.99, "map overview keeps the sandbox and combat simulation running")
	var before_ink: int = game.draft.size()
	game.pointer_down(game.world_to_screen(Vector2(35, 0)))
	check(not world.overview and game.draft.size() == before_ink, "clicking overview navigates to a chapter without drawing accidental ink")
	for size in [Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = size
		await process_frame
		await process_frame
		world.visit(1)
		await frames(3)
		var on_screen: Vector2 = game.world_to_screen(game.player.position)
		check(on_screen.y > world.controls.panel.get_global_rect().end.y + 15 and on_screen.y < size.y - 80, "camera keeps the player between map controls and touch buttons at " + str(size))
	root.size = Vector2i(1280, 720)
	await process_frame
	# A horizontal arrow must hit the real 0.64 m chapter step, not fly through it.
	await teleport(game, Vector2(25, -2.45))
	game.player.freeze = true
	game.combat.projectiles.clear()
	game.combat.shoot_arrow(Vector2(25.5, -2.5), Vector2.RIGHT, "player")
	game.combat._step_projectiles(0.1)
	check(game.combat.projectiles.is_empty(), "arrow is blocked by the textbook chapter step")
	var blade_wall: Dictionary = game.combat._blade_structure([PackedVector2Array([Vector2(25.5, -2.6), Vector2(25.5, -2.4)])], [PackedVector2Array([Vector2(26.5, -2.6), Vector2(26.5, -2.4)])])
	check(not blade_wall.is_empty() and blade_wall.index == -1, "model-based sword sweep sees the same solid chapter step")
	# Save from high in literature, restore map, position, camera, marks and ink objects.
	await teleport(game, Vector2(35, 12))
	game.camera_x = 35
	game.camera_y = 8
	game.knowledge_world.collected = {1: true}
	game.set_physics_process(false)
	check(game.save_game(), "knowledge world saves through the actual core save action")
	var saved := SaveStore.load_game()
	check(saved.error == "" and saved.data.get("world", {}).get("id", "") == "knowledge-v1", "saved world explicitly identifies the knowledge map")
	world.visit(0)
	game.load_game()
	check(game.get("knowledge_world") != null and game.player.position.distance_to(Vector2(35, 12)) < 0.02, "loading restores the same map and both player coordinates")
	check(is_equal_approx(game.camera_y, 8) and game.knowledge_world.collected.has(1), "vertical camera and collected bookmarks survive load")
	check(game.save_game(), "subsequent map save succeeds with a previous version backup")
	var healthy_bytes := FileAccess.get_file_as_string(SaveStore.SAVE_PATH)
	var storage: Variant = load("res://scripts/save_store.gd")
	var rejected: Dictionary = storage.save_game("draft", [], BlueprintBag.new_bag(), 0, 0, {}, {"id": "bad-map"})
	check(not rejected.ok and FileAccess.get_file_as_string(SaveStore.SAVE_PATH) == healthy_bytes, "invalid map metadata cannot overwrite the good save")
	var bad_ink := [{"x": 0.0, "y": 1.0, "paths": [{"points": [Vector2.ZERO, Vector2(300, 0)]}]}]
	var invalid_object := SaveStore.save_game("draft", bad_ink, BlueprintBag.new_bag(), 0, 0)
	check(not invalid_object.ok and FileAccess.get_file_as_string(SaveStore.SAVE_PATH) == healthy_bytes, "invalid drawn geometry cannot replace the recoverable knowledge world")
	check(FileAccess.file_exists(SaveStore.SAVE_PATH + ".bak"), "save replacement retains a recoverable previous version")
	SaveStore.save_game("draft", [], BlueprintBag.new_bag(), 5, 5)
	game.load_game()
	await frames(3)
	check(game.get("knowledge_world") == null and not game.ground_chunks.is_empty(), "legacy version 2 works retain their original flat terrain")
	game.undo()
	check(game.get("knowledge_world") != null, "undoing a legacy-world load restores the knowledge map rather than mixing floors")
	game.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("KNOWLEDGE INTEGRATION: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
