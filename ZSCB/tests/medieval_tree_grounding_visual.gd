extends SceneTree
var game

func _init() -> void: call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440,900)
	game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	game.onboarding.dismiss()
	await physics_frame
	game.set_physics_process(false)
	game.player.freeze = true
	var folder := OS.get_environment("TREE_CAPTURE_DIR")
	if folder.is_empty(): folder="/tmp/paper-tree-grounding"
	DirAccess.make_dir_recursive_absolute(folder)
	for shot in [["woodland-uphill",6.0,125.0],["woodland-downhill",14.0,125.0],["pine-ridge",94.0,100.0],["orchard-uphill",145.4,125.0]]:
		var x: float = shot[1]
		game.PIXELS_PER_UNIT = shot[2]
		game.camera_x = x
		game.camera_y = game.medieval_world.surface_height(x)-game.GROUND_Y+(640-root.size.y+game._ground_margin())/game.PIXELS_PER_UNIT
		game.player.position = game.medieval_world.safe_spawn_position(x-1.2)
		game.flip_timer = 0
		for i in 4:
			game.canvas_node.queue_redraw()
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(shot[0]+".png"))
	game.queue_free()
	await process_frame
	print("TREE GROUNDING VISUAL: 4 real game captures in ",folder)
	quit()
