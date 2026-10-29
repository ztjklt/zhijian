extends SceneTree
func _init() -> void: call_deferred("run")
func shot(path: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(path)
	assert(error==OK)
func run() -> void:
	var folder:=OS.get_environment("PAPER_WEAPON_CAPTURE_DIR")
	if folder.is_empty(): folder="/tmp/paper-weapon-types"
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1280,800)
	var game=load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist=false;root.add_child(game)
	game.onboarding.dismiss();game.feedback.audio_enabled=false
	game.set_physics_process(false)
	game.player.position=Vector2(0,game.GROUND_Y+.54);game.camera_x=0
	game.set_draw_mode(2)
	# A nonstandard drawn weapon intentionally stays identical across type choices.
	game.draft=[{"points":[Vector2(-1,0),Vector2(-1,1.5),Vector2(-.6,1.2),Vector2(-.5,.5)]},{"points":[Vector2(-1.3,.3),Vector2(-.6,.3)]}]
	game.generate();game.select_weapon_grip(Vector2(-1,.2));game.generate()
	game.select_weapon_type("firearm")
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size
		await shot(folder+"/wheel-%dx%d.png"%[size.x,size.y])
		assert(is_equal_approx(game.weapon_type_wheel.scale.x,PaperGuiScale.factor(Vector2(size))), "wheel must share HUD scaling")
		for button in game.weapon_type_wheel.buttons:
			assert(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()))
	root.size=Vector2i(1280,800)
	game.generate()
	for kind in ["bow","firearm","hammer","spear"]:
		game.equipped_weapon.weapon_type=kind
		game.aim_world=game.player.position+Vector2(5,1)
		game.combat.reset();game.combat.attack(Vector2(5,1))
		if kind=="hammer" or kind=="spear":game.combat.swing*=.55
		await shot(folder+"/held-"+kind+".png")
	game.queue_free();for i in 4:await process_frame
	print("WEAPON TYPE VISUAL: 4 window sizes and 4 original drawn models")
	quit()
