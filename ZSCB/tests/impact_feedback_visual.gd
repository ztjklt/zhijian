extends SceneTree
## Isolated renderer capture of real native/player damage entry points.

func _init() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var destination := "/tmp/paper-impact-feedback"
	DirAccess.make_dir_recursive_absolute(destination)
	root.content_scale_size = Vector2i.ZERO
	for size in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = size
		var game = load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist = false
		game.onboarding.visible = false
		root.add_child(game)
		for frame in range(5): await physics_frame
		game.set_physics_process(false)
		game.player.freeze = true
		game.feedback.set_process(false)
		game.feedback.audio_enabled = size == Vector2i(1280, 720)
		game.player.position = Vector2(-1, game.GROUND_Y + 0.3)
		game.camera_x = 0
		game.facing = 1
		game.equipped_weapon = PaperWeaponGrip.practice_sword()
		game.toolbar._layout()
		for i in game.combat.natives.size():
			var native = game.combat.natives[i]
			native.set_physics_process(false)
			native.position = Vector2(0.7 if i == 0 else 30.0 + i, game.GROUND_Y + 0.3)
		var opponent = game.combat.natives[0]
		for kind in ["hit", "hurt", "break"]:
			game.feedback.events.clear()
			game.combat.effects.clear()
			match kind:
				"hit": opponent.take_hit(18, Vector2.RIGHT)
				"hurt":
					game.combat.invulnerable = 0
					game.combat.hurt_player(15, Vector2.LEFT)
				"break": opponent.take_hit(1000, Vector2.RIGHT)
			assert(game.feedback.events.any(func(event): return event.kind == kind))
			if game.feedback.audio_enabled:
				assert(game.feedback.voices.any(func(voice): return voice.playing and game.feedback.sound_banks[kind].has(voice.stream)))
			game.feedback.step(0.075)
			await capture(destination + "/%s-%dx%d.png" % [kind, size.x, size.y])
		game.queue_free()
		await process_frame
	print("IMPACT FEEDBACK VISUAL: 9 real damage captures; hit/hurt/break audio voices started")
	quit()
