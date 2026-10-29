extends SceneTree
var game
var folder:String
func _initialize()->void:call_deferred("run")
func capture(name:String)->void:
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(folder.path_join(name))==OK)
func run()->void:
	folder=OS.get_environment("PAPER_LAB_CAPTURE_DIR")
	if folder=="":folder="/tmp/paper-weapon-lab-visual"
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.player.position=Vector2(0,0);game.camera_x=0;game.combat.set_natives(false);game.feedback.audio_enabled=false
	var weapon=PaperWeaponGrip.practice_sword();weapon.weapon_type="firearm";game.equipped_weapon=weapon
	assert(game.weapon_lab.start(1.2).ok)
	game.combat.attack(Vector2.RIGHT);game.combat._step_projectiles(.1)
	assert(game.weapon_lab.current.hits==1 and game.weapon_lab.keep().ok)
	weapon=weapon.duplicate(true);weapon.weapon_type="bow";game.equipped_weapon=weapon;game.weapon_lab.select(weapon);game.combat.reset();game.combat.attack(Vector2.RIGHT);game.combat.step(.43)
	assert(game.weapon_lab.current.hits==1)
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size;game.open_weapon_lab()
		await capture("comparison-%dx%d.png"%[size.x,size.y])
		game.weapon_lab_panel.close()
	root.size=Vector2i(1280,800);game.open_weapon_lab();assert(game.refine_weapon());game.weapon_lab_panel.close()
	await capture("copied-ink.png")
	game.queue_free();await process_frame
	print("WEAPON LAB VISUAL: real gun/bow hits, four panels and copied model")
	quit()
