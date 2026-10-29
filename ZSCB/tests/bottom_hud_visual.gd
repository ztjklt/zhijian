extends SceneTree

const OUT := "/tmp/paper-bottom-hud"
var captures: Array[Dictionary] = []

func _init() -> void: call_deferred("run")

func shot(game, name: String, dimensions: Vector2i) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT + "/%s-%dx%d.png" % [name, dimensions.x, dimensions.y]
	root.get_texture().get_image().save_png(path)
	var rect: Rect2 = game.toolbar.bottom.get_global_rect()
	if rect.size.y / game.toolbar.scale.y > 108.0:
		push_error("BOTTOM HUD VISUAL: initial/resize status wrap left an oversized invisible wrapper: " + str(rect))
	captures.append({"name": name, "size": [dimensions.x, dimensions.y], "path": path, "bottom": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "logical_height": rect.size.y / game.toolbar.scale.y})

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.feedback.audio_enabled = false
	game.onboarding.visible = false
	for i in range(12): await physics_frame
	game.player.freeze = true
	game.set_physics_process(false)
	for dimensions in [Vector2i(1440,900), Vector2i(3840,2160), Vector2i(844,390), Vector2i(390,844)]:
		root.min_size = dimensions
		root.size = dimensions
		game.touch_controls.force_visible = dimensions.x < 900
		game.touch_controls._layout()
		for i in range(6): await process_frame
		game.camera_y = game.camera_target_y()
		game.activate_draw_mode(1)
		game.draft = [{"points": [game.player.position + Vector2(1, 2), game.player.position + Vector2(2, 2)]}]
		game.mode_drafts[1] = game.draft
		await shot(game, "free", dimensions)
		game.activate_draw_mode(3)
		game.draft = [{"points": [game.player.position + Vector2(1, 2), game.player.position + Vector2(2, 2)]}]
		game.mode_drafts[3] = game.draft
		await shot(game, "building", dimensions)
		game.activate_draw_mode(2)
		game.draft = [{"points": [game.player.position + Vector2(1, 2), game.player.position + Vector2(2, 2)]}]
		game.mode_drafts[2] = game.draft
		game.selecting_weapon_grip = true
		game.selected_weapon_grip = game.draft[0].points[0]
		game.toolbar.last_state = ""
		game.toolbar.update_buttons()
		await shot(game, "weapon-grip", dimensions)
		game.selecting_weapon_grip = false
	var file := FileAccess.open(OUT + "/bounds.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(captures, "\t"))
	file.close()
	game.queue_free()
	for i in range(4): await process_frame
	print("BOTTOM HUD VISUAL: actual renderer, ", captures.size(), " captures; ", OUT)
	quit()
