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
	DirAccess.make_dir_recursive_absolute("/tmp/paper-native-combat/frames")
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	for frame in range(25): await physics_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.feedback.set_process(false)
	game.player.position = Vector2(-2.5, game.GROUND_Y + 0.30)
	game.camera_x = 0
	game.pose = "idle"
	game.facing = 1
	game.land_timer = 0
	game.equipped_weapon = PaperWeaponGrip.make_weapon([{"points": [Vector2.ZERO, Vector2(0, 0.2), Vector2(0.8, 1.05), Vector2(1.0, 1.08), Vector2(0.9, 0.85), Vector2(0, 0.2)]}, {"points": [Vector2(-0.12, 0.20), Vector2(0.18, 0.06)]}], Vector2.ZERO)
	var battle = game.combat
	for i in battle.natives.size():
		var native = battle.natives[i]
		native.position = Vector2([1.5, 4.3, -5.0, 7.0, -8.0, 9.0][i], game.GROUND_Y + 0.23)
		native.home_x = native.position.x
		native.gait = i * 1.7
		native.velocity.x = -1.2
	await capture("/tmp/paper-native-combat/roaming.png")
	battle.toggle_bow()
	game.aim_world = Vector2(4.0, game.player.position.y + 0.15)
	battle.bow_direction = Vector2.RIGHT
	battle.bow_charge = 0.10
	await capture("/tmp/paper-native-combat/bow-draw.png")
	battle.bow_charge = 0
	battle.shoot_arrow(game.player.position + Vector2(1.0, 0.2), Vector2.RIGHT, "player")
	battle.shoot_arrow(game.player.position + Vector2(3.0, 0.2), Vector2.LEFT, "native")
	battle.shot_recoil = 0.17
	await capture("/tmp/paper-native-combat/arrows.png")
	battle.projectiles.clear()
	battle.bow_equipped = false
	var opponent = battle.natives[0]
	opponent.position = game.player.position + Vector2(1.05, -0.06)
	opponent.facing = -1
	opponent.state = "windup"
	opponent.action_time = 0.13
	battle.cooldown = 0
	battle.recoil = 0
	battle.attack(Vector2.RIGHT)
	for frame in range(14):
		battle.step(1.0 / 60.0)
		if game.feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "clash"): break
	game.feedback.step(0.035)
	await capture("/tmp/paper-native-combat/blade-clash.png")
	# Real frame sequence: approach, bow draw/release, then melee against a native.
	for frame in range(72):
		if frame == 0:
			battle.bow_equipped = true
			battle.cooldown = 0
			battle.recoil = 0
			opponent.position.x = 1.5
			opponent.home_x = 1.5
			battle.attack(Vector2.RIGHT)
		if frame == 30:
			battle.bow_equipped = false
			opponent.position = game.player.position + Vector2(1.05, -0.06)
			opponent.stagger = 0
			opponent.state = "windup"
			opponent.action_time = 0.13
			battle.cooldown = 0
			battle.attack(Vector2.RIGHT)
		battle.step(1.0 / 30.0)
		game.feedback.step(1.0 / 30.0)
		await capture("/tmp/paper-native-combat/frames/%03d.png" % frame)
	for size in [Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = size
		game.touch_controls.force_visible = true
		game.toolbar._layout()
		game.camera_x = game.player.position.x + 0.6
		await capture("/tmp/paper-native-combat/compact-%dx%d.png" % [size.x, size.y])
	for voice in game.feedback.voices: voice.stop()
	game.queue_free()
	for frame in range(4): await process_frame
	print("NATIVE COMBAT VISUAL COMPLETE")
	quit()
