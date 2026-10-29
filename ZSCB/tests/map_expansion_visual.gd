extends SceneTree

func _init() -> void: call_deferred("run")

func capture(game, at: Vector2, name: String) -> void:
	game.knowledge_world.checkpoint = at
	game.knowledge_world.respawn()
	game.player.freeze = true
	game.set_physics_process(false)
	game.camera_x = at.x
	game.camera_y = game.camera_target_y()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "/tmp/paper-map-expansion"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.combat.set_natives(false)
	await capture(game, Vector2(4,14.29), "01-textbook-sky")
	game.knowledge_world.toggle_overview()
	await capture(game, Vector2(40,10), "02-textbook-overview")
	game.knowledge_world.toggle_overview()
	var old = game.knowledge_world
	game.remove_child(old)
	old.queue_free()
	game.world_kind = "nature-v1"
	game.knowledge_world = load("res://scripts/nature_world.gd").new()
	game.knowledge_world.game = game
	game.add_child(game.knowledge_world)
	await capture(game, Vector2(20,6.49), "03-nature-woodland")
	await capture(game, Vector2(35,6.29), "04-nature-mountain")
	await capture(game, Vector2(79,20.29), "05-nature-canopy")
	game.knowledge_world.toggle_overview()
	await capture(game, Vector2(79,20.29), "06-nature-overview")
	game.knowledge_world.toggle_overview()
	for size in [Vector2i(844,390),Vector2i(390,844)]:
		root.size = size
		game.toolbar._layout()
		game.touch_controls.force_visible = true
		game.touch_controls._layout()
		await process_frame
		await capture(game, Vector2(35,6.29), "07-nature-%dx%d" % [size.x,size.y])
	game.queue_free()
	for i in 3: await process_frame
	print("MAP EXPANSION VISUAL COMPLETE /tmp/paper-map-expansion")
	quit()
