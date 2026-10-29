extends SceneTree
var game
func _init()->void:call_deferred("run")
func capture(label:String,x:float,ppu:float=68.0,root_y:float=-999.0)->void:
	game.player.freeze=false
	game.player.reset_movement()
	game.player.position=game.medieval_world.safe_spawn_position(x) if root_y==-999.0 else Vector2(x,root_y)
	game.player.linear_velocity=Vector2.ZERO
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	for i in 30:
		game._physics_process(1.0/60)
		await physics_frame
	game.player.freeze=true
	game.PIXELS_PER_UNIT=ppu
	game.camera_x=x
	game.camera_y=game.camera_target_y()
	game.flip_timer=0
	game.last_page=int(floor(x/20))
	var nearest:=0
	for i in MedievalWorld.SECTIONS.size():
		if absf(float(MedievalWorld.SECTIONS[i].x)-x)<absf(float(MedievalWorld.SECTIONS[nearest].x)-x):nearest=i
	game.map_controls.regions.select(nearest)
	game.set_physics_process(true)
	for i in 5:
		# Capture normal runtime: controller, rigid bodies and visuals all tick.
		await physics_frame
		game.canvas_node.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	var folder:="/tmp/paper-medieval-product"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
	var people:Array=[]
	for entity in game.medieval_world.entities:
		if not entity.is_person() or entity.kind in ["king","queen","driver"]:continue
		var visual=entity.person_visual
		if not is_instance_valid(visual) or visual.position.x < -100 or visual.position.x > 1540:continue
		var feet:Array=[]
		for leg in ["FrontLeg","BackLeg"]:
			var foot=visual.get_node("Skeleton/Hips/"+leg+"/Shin/Foot")
			var screen:Vector2=foot.to_global(Vector2(2.4,4.25))
			var point:Vector2=game.screen_to_world(screen)
			feet.append({"leg":leg,"screen":[screen.x,screen.y],"world":[point.x,point.y],"road_y":game.medieval_world.travel_height(point.x),"gap":point.y-game.medieval_world.travel_height(point.x)})
		people.append({"id":entity.entity_id,"body":[entity.position.x,entity.position.y],"velocity":[entity.linear_velocity.x,entity.linear_velocity.y],"visual_rotation":visual.rotation,"visual_position":[visual.position.x,visual.position.y],"feet":feet})
	var diagnostics=FileAccess.open(folder.path_join(label+"-feet.json"),FileAccess.WRITE)
	diagnostics.store_string(JSON.stringify({"camera":[game.camera_x,game.camera_y],"ppu":ppu,"people":people},"\t"))
	game.set_physics_process(false)
func run()->void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1440,900)
	game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	game.onboarding.dismiss()
	for i in 30:await physics_frame
	game.set_physics_process(false)
	await capture("01-woodland",11)
	await capture("02-village",29)
	await capture("03-market-river",48)
	await capture("04-castle",78,48)
	await capture("05-ridge",96)
	await capture("06-farm",115)
	await capture("07-mill-river",132)
	await capture("08-abbey",153)
	await capture("09-border-camp",171)
	var landing=game.medieval_world.entity_by_id("bridge_stone-100")
	var floor_y:float=-INF
	for edge in landing.world_walk_segments():
		if minf(edge[0].x,edge[1].x)<=134 and maxf(edge[0].x,edge[1].x)>=134:
			floor_y=maxf(floor_y,edge[0].y if absf(edge[1].x-edge[0].x)<.001 else lerpf(edge[0].y,edge[1].y,(134-edge[0].x)/(edge[1].x-edge[0].x)))
	await capture("10-river-lower-stone-route",134,72,floor_y+.34)
	game.queue_free();await process_frame
	print("PRODUCT COMPOSITION: 10 real rendered district / lower-route captures /tmp/paper-medieval-product")
	quit()
