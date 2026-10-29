extends SceneTree

func _init() -> void: call_deferred("run")

func shot(path: String) -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("/tmp/paper-godot-experience")
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.feedback.audio_enabled = false
	game.onboarding.visible = false
	for i in range(12): await physics_frame
	game.experience.open()
	await shot("/tmp/paper-godot-experience/experience-1280.png")
	print("EXPERIENCE INITIAL RECT: ", game.experience.panel.get_global_rect(), " MIN: ", game.experience.panel.get_combined_minimum_size(), " SCROLL: ", game.experience.scroll.get_rect(), " SCROLL MIN: ", game.experience.scroll.get_combined_minimum_size())
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(game.experience.panel.get_global_rect()):
		push_error("The initial desktop panel must fit before any resize")
		game.queue_free()
		for i in range(4): await process_frame
		quit(1)
		return
	game.experience.scroll.scroll_vertical = 10000
	await shot("/tmp/paper-godot-experience/experience-details.png")
	game.experience.scroll.scroll_vertical = 0
	game.experience.try_sword()
	for i in range(20): await physics_frame
	await shot("/tmp/paper-godot-experience/knowledge-play.png")
	game.experience.show_map()
	await shot("/tmp/paper-godot-experience/six-chapters.png")
	game.knowledge_world.toggle_overview()
	for size in [Vector2i(960, 540), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = size
		game.experience.open()
		await shot("/tmp/paper-godot-experience/experience-%dx%d.png" % [size.x, size.y])
		assert(Rect2(Vector2.ZERO, Vector2(size)).encloses(game.experience.panel.get_global_rect()))
	game.queue_free()
	for i in range(4): await process_frame
	print("EXPERIENCE VISUAL COMPLETE: 4 window sizes, real map, trial sword and overview")
	quit()
