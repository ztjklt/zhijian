extends SceneTree
const OUTPUT := "/Users/jitian/Documents/ChatGPT/纸上城堡/ZSCB/docs/previews/2026-10-25-living-map"
var game
func _init() -> void: call_deferred("run")
func stats(values: Array) -> Dictionary:
	values.sort()
	return {"median_ms":values[values.size()/2],"p95_ms":values[int(values.size()*.95)],"max_ms":values.back()}
func run() -> void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1440,900)
	Engine.max_fps=120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	game.onboarding.dismiss()
	game.combat.set_natives(false)
	var report:={"phase":OS.get_environment("PAPER_LIVING_PROFILE_PHASE"),"viewports":[1440,900],"entities":game.medieval_world.entities.size(),"locations":[]}
	for x in [9.0,30.0,55.0,77.0,113.0,172.0]:
		game.player.position=game.medieval_world.safe_spawn_position(x)
		game.player.linear_velocity=Vector2.ZERO
		PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
		game.camera_x=x
		game.camera_y=game.camera_target_y()
		for i in 12: await process_frame
		var frame: Array=[];var physics:Array=[];var process:Array=[];var draws:Array=[]
		var last:=Time.get_ticks_usec()
		for i in 55:
			await process_frame
			var now:=Time.get_ticks_usec()
			frame.append(float(now-last)/1000.0);last=now
			process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var row:={"x":x,"frame":stats(frame),"process":stats(process),"physics":stats(physics),"draw_calls":draws[draws.size()/2]}
		report.locations.append(row)
		print("PROFILE ",JSON.stringify(row))
		if report.phase=="final":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT.path_join("final-"+str(int(x))+".png"))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var file:=FileAccess.open(OUTPUT.path_join(str(report.phase)+"-profile.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	game.queue_free();await process_frame
	print("LIVING MAP PROFILE COMPLETE")
	quit()
