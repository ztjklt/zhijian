extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var lobby=load("res://scenes/network_lobby.tscn").instantiate()
	root.add_child(lobby)
	var folder:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
	if folder=="": folder="/tmp/paper-network-ui"
	DirAccess.make_dir_recursive_absolute(folder)
	for dimensions in [Vector2i(1280,800),Vector2i(390,844)]:
		root.size=dimensions
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var file:=folder.path_join("lobby-%dx%d.png"%[dimensions.x,dimensions.y])
		root.get_texture().get_image().save_png(file)
		if lobby.scroll.size.x>dimensions.x or lobby.scroll.size.y>dimensions.y:
			print("FAIL: 联机入口超出窗口"); quit(1); return
	lobby.session.queue_free(); lobby.queue_free()
	await process_frame
	print("NETWORK_LOBBY_VISUAL: PASS")
	quit()
