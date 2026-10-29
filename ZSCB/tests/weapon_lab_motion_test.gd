extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL LAB MOTION: ",label)
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.player.position=Vector2.ZERO;game.combat.set_natives(false)
	var held=game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	for kind in ["sword","hammer","spear","bow","firearm"]:
		game.combat.reset();game.combat.bow_equipped=false;game.facing=1
		var weapon=PaperWeaponGrip.practice_sword();weapon.weapon_type=kind;game.equipped_weapon=weapon
		check(game.weapon_lab.start(1.2).ok,"actual target available for "+kind)
		game.weapon_lab.reset()
		game.character_visual._process(0);held._process(0);game.aim_world=game.weapon_lab.position
		game.attack()
		for i in 75:
			game.character_visual._process(1.0/60);held._process(1.0/60);game.combat.step(1.0/60)
		print("LAB MOTION ",kind," hits=",game.weapon_lab.current.hits," last=",game.weapon_lab.current.last)
		check(game.weapon_lab.current.hits==1,kind+" real rig/projectile records exactly one actual attack")
		check(game.weapon_lab.current.last>=5 and game.weapon_lab.current.last<=40,kind+" result is the bounded combat damage")
	game.queue_free();await process_frame
	print("WEAPON LAB MOTION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
