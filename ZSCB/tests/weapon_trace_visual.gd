extends SceneTree
func _init()->void:call_deferred("run")
func capture(path:String)->void:
	for i in 2: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK)
func run()->void:
	var folder:=OS.get_environment("PAPER_TRACE_CAPTURE_DIR")
	if folder.is_empty():folder="/tmp/paper-weapon-trace"
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false);game.onboarding.dismiss()
	game.feedback.audio_enabled=false;game.feedback.set_process(false)
	game.player.position=Vector2(0,game.GROUND_Y+.54);game.camera_x=0
	var held=game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	held.set_process(false)
	for kind in ["sword","hammer","spear"]:
		var strokes:Array=[{"points":[Vector2(0,0),Vector2(-.08,1.3),Vector2(.20,1.55),Vector2(.38,1.3),Vector2(.07,.45)]},{"points":[Vector2(-.25,.3),Vector2(.28,.3)]}]
		game.equipped_weapon=PaperWeaponGrip.make_weapon(strokes,Vector2(0,.1));game.equipped_weapon.weapon_type=kind
		for face in [1,-1]:
			game.combat.reset();game.facing=face;game.combat.attack(Vector2(face,0))
			game.combat.motion_index=3 if kind=="hammer" else 2 if kind=="spear" else 1
			for frame in range(7):
				game.combat.swing=PaperWeaponTypes.duration(game.equipped_weapon)*(.72-float(frame)*.04)
				game.character_visual.sample_weapon();held._process(1.0/90)
			assert(not held.trace.snapshots.is_empty(),"visible actual rig supplies contour echoes")
			game.feedback.events.clear()
			await capture(folder+"/%s-%d.png"%[kind,face])
	# Contact-point detail is separate from the model's extent.
	game.feedback.emit_event("hit",game.player.position+Vector2(.9,.65))
	game.feedback.step(.055)
	await capture(folder+"/contact.png")
	# Render cost observation: a complex original model is always retained.
	var points:Array=[]
	for i in 1200:points.append(Vector2(sin(i*.2)*.12,float(i)/1200*2.5))
	game.equipped_weapon={"paths":[{"points":points}],"grip":Vector2.ZERO,"reach":2.5,"cooldown":.4}
	game.combat.reset();game.combat.attack(Vector2.RIGHT);game.combat.swing=.2
	game.character_visual.sample_weapon()
	var start:=Time.get_ticks_usec()
	for i in 60:held._process(1.0/120)
	print("TRACE CPU 1200 vertices: mean_ms=",float(Time.get_ticks_usec()-start)/60000.0)
	await capture(folder+"/complex.png")
	game.queue_free();for i in 4:await process_frame
	print("WEAPON TRACE VISUAL: 3 types x 2 directions, contact, complex model; actual Metal rendering")
	quit()
