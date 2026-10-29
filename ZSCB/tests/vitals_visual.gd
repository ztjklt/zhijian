extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var output := "/tmp/paper-vitals"
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO
	for size in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size
		var game=load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist=false; game.onboarding.visible=false
		root.add_child(game); await process_frame
		game.set_physics_process(false); game.player.freeze=true
		game.camera_x=game.player.position.x+0.6
		game.combat.natives[0].position=game.player.position+Vector2(1.3,0)
		game.ink.spend(80)
		game.combat.hurt_player(26, Vector2.LEFT)
		game.combat.natives[0].take_hit(24,Vector2.RIGHT)
		game.toolbar._layout()
		for frame in range(5): await process_frame
		assert(Rect2(Vector2.ZERO,Vector2(size)).encloses(game.vitals_hud.get_global_rect()))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/%dx%d.png" % [size.x,size.y])
		game.queue_free(); await process_frame
	print("VITALS VISUAL: four real damage/resource layouts captured"); quit()
