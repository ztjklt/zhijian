extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("PAPER_MAP_CAPTURE_DIR")
	if folder.is_empty(): folder = "/tmp/paper-core-knowledge-map"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func place(game, point: Vector2) -> void:
	game.player.position = point
	PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, point))

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.combat.set_natives(false)
	for frame in range(60): await physics_frame
	await capture("01-math-default-entry")
	game.set_physics_process(false)
	game.player.freeze = true
	game.knowledge_world.visit(1)
	place(game, Vector2(30, 5.13))
	game.camera_x = 39
	game.camera_y = 3.2
	game.PIXELS_PER_UNIT = 46
	game.pose = "idle"
	game.land_timer = 0
	await capture("02-complete-poems")
	game.knowledge_world.visit(3)
	place(game, Vector2(87, -1.2))
	game.camera_x = 87
	game.camera_y = 0.2
	game.PIXELS_PER_UNIT = 60
	game.set_draw_mode(3)
	game.draft = [{"points": [Vector2(89, 1), Vector2(91, 1)]}, {"points": [Vector2(89.4, 1), Vector2(89.4, 2)]}]
	await capture("03-core-drawing-on-physics-map")
	game.set_draw_mode(2)
	game.draft = [{"points": [Vector2(88, 1), Vector2(88, 2.5)]}, {"points": [Vector2(87.6, 1.25), Vector2(88.4, 1.25)]}]
	game.generate()
	game.select_weapon_grip(Vector2(88, 1.1))
	await capture("04-multi-stroke-grip-on-map")
	game.generate()
	game.feedback.events.clear()
	game.combat.set_natives(true)
	for i in game.combat.natives.size():
		var native = game.combat.natives[i]
		native.position = Vector2(90 + i * 1.5, game.ground_height_at(90 + i * 1.5) + 0.3)
		native.home_x = native.position.x
	game.combat.toggle_bow()
	game.aim_world = game.player.position + Vector2(5, 1)
	game.combat.bow_direction = Vector2(1, 0.1).normalized()
	game.combat.bow_charge = 0.16
	await capture("05-core-bow-and-natives-on-map")
	game.combat.set_natives(false)
	game.knowledge_world.toggle_overview()
	await capture("06-six-chapter-overview")
	game.knowledge_world.toggle_overview()
	for size in [Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = size
		game.knowledge_world.visit(1)
		place(game, Vector2(29, 5.13))
		game.camera_x = 29
		game.camera_y = game.camera_target_y()
		game.touch_controls.force_visible = true
		game.toolbar._layout()
		game.touch_controls._layout()
		await capture("07-compact-%dx%d" % [size.x, size.y])
	game.queue_free()
	for frame in range(5): await process_frame
	print("CORE KNOWLEDGE MAP VISUAL COMPLETE")
	quit()
