extends SceneTree
var failures: Array[String] = []
var count := 0
func check(ok: bool, label: String) -> void:
	count += 1
	if not ok: failures.append(label); push_error("TYPE COMBAT: " + label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game); await process_frame
	game.set_physics_process(false); game.onboarding.dismiss()
	game.player.position = Vector2(0,0)
	game.aim_world = Vector2(10,.4)
	var held = game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	for kind in ["sword","hammer","spear","bow","firearm"]:
		var w := PaperWeaponGrip.practice_sword()
		w.weapon_type = kind
		game.equipped_weapon = w
		game.combat.reset(); game.combat.bow_equipped=false
		game.character_visual._process(0); held._process(0)
		game.combat.attack(Vector2.RIGHT)
		if kind=="bow":
			check(game.combat.bow_charge>0 and game.combat.swing==0,"hand-drawn bow charges instead of swinging")
			if game.combat.bow_charge>0:
				game.combat.step(.43)
				check(game.combat.projectiles.size()==1 and game.combat.projectiles[0].kind=="arrow","custom bow fires a real arrow")
		elif kind=="firearm":
			check(game.combat.swing==0 and game.combat.projectiles.size()==1,"firearm shoots immediately instead of swinging")
			if not game.combat.projectiles.is_empty():
				check(game.combat.projectiles[0].kind=="bullet" and game.combat.projectiles[0].velocity.length()>16,"gun has faster bullets distinct from arrows")
		else:
			check(game.combat.swing>0,kind+" begins a physical attack")
			if kind=="hammer": check(game.combat.motion_index==3 and game.combat.swing>.6,"hammer uses a slower heavy strike")
			if kind=="spear": check(game.combat.motion_index==2,"spear always uses thrust")
		held._process(0)
		check(held.visible and held.weapon.paths==w.paths,kind+" keeps the original drawn model")
	if game.combat.has_method("shoot_bullet"):
		game.combat.reset()
		game.combat.targets=[{"position":Vector2(2,.4),"health":80.0,"flash":0.0,"respawn":0.0}]
		game.combat.shoot_bullet(Vector2(0,.4),Vector2.RIGHT,"player")
		game.combat._step_projectiles(.1)
		check(game.combat.targets[0].health<80,"fast bullet sweeps and damages target between frames")
		game.combat.targets[0].health=80
		game.objects=[{"role":"building","kind":"wall","paths":[{"points":[Vector2(1,-1),Vector2(1,2)],"collision":true}],"x":0.0,"y":0.0,"health":120.0}]
		game.combat.shoot_bullet(Vector2(0,.4),Vector2.RIGHT,"player")
		game.combat._step_projectiles(.1)
		check(game.combat.targets[0].health==80 and game.objects[0].health<120,"wall absorbs bullet before target behind it")
		game.objects=[]
	game.queue_free(); await process_frame
	print("WEAPON TYPE COMBAT TESTS: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
