extends SceneTree
var failures:Array[String]=[]
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("WEAPON AUDIO: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.onboarding.dismiss()
	for kind in ["sword","hammer","spear","bow","firearm"]:
		var weapon:=PaperWeaponGrip.practice_sword();weapon.weapon_type=kind
		game.equipped_weapon=weapon;game.combat.reset();game.feedback.events.clear()
		game.combat.attack(Vector2.RIGHT)
		var cue:String=("bow_draw" if kind=="bow" else "firearm_shoot" if kind=="firearm" else kind+"_swing")
		check(game.feedback.events.any(func(e):return e.get("audio","")==cue),"actual "+kind+" attack selects its own action sound")
		if kind=="bow":
			for i in 30:game.combat.step(1.0/60)
			check(game.feedback.events.any(func(e):return e.get("audio","")=="bow_shoot"),"bow release has a string sound distinct from musket")
	check(game.feedback.has_method("emit_combat"),"typed feedback available for remote and projectile impacts")
	if game.feedback.has_method("emit_combat"):
		for kind in ["sword","hammer","spear","bow","firearm"]:
			game.feedback.events.clear();game.feedback.emit_combat("hit",game.player.position,kind)
			check(game.feedback.events.back().get("audio","")==kind+"_hit","impact retains "+kind+" regardless of current equipment")
			var bank:Array=game.feedback.sound_banks.get(kind+"_hit",[])
			check(bank.size()>=3 and bank.all(func(s):return s is AudioStreamWAV and s.get_length()>.025),"three playable variants for "+kind+" impact")
	# Real projectile contact must use launch type even after equipping a hammer.
	for ranged in ["bow","firearm"]:
		game.objects=[{"kind":"freehand","x":1.0,"y":2.0,"dynamic":true,"paths":[{"collision":true,"points":[Vector2(-.2,-.6),Vector2(.2,-.6),Vector2(.2,.6),Vector2(-.2,.6),Vector2(-.2,-.6)]}]}]
		game._rebuild_objects();game.combat.projectiles.clear();game.feedback.events.clear()
		if ranged=="bow":game.combat.shoot_arrow(Vector2(0,2),Vector2.RIGHT,"player")
		else:game.combat.shoot_bullet(Vector2(0,2),Vector2.RIGHT,"player")
		game.equipped_weapon=PaperWeaponGrip.practice_sword();game.equipped_weapon.weapon_type="hammer"
		for i in 12:game.combat._step_projectiles(1.0/60)
		check(game.feedback.events.any(func(e):return e.kind=="hit" and e.get("audio","")==ranged+"_hit"),"actual "+ranged+" projectile retains its impact after equipment switch")
	game.queue_free();await process_frame
	print("WEAPON AUDIO: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
