extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(file: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.title = "纸上城堡 · 自动塑形验收"
	for size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = size
		var game = load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist = false
		game.onboarding.visible = false
		root.add_child(game)
		await process_frame
		game.player.position = Vector2(-1.5, game.GROUND_Y + 0.5)
		game.set_draw_mode(4)
		game.toggle_sculpt()
		var center: Vector2 = game.screen_to_world(Vector2(size.x * 0.58, size.y * 0.5))
		game.draft = []
		for half in range(2):
			var points: Array = []
			for i in range(25):
				var t := PI * (half + i / 24.0)
				var radius := 0.64 * (1 + 0.09 * sin(i * 2.5))
				points.append(center + Vector2(cos(t), sin(t)) * radius)
			game.draft.append({"points": points})
		game.touch_controls.force_visible = size.y < 500 or size.x < 600
		game.toolbar._layout()
		await capture("/tmp/paper-sculpt-before-%dx%d.png" % [size.x, size.y])
		game.generate()
		# Freeze only in this visual check to compare geometry at the same position.
		for body in game.object_nodes: body.freeze = true
		await capture("/tmp/paper-sculpt-after-%dx%d.png" % [size.x, size.y])
		var button: Button = game.toolbar.mode_buttons[4]
		if button.get_global_rect().end.x > size.x: push_error("5 button exceeds viewport")
		game.queue_free()
		await process_frame
	print("SCULPT VISUAL COMPLETE")
	quit()
