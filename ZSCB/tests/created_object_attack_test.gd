extends SceneTree
var count:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("CREATED ATTACK: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.onboarding.dismiss();game.player.freeze=true
	game.player.position=Vector2(0,game.GROUND_Y+.54)
	var weapon:=PaperWeaponGrip.make_weapon([{"points":[Vector2.ZERO,Vector2(0,1.1),Vector2(.06,1.05)]}],Vector2.ZERO)
	for mode in [1,3,5]:
		game.ink.amount=300;game.set_draw_mode(mode);game.generator="own";game.build_kind="freehand"
		var center:Vector2=game.player.position+Vector2(1.05,.25)
		game.draft=[{"points":[center+Vector2(-.5,-.55),center+Vector2(.5,-.55),center+Vector2(.5,.55),center+Vector2(-.5,.55),center+Vector2(-.5,-.55)]}]
		var before:int=game.objects.size();game.generate()
		check(game.objects.size()==before+1,"actual creation tool "+str(mode)+" generates target")
		if game.objects.size()==before:continue
		var target:Dictionary=game.objects.back()
		game.object_nodes.back().freeze=true
		game.equipped_weapon=weapon.duplicate(true);game.combat.reset()
		game.combat.attack(Vector2.RIGHT)
		for i in 25:game.combat.step(1.0/60)
		check(target.get("health",120)<120,"real drawn weapon damages own creation from tool "+str(mode))
		check(target.get("damage_cuts",[]).size()>0,"actual model sweep leaves progressive chip for tool "+str(mode))
		for attack in 14:
			if not game.objects.has(target):break
			game.combat.cooldown=0;game.combat.attack(Vector2.RIGHT)
			for i in 26:game.combat.step(1.0/60)
		check(not game.objects.has(target),"repeated real attacks eventually break own tool "+str(mode)+" object")
		if game.objects.has(target):
			print("DIAGNOSTIC target=",target," blade_bounds=",PaperBladeSweep.bounds(game.combat.player_paths))
	game.queue_free();await process_frame
	print("CREATED ATTACK: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
