extends SceneTree
## Render-only fixture. Actual transport/cancellation is covered by the full duel clients.
func _initialize() -> void: call_deferred("run")
func capture(path: String) -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK)
func run() -> void:
	var folder:=OS.get_environment("PAPER_BOW_CAPTURE_DIR")
	if folder.is_empty(): folder="/tmp/paper-bow-intent-visual"
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1280,800)
	var game=load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist=false; root.add_child(game)
	game.onboarding.dismiss(); game.combat.set_natives(false)
	game.feedback.audio_enabled=false; game.set_physics_process(false)
	game.player.freeze=true; game.player.position=Vector2(0,game.GROUND_Y+.54);game.camera_x=0
	var session:=PaperNetSession.new(); root.add_child(session)
	session.set_process(false);session.game=game;game.network_session=session
	session.ready_to_play=true;session.player_id="self"
	game.combat.bow_equipped=true;game.aim_world=game.player.position+Vector2(4,1)
	for size in [Vector2i(1280,800),Vector2i(390,844)]:
		root.size=size
		session.combat_intent.reset(game);game.attack();session.tick(.15)
		assert(game.combat.bow_charge>0 and game.combat.projectiles.is_empty())
		await capture(folder+"/charging-%dx%d.png"%[size.x,size.y])
		game.toggle_bag();session.tick(.01)
		assert(game.combat.bow_charge==0)
		await capture(folder+"/cancelled-%dx%d.png"%[size.x,size.y])
		game.toggle_bag()
	game.network_session=null;game.queue_free();session.queue_free();await process_frame
	print("BOW INTENT VISUAL: desktop and narrow charge/cancel captured")
	quit()
