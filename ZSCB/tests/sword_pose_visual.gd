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
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("/tmp/paper-sword-quality/frames")
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.feedback.audio_enabled = false
	game.feedback.set_process(false)
	game.PIXELS_PER_UNIT = 190
	game.camera_x = 0
	game.player.position = Vector2(-1.7, game.GROUND_Y + 0.30)
	game.pose = "idle"
	game.facing = 1
	game.land_timer = 0
	game.flip_timer = 0
	var opponent = game.combat.natives[0]
	for native in game.combat.natives: native.position.x = 50
	opponent.position = Vector2(1.45, game.GROUND_Y + 0.30)
	opponent.home_x = 1.45
	opponent.velocity = Vector2.ZERO
	opponent.facing = -1
	opponent.state = "wander"
	opponent.weapon_kind = "blade"
	opponent.cooldown = 10
	game.equipped_weapon = opponent.weapon_model.duplicate(true)
	var blade = game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	await capture("/tmp/paper-sword-quality/ready.png")
	game.character_visual.animator.pause()
	for native in game.combat.natives: native.visual.animator.pause()
	var sharpening: ColorRect = game.get_node("VisualQuality/WorldSharpening")
	print("SHARPEN RECT: ", sharpening.get_global_rect())
	sharpening.visible = false
	await capture("/tmp/paper-sword-quality/ready-unsharpened.png")
	sharpening.visible = true
	# Same original model, upright guard, then the actual wrist-driven swing.
	for frame in range(54):
		var progress: float = clampf((float(frame) - 9) / 30.0, 0, 1)
		game.combat.swing = game.combat.SWING_DURATION * (1 - progress) if frame >= 9 and frame < 39 else 0.0
		game.combat.swing_direction = Vector2.RIGHT
		game.combat.recoil = 0
		if frame >= 9 and frame < 39:
			opponent.state = "windup" if progress < 0.22 else "strike" if progress < 0.66 else "recover"
			opponent.action_time = (1 - progress / 0.22) * 0.36 if progress < 0.22 else (1 - (progress - 0.22) / 0.44) * 0.16 if progress < 0.66 else (1 - (progress - 0.66) / 0.34) * 0.30
		else: opponent.state = "wander"
		await capture("/tmp/paper-sword-quality/frames/%03d.png" % frame)
		if frame == 15: await capture("/tmp/paper-sword-quality/windup.png")
		if frame == 23: await capture("/tmp/paper-sword-quality/cut.png")
		if frame == 35: await capture("/tmp/paper-sword-quality/recovery.png")
	game.PIXELS_PER_UNIT = 78
	game.combat.swing = 0
	opponent.state = "wander"
	await capture("/tmp/paper-sword-quality/normal-size.png")
	print("QUALITY VIEWPORT MSAA: ", root.msaa_2d, "; MIPMAPS: ", game.character_visual.get_node("Skeleton/Hips/Torso/Head/Ink").texture.atlas.get_image().has_mipmaps())
	assert(root.msaa_2d == Viewport.MSAA_4X)
	assert(game.get_node("VisualQuality/WorldSharpening").size == Vector2(root.size))
	game.queue_free()
	for frame in range(4): await process_frame
	print("SWORD POSE VISUAL COMPLETE")
	quit()
