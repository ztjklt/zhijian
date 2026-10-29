extends "res://tests/first_work_test.gd"
var folder:String
func capture(label:String)->void:
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size
		for i in 8:await process_frame
		game.sync_objects();await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(folder.path_join("%s-%dx%d.png"%[label,size.x,size.y]))==OK)
func run()->void:
	folder=OS.get_environment("PAPER_FIRST_WORK_CAPTURE_DIR")
	if folder=="":folder="/tmp/paper-first-work-visual"
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.player.freeze=true;game.combat.set_natives(false);game.feedback.audio_enabled=false;game.first_work.start()
	await capture("draw")
	root.size=Vector2i(1280,800)
	for i in 6:await process_frame
	draw_piece(game.player.position+Vector2(2,1.2));game.first_work.action()
	assert(game.first_work.stage==2)
	await capture("use")
	root.size=Vector2i(1280,800)
	for i in 6:await process_frame
	game.set_draw_mode(4);var body=game.first_work.target();var at:=Vector2(body.data.x,body.data.y)
	game.pointer_down(game.world_to_screen(at));game.pointer_move(game.world_to_screen(at+Vector2(.4,0)));game.pointer_up(game.world_to_screen(at+Vector2(.4,0)))
	assert(game.first_work.stage==3)
	game.first_work.action();assert(game.first_work.stage==4)
	assert(SaveStore.load_game("medieval-v1").error=="")
	await capture("saved")
	game.queue_free();await process_frame
	print("FIRST WORK VISUAL: real drawing, generated body, actual drag, real saved/readback;3 stages x4 sizes")
	quit()
