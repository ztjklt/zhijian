extends SceneTree

func _init() -> void: call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("/tmp/paper-weapon-motion/frames")
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.feedback.audio_enabled = false
	game.feedback.set_process(false)
	game.PIXELS_PER_UNIT = 185
	game.camera_x = 0
	game.player.position = Vector2(-1.7, game.GROUND_Y + 0.30)
	game.pose = "idle"
	game.facing = 1
	game.land_timer = 0
	game.flip_timer = 0
	var opponent = game.combat.natives[0]
	for native in game.combat.natives: native.position.x = 50
	opponent.position = Vector2(1.45, game.GROUND_Y + 0.30)
	opponent.velocity = Vector2.ZERO
	opponent.facing = -1
	opponent.weapon_kind = "blade"
	opponent.cooldown = 100
	game.equipped_weapon = opponent.weapon_model.duplicate(true)
	game.equipped_weapon.cooldown = 0.44
	game.combat.reset()
	# Keep the original gray rig as a mirrored motion reference, outside the
	# combat simulation so a duel does not interrupt the four-move showcase.
	var actors: Array = game.combat.natives.duplicate()
	# reset() replaces natives, so select its current gray rig.
	opponent = actors[0]
	for native in actors: native.position.x = 50
	opponent.position = Vector2(1.45, game.GROUND_Y + 0.30)
	opponent.facing = -1
	opponent.weapon_kind = "blade"
	var layer := CanvasLayer.new()
	layer.layer = 3
	game.add_child(layer)
	var label := Label.new()
	label.position = Vector2(180, 135)
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color("536c72"))
	layer.add_child(label)
	game.character_visual.animator.pause()
	for native in actors: native.visual.animator.pause()
	var battle = game.combat
	var seen := {}
	for frame in range(112):
		if frame == 8: battle.attack(Vector2.RIGHT)
		if frame > 8 and battle.motion_index < 3 and battle.swing <= 0.14 and battle.cooldown > 0 and battle.cooldown <= 0.15:
			battle.attack(Vector2.RIGHT)
		battle.natives = []
		battle.step(1.0 / 30)
		battle.natives = actors
		opponent.motion_index = battle.motion_index
		var p: float = 1 - battle.swing / 0.36
		if battle.swing > 0:
			if p < 0.194444:
				opponent.state = "windup"
				opponent.action_time = (battle.swing - 0.29) / 0.07 * 0.36
			elif battle.swing > 0.12:
				opponent.state = "strike"
				opponent.action_time = (battle.swing - 0.12) / 0.17 * 0.16
			else:
				opponent.state = "recover"
				opponent.action_time = battle.swing / 0.12 * 0.30
		else: opponent.state = "wander"
		label.text = "%02d  %s   ·   连续按 R 衔接" % [battle.motion_index + 1, PaperWeaponMotion.NAMES[battle.motion_index]] if frame >= 8 and frame < 78 else "四式近战  ·  原角色与灰色土著共用动作"
		game.character_visual.sample_weapon()
		opponent.visual.sample_weapon()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_png("/tmp/paper-weapon-motion/frames/%03d.png" % frame)
		if battle.swing > 0.13 and battle.swing < 0.19 and not seen.has(battle.motion_index):
			seen[battle.motion_index] = true
			picture.save_png("/tmp/paper-weapon-motion/move-%d.png" % battle.motion_index)
	assert(seen.size() == 4, "all four moves must execute through the real attack input and recovery queue")
	game.queue_free()
	for frame in range(4): await process_frame
	print("WEAPON MOTION VISUAL COMPLETE: four actual attacks, mirrored original rigs")
	quit()
