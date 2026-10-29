extends SceneTree
var capture_game: Node2D

func _init() -> void: call_deferred("run")
func capture(name: String) -> void:
	for i in 5:
		await process_frame
		# Teleport captures inspect settled geometry without the page-turn overlay.
		if is_instance_valid(capture_game):
			capture_game.flip_timer=0
			capture_game.canvas_node.queue_redraw()
	await RenderingServer.frame_post_draw
	var folder := "/tmp/paper-fusion-review"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func frame_at(game,x: float,ppu: float=60.0) -> void:
	game.PIXELS_PER_UNIT = ppu
	game.player.freeze=false
	game.player.linear_velocity=Vector2.ZERO
	game.player.position = game.medieval_world.safe_spawn_position(x)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	# Let the actual hero collider reach its support before freezing the photo.
	for i in 30: await physics_frame
	game.player.freeze=true
	game.camera_x = x
	game.camera_y = game.camera_target_y()
	game.last_page = int(floor(game.player.position.x/20))
	game.flip_timer = 0
	var closest := 0
	var distance := INF
	for i in MedievalWorld.SECTIONS.size():
		var next_distance := absf(float(MedievalWorld.SECTIONS[i].x)-x)
		if next_distance < distance: closest=i; distance=next_distance
	game.map_controls.regions.select(closest)
	game.canvas_node.queue_redraw()
func run() -> void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1440,900)
	var menu=load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await capture("01-fused-start-menu")
	menu.queue_free()
	await process_frame
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	capture_game=game
	root.add_child(game)
	game.onboarding.dismiss()
	for i in 40: await physics_frame
	game.player.freeze=true
	game.experience.try_sword()
	await frame_at(game,16,62)
	await capture("02-woodland-hills")
	await frame_at(game,27,68)
	await capture("03-stickman-village")
	await frame_at(game,44,68)
	await capture("04-market-and-stickman-driver")
	await frame_at(game,59,60)
	await capture("05-real-river-and-bridge")
	await frame_at(game,61,34)
	await capture("06-river-to-castle-landscape")
	await frame_at(game,78,45)
	game.set_physics_process(false)
	game.camera_y=6.7
	game.canvas_node.queue_redraw()
	await capture("07-hilltop-castle")
	game.set_physics_process(true)
	var wall=game.medieval_world.entities.filter(func(e): return e.kind=="castle_piece" and e.position.y<4 and e.position.x<72)[0]
	game.medieval_world.damage_entity(wall,40,wall.position+Vector2(-wall.size.x*.5,.6),Vector2(4,2))
	await frame_at(game,wall.position.x+1.5,65)
	await capture("08-damage-on-mountain")
	var person=game.medieval_world.entities.filter(func(e): return e.kind=="villager")[0]
	await frame_at(game,person.position.x+1.4,108)
	await capture("09-original-hero-and-villager")
	game.medieval_world.damage_entity(person,5,person.position+Vector2(0,.5),Vector2(3,2.4))
	await capture("10-stickman-knockup")
	game.medieval_world.damage_entity(person,100,person.position,Vector2(2,2))
	for i in 65: await physics_frame
	await frame_at(game,person.position.x+1.3,108)
	await capture("11-stickman-defeated")
	await frame_at(game,94,62)
	await capture("12-dragon-ridge")
	# Capture the same user-facing 2/confirm flow as the giant-brick regression.
	game.set_physics_process(false)
	await frame_at(game,78,33)
	game.camera_y=6.7
	var roof=null
	var roof_top := -INF
	for part in game.medieval_world.entities:
		if part.kind != "castle_piece": continue
		for polygon in part.world_polygons():
			for point in polygon:
				if point.y>roof_top: roof_top=point.y;roof=part
	var balcony: Dictionary = MedievalCastleLayout.role_positions()[0]
	game.player.position=Vector2(balcony.x+0.8,balcony.y+0.56)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	var center := Vector2(roof.position.x,roof_top+4)
	game.set_draw_mode(3)
	game.build_kind="freehand"
	game.draft=[{"points":[center+Vector2(-2.4,-0.65),center+Vector2(2.4,-0.65),center+Vector2(2.4,0.65),center+Vector2(-2.4,0.65),center+Vector2(-2.4,-0.65)]}]
	game.generate()
	game.canvas_node.queue_redraw()
	await capture("15-player-drawn-giant-brick")
	for i in 135:
		game.medieval_world.step(1.0/60)
		await physics_frame
	game.sync_objects()
	game.canvas_node.queue_redraw()
	await capture("16-giant-brick-roof-damage")
	game.set_physics_process(true)
	root.size=Vector2i(390,844)
	game.touch_controls.force_visible=true
	game.toolbar._layout()
	game.touch_controls._layout()
	await frame_at(game,59,43)
	await capture("13-river-narrow")
	game.queue_free()
	await process_frame
	menu=load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await capture("14-fused-start-narrow")
	menu.queue_free()
	await process_frame
	print("FUSION VISUAL CAPTURES COMPLETE")
	quit()
