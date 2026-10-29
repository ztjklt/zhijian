extends "res://tests/mill_bridge_trial_test.gd"
var capture_folder: String
func capture(name: String) -> void:
	for i in 4:await process_frame
	game.camera_y=game.camera_target_y()
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(capture_folder.path_join(name))==OK)
func run() -> void:
	capture_folder=OS.get_environment("PAPER_MILL_CAPTURE_DIR")
	if capture_folder=="":capture_folder="/tmp/paper-mill-visual"
	DirAccess.make_dir_recursive_absolute(capture_folder)
	Engine.physics_ticks_per_second=120;Engine.time_scale=4
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	game.set_physics_process(false);game.player.freeze=true;game.feedback.audio_enabled=false
	game.player.position=Vector2(130.0,3.3);game.camera_x=133.5;game.camera_y=game.camera_target_y()
	var trial=game.medieval_world.bridge_trial
	assert(trial.prepare().ok)
	rectangle(Vector2(133.5,5.5),Vector2(7.8,.06))
	await ticks(75)
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size
		game.camera_x=130.0 if size.x<600 else 133.5
		game.map_controls._process(0)
		await capture("ready-%dx%d.png"%[size.x,size.y])
	root.size=Vector2i(1280,800);game.camera_x=133.5
	assert(trial.start().ok)
	await ticks(100)
	await capture("transporting.png")
	for i in 900:
		await ticks(1)
		if trial.phase!="running":break
	assert(trial.phase=="delivered")
	await capture("delivered.png")
	game.queue_free();await process_frame
	print("MILL BRIDGE VISUAL: four viewports plus real transport/delivery")
	quit()
