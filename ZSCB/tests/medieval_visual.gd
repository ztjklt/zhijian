extends SceneTree

func _init() -> void: call_deferred("run")

func capture(name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := "/tmp/paper-medieval-review"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func pose_camera(game, x: float, zoom: float = 68.0) -> void:
	game.PIXELS_PER_UNIT = zoom
	game.player.position = game.medieval_world.safe_spawn_position(x)
	PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0,game.player.position))
	game.camera_x = x
	game.camera_y = game.camera_target_y()
	game.last_page = int(floor(x / 20.0))
	game.flip_timer = 0
	var section := 0
	for i in MedievalWorld.SECTIONS.size():
		if x >= float(MedievalWorld.SECTIONS[i].x)-3: section = i
	game.map_controls.regions.select(section)
	game.canvas_node.queue_redraw()

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440,900)
	var menu = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await capture("01-start-menu")
	root.size = Vector2i(390,844)
	await capture("02-start-menu-narrow")
	menu.queue_free()
	await process_frame
	root.size = Vector2i(1440,900)
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.onboarding.dismiss()
	for i in 30: await physics_frame
	game.player.freeze = true
	game.experience.try_sword()
	pose_camera(game,27)
	await capture("03-village")
	pose_camera(game,40)
	await capture("04-market-and-wagon")
	pose_camera(game,71,52)
	await capture("05-castle-before")
	var wall = game.medieval_world.entities.filter(func(e): return e.kind == "wall")[0]
	game.medieval_world.damage_entity(wall,45,wall.position+Vector2(-wall.size.x*0.5,0.65),Vector2(4,2))
	await physics_frame
	pose_camera(game,wall.position.x+2,72)
	await capture("06-castle-local-damage")
	var villager = game.medieval_world.entities.filter(func(e): return e.kind == "villager")[0]
	game.medieval_world.damage_entity(villager,100,villager.position+Vector2(0,0.5),Vector2(3,3))
	for i in 60:
		await physics_frame
	pose_camera(game,villager.position.x+1,72)
	await capture("07-villager-defeated")
	pose_camera(game,92,62)
	await capture("08-dragon-flight-a")
	for i in 25:
		await physics_frame
	await capture("09-dragon-flight-b")
	root.size = Vector2i(390,844)
	game.touch_controls.force_visible = true
	game.toolbar._layout()
	game.touch_controls._layout()
	pose_camera(game,27,60)
	await capture("10-village-narrow")
	game.queue_free()
	await process_frame
	print("MEDIEVAL VISUAL CAPTURES COMPLETE")
	quit()
