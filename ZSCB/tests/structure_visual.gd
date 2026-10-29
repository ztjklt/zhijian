extends "res://tests/structure_links_test.gd"
var capture_folder:String
func capture(name:String)->void:
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(capture_folder.path_join(name))==OK)
func run()->void:
	capture_folder=OS.get_environment("PAPER_STRUCTURE_CAPTURE_DIR")
	if capture_folder=="":capture_folder="/tmp/paper-structure-visual"
	DirAccess.make_dir_recursive_absolute(capture_folder)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);game.onboarding.visible=false
	game.set_physics_process(false);game.player.freeze=true;game.feedback.audio_enabled=false
	game.player.position=Vector2(-2,-2.26);game.camera_x=0
	block("support",Vector2(0,-.4),[Vector2(-.2,-1.9),Vector2(.2,-1.9),Vector2(.2,.2),Vector2(-.2,.2),Vector2(-.2,-1.9)],false)
	var beam=block("beam",Vector2(1.1,-.4),[Vector2(-1,-.06),Vector2(1,-.06),Vector2(1,.06),Vector2(-1,.06),Vector2(-1,-.06)])
	assert(game.structure_links.create("support","beam",Vector2(.2,-.4),"fixed").ok)
	game.set_draw_mode(4);game.set_connection_tool("fixed")
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size
		game.touch_controls.force_visible=size.x<900
		await capture("fixed-%dx%d.png"%[size.x,size.y])
	root.size=Vector2i(1280,800)
	game.structure_links.remove(game.structure_links.records[0].id)
	assert(game.structure_links.create("support","beam",Vector2(.2,-.4),"hinge").ok)
	game.set_connection_tool("hinge")
	await frames(32);game.sync_objects()
	assert(absf(beam.rotation)>.25)
	await capture("hinge-in-motion.png")
	game.queue_free();await process_frame
	print("STRUCTURE VISUAL: four sizes and real hinge motion")
	quit()
