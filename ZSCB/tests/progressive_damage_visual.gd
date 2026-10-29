extends SceneTree
func _init()->void:call_deferred("run")
func shot(path:String)->void:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK)
func run()->void:
	var folder:=OS.get_environment("PAPER_DAMAGE_CAPTURE_DIR")
	if folder.is_empty():folder="/tmp/paper-progressive-damage"
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false);game.onboarding.dismiss()
	game.feedback.audio_enabled=false;game.feedback.set_process(false)
	game.player.position=Vector2(0,game.GROUND_Y+.54);game.camera_x=0
	var center:Vector2=game.player.position+Vector2(1.05,.25)
	game.set_draw_mode(1);game.generator="own"
	game.draft=[{"points":[center+Vector2(-.5,-.55),center+Vector2(.5,-.55),center+Vector2(.5,.55),center+Vector2(-.5,.55),center+Vector2(-.5,-.55)]}]
	game.generate();game.object_nodes.back().freeze=true
	var target:Dictionary=game.objects.back()
	game.equipped_weapon=PaperWeaponGrip.make_weapon([{"points":[Vector2.ZERO,Vector2(0,1.1),Vector2(.06,1.05)]}],Vector2.ZERO)
	game.feedback.events.clear()
	await shot(folder+"/before.png")
	var captured_hit:=false
	for attack in 12:
		if not game.objects.has(target):break
		game.combat.cooldown=0;game.combat.attack(Vector2.RIGHT)
		for i in 26:
			game.combat.step(1.0/60);game.feedback.step(1.0/60)
			if not captured_hit and game.feedback.events.any(func(e):return e.kind=="hit"):
				captured_hit=true
				await shot(folder+"/actual-impact.png")
				game.feedback.step(.06)
				await shot(folder+"/impact-burst.png")
			if not game.objects.has(target):break
		print("ACTUAL ATTACK ",attack+1," health=",target.get("health",0)," cuts=",target.get("damage_cuts",[]).size())
		if attack==0 or attack==2:
			game.feedback.events.clear()
			await shot(folder+"/after-%d.png"%[attack+1])
		if not game.objects.has(target):await shot(folder+"/shattered.png")
	assert(game.objects.is_empty())
	for size in [Vector2i(844,390),Vector2i(390,844)]:
		root.size=size
		game.feedback.events.clear();game.feedback.emit_event("break",game.player.position+Vector2(1,.4));game.feedback.step(.04)
		await shot(folder+"/impact-%dx%d.png"%[size.x,size.y])
	game.queue_free();for i in 4:await process_frame
	print("PROGRESSIVE DAMAGE VISUAL: actual 1 creation, real hand-drawn swings, chips, final shatter, 3 window sizes")
	quit()
