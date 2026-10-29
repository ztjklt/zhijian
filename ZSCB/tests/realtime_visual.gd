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
	root.title = "纸上城堡 · 实时绘画验收"
	for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = viewport_size
		var game = load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist = false
		game.onboarding.visible = false
		root.add_child(game)
		await process_frame
		game.camera_x = -1.5
		game.player.position = Vector2(-3.5, game.GROUND_Y + 0.5)
		game.equipped_weapon = DrawingRules.weapon([{"points": [Vector2(0, 0), Vector2(1.1, 0), Vector2(1.8, 0.20), Vector2(1.1, 0.36), Vector2(0, 0)]}, {"points": [Vector2(0.3, -0.15), Vector2(0.3, 0.48)]}])
		game.aim_world = Vector2(1, game.player.position.y)
		game.combat.set_training(true)
		for item in [{"kind": "wall", "x": 1.5, "width": 1.1, "height": 1.5}, {"kind": "ladder", "x": 3.0, "width": 0.7, "height": 2.4}, {"kind": "platform", "x": 3.7, "width": 3.0, "height": 0.3}]:
			var object: Dictionary = DrawingRules.building([{"points": [Vector2.ZERO, Vector2(item.width, item.height)]}], item.kind)
			object.x = item.x
			object.y = game.GROUND_Y + item.height * 0.5 + (2.4 if item.kind == "platform" else 0)
			game.objects.append(object)
			game.object_nodes.append(game._build_physics_for_object(object))
		game.set_draw_mode(3)
		game.build_kind = "freehand"
		game.draft = [{"points": [Vector2(-1.4, -0.2), Vector2(-0.2, -0.2), Vector2(-0.2, 1.4), Vector2(-1.4, 1.4), Vector2(-1.4, -0.2)]}]
		game.building_wait = -1 # Keep an unfinished outline visible for the layout capture.
		game.touch_controls.force_visible = viewport_size.y < 500 or viewport_size.x < 600
		game.toolbar._layout()
		game.backpack_panel._layout()
		game.touch_controls._layout()
		for frame in range(28): await physics_frame
		await capture("/tmp/paper-realtime-%dx%d.png" % [viewport_size.x, viewport_size.y])
		game.toggle_bag()
		await capture("/tmp/paper-realtime-bag-%dx%d.png" % [viewport_size.x, viewport_size.y])
		game.queue_free()
		await process_frame
	print("REALTIME VISUAL COMPLETE")
	quit()
