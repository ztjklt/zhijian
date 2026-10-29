extends "res://tests/network_duel_bot.gd"
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL DUEL AIM: ",label)
func run()->void:
	var room:=PaperNetRoom.new()
	room.configure("AIMBOT","paper","owner",PaperWorldStore.new("user://duel-aim"),"world")
	root.add_child(room);room.set_physics_process(false)
	var owner:Dictionary=room.join("","甲");var guest:Dictionary=room.join("","乙")
	room.ready(owner.player_id);room.ready(guest.player_id)
	var shooter=room.actors[owner.player_id];var target=room.actors[guest.player_id]
	session=PaperNetSession.new();root.add_child(session);session.set_process(false)
	var displayed=load("res://scripts/net/remote_actor.gd").new()
	displayed.display_game=room.world;root.add_child(displayed);displayed.set_process(false)
	session.game=shooter;session.remotes={guest.player_id:displayed}
	# The recorded failed run displayed a .96m gap while authority positions
	# were farther apart. Reproduce that small delayed-pose discrepancy;
	# the straight arrow must still hit when aimed at the body centre.
	for side in [-1.0,1.0]:
		shooter.player.position=Vector2(-4,-2.515)
		target.player.position=Vector2(-4+side*1.3,-2.515)
		displayed.player.position=Vector2(-4+side*.96,-2.515)
		target.combat.health=100;target.combat.invulnerable=0
		shooter.combat.reset();shooter.combat.bow_equipped=true
		aim_at_friend();shooter.attack()
		check(shooter.combat.bow_charge>.4,"bot initiates a real bow charge in both directions")
		shooter.combat.step(.43,false)
		check(shooter.combat.projectiles.size()==1,"authority releases exactly one real arrow")
		for frame in 20:room._step_shared_arrows(1.0/120)
		check(target.combat.health==76,"bot aims a real arrow inside the target instead of below its hit circle")
	shooter.combat.reset();target.combat.health=100;target.combat.invulnerable=0
	shooter.combat.bow_equipped=true;shooter.combat.cooldown=.1
	aim_at_friend();shooter.attack();shooter.combat.step(.43,false)
	for frame in 20:room._step_shared_arrows(1.0/120)
	check(target.combat.health==100 and shooter.combat.projectiles.is_empty(),"aim fixture still detects an actually ignored cooldown attack")
	displayed.queue_free();session.game=null;session.remotes.clear();session.queue_free();room.queue_free();await process_frame
	print("NETWORK DUEL AIM: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
