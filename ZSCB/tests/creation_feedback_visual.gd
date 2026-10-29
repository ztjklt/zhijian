extends SceneTree
## Run in an isolated project with a real renderer. Writes only review captures to /tmp.

func _init() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	DirAccess.make_dir_recursive_absolute("/tmp/paper-creation-feedback/frames")
	for viewport_size in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = viewport_size
		var game = load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist = false
		game.onboarding.visible = false
		root.add_child(game)
		await process_frame
		game.set_physics_process(false)
		game.player.freeze = true
		game.feedback.set_process(false)
		game.feedback.audio_enabled = viewport_size == Vector2i(1280, 720)
		game.camera_x = game.player.position.x + 2.0
		game.toolbar._layout()
		game.touch_controls._layout()
		var size := Vector2(1.5, 1.8) if viewport_size.x > 600 else Vector2(0.8, 1.1)
		var origin: Vector2 = game.player.position + Vector2(2.0, 1.25)
		game.draft = [{"points": [origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y), origin]}]
		game.generate()
		if game.feedback.audio_enabled:
			assert(game.feedback.voices.any(func(voice: AudioStreamPlayer) -> bool: return voice.playing), "creation starts a real audio voice")
		# Every frame comes from the real successful generation above.
		if viewport_size == Vector2i(1280, 720):
			for frame in range(60):
				game.feedback.step(1.0 / 24.0)
				await capture("/tmp/paper-creation-feedback/frames/%03d.png" % frame)
		else:
			game.feedback.step(0.20)
		await capture("/tmp/paper-creation-feedback/creation-%dx%d.png" % [viewport_size.x, viewport_size.y])
		if viewport_size == Vector2i(1280, 720):
			game.feedback.events.clear()
			game.feedback.emit_event("create", origin + size * 0.5, "CREATED!")
			game.feedback.step(0.18)
			await capture("/tmp/paper-creation-feedback/creation-hero.png")
			game.feedback.events.clear()
			game.equipped_weapon = DrawingRules.weapon([{"points": [Vector2.ZERO, Vector2(2, 0)]}])
			game.combat.targets = [{"position": game.player.position + Vector2(1, 0.06), "health": 1.0, "flash": 0.0, "respawn": 0.0}]
			game.combat.attack(Vector2.RIGHT)
			game.feedback.step(0.08)
			await capture("/tmp/paper-creation-feedback/combat-hero.png")
		game.queue_free()
		await process_frame
	print("CREATION FEEDBACK VISUAL COMPLETE")
	quit()
