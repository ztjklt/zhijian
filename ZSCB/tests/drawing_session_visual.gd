extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.title = "纸上城堡 · 多轮绘画与握持点验收"
	for size in [Vector2i(1280, 720), Vector2i(844, 390)]:
		root.size = size
		var game = load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist = false
		game.onboarding.dismiss()
		root.add_child(game)
		await process_frame
		game.set_physics_process(false)
		game.player.freeze = true
		game.player.position = Vector2(-3.4, game.GROUND_Y + 0.54)
		game.camera_x = -1
		game.flip_timer = 0
		game.set_draw_mode(2)
		var origin := Vector2(0.6, game.GROUND_Y + 0.7)
		game.draft = [{"points": [origin, origin + Vector2(0, 1.6)]}, {"points": [origin + Vector2(-0.5, 0.4), origin + Vector2(0.5, 0.4)]}]
		game.toolbar._layout()
		game.touch_controls._layout()
		await capture("/tmp/paper-drawing-%dx%d-draft.png" % [size.x, size.y])
		game.generate()
		game.pointer_down(game.world_to_screen(origin + Vector2(0, 0.2)))
		await capture("/tmp/paper-drawing-%dx%d-grip.png" % [size.x, size.y])
		game.generate()
		await capture("/tmp/paper-drawing-%dx%d-equipped.png" % [size.x, size.y])
		game.queue_free()
		await process_frame
	print("DRAWING SESSION VISUAL COMPLETE")
	quit()
