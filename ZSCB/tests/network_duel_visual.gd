extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var room=PaperNetRoom.new()
	room.configure("DUEL24","paper","owner",PaperWorldStore.new("user://duel-visual"),"world")
	root.add_child(room)
	var a:Dictionary=room.join("","甲");var b:Dictionary=room.join("","乙")
	room.ready(a.player_id);room.ready(b.player_id)
	room.command(a.player_id,{"op":"equip","seq":1,"weapon":PaperWeaponGrip.practice_sword()})
	room.command(b.player_id,{"op":"equip","seq":1,"weapon":PaperWeaponGrip.practice_sword()})
	room.set_physics_process(false)
	var session=PaperNetSession.new();root.add_child(session)
	session.player_id=a.player_id;session.epoch=room.epoch;session.code="DUEL24";session.address="ws://127.0.0.1:9080/ws"
	session.apply_snapshot(room.snapshot())
	var game=session.game
	session.round_trip_ms=108
	var folder:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
	if folder=="":folder="/tmp/paper-duel-ui"
	DirAccess.make_dir_recursive_absolute(folder)
	for dimensions in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=dimensions
		for i in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("duel-%dx%d.png"%[dimensions.x,dimensions.y]))
		var screen:=Rect2(Vector2.ZERO,Vector2(dimensions))
		if not screen.encloses(session.hud.get_global_rect()) or not screen.encloses(session.invite_button.get_global_rect()):
			print("FAIL: duel HUD exceeds viewport ",dimensions," hud=",session.hud.get_global_rect()," invite=",session.invite_button.get_global_rect());quit(1);return
		if session.invite_button.get_global_rect().intersects(game.toolbar.bottom.get_global_rect()):
			print("FAIL: invite overlaps drawing controls ",dimensions);quit(1);return
	game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("NETWORK DUEL VISUAL: PASS, four viewport sizes");quit()
