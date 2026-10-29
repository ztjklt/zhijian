extends SceneTree

func _init() -> void: call_deferred("run")

func shot(path: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute("/tmp/paper-responsive-ui")
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.feedback.audio_enabled = false
	game.onboarding.visible = false
	for i in range(90): await physics_frame
	game.player.freeze = true
	game.set_physics_process(false)
	for dimensions in [Vector2i(1440,900), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(390,844), Vector2i(844,390)]:
		root.min_size = dimensions
		root.size = dimensions
		game.touch_controls.force_visible = dimensions.x < 900
		game.touch_controls._layout()
		for i in range(6): await process_frame
		game.camera_y = game.camera_target_y()
		await shot("/tmp/paper-responsive-ui/world-%dx%d.png" % [dimensions.x, dimensions.y])
		game.toggle_bag()
		game.select_blueprint(game.bag.entries.back().id)
		await shot("/tmp/paper-responsive-ui/bag-%dx%d.png" % [dimensions.x, dimensions.y])
		game.toggle_bag()
		game.experience.open()
		await shot("/tmp/paper-responsive-ui/experience-%dx%d.png" % [dimensions.x, dimensions.y])
		game.experience.close()
	game.queue_free()
	for i in range(4): await process_frame
	print("RESPONSIVE UI VISUAL: Metal render, five live sizes, world/bag/modal")
	quit()
