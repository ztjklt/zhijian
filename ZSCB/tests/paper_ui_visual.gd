extends SceneTree

func _init() -> void: call_deferred("run")

func shot(path: String) -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("/tmp/paper-ui-proof")
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.feedback.audio_enabled = false
	game.onboarding.visible = false
	game.combat.set_natives(false)
	for i in range(12): await physics_frame
	for n in range(6):
		BlueprintBag.add_entry(game.bag, {"kind": "weapon" if n == 0 else "freehand", "source": "own", "role": "weapon" if n == 0 else "building", "grip": Vector2.ZERO, "paths": [{"points": [Vector2.ZERO, Vector2(0.7, 0), Vector2(0.5, 0.7), Vector2.ZERO]}]})
	for window_size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = window_size
		game.touch_controls.force_visible = window_size.x < 900
		game.touch_controls._layout()
		game.activate_draw_mode(4)
		await shot("/tmp/paper-ui-proof/tools-%dx%d.png" % [window_size.x, window_size.y])
		game.toggle_bag()
		game.select_blueprint(game.bag.entries.back().id)
		await shot("/tmp/paper-ui-proof/bag-%dx%d.png" % [window_size.x, window_size.y])
		game.toggle_bag()
	game.queue_free()
	for i in range(4): await process_frame
	print("PAPER UI VISUAL: 4 sizes rendered with tools and populated collection")
	quit()
