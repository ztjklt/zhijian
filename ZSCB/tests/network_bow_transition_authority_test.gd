extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);print("FAIL BOW TRANSITION: ",label)
func run() -> void:
	var room:=PaperNetRoom.new()
	room.configure("BOWTR1","paper","owner",PaperWorldStore.new("user://bow-transitions"),"world")
	root.add_child(room);room.set_physics_process(false)
	var joined:Dictionary=room.join("","甲");room.ready(joined.player_id)
	var actor=room.actors[joined.player_id]
	actor.equipped_weapon=PaperWeaponGrip.practice_sword()
	var session:=PaperNetSession.new();root.add_child(session);session.set_process(false)
	session.player_id=joined.player_id;session.epoch=room.epoch;session.apply_snapshot(room.snapshot())
	var game=session.game;game.set_physics_process(false);session.ready_to_play=true
	# Q->R before either reply is delivered must use the same type on both sides.
	var toggle:=session.send_op("bow")
	var attack:=session.send_op("attack",{"direction":Vector2.RIGHT})
	check(game.combat.is_bow() and game.combat.bow_charge>.4,"local Q then R starts bow before replies")
	var toggled:Dictionary=room.command(joined.player_id,{"op":"bow","seq":toggle})
	var started:Dictionary=room.command(joined.player_id,{"op":"attack","seq":attack,"direction":Vector2.RIGHT})
	check(actor.combat.is_bow() and actor.combat.bow_charge>.4,"authority receives the same ordered bow attack")
	check(started.get("attack_started",false),"authority distinguishes a real charge from an ignored request")
	session._result(toggled.merged({"seq":toggle}));session._result(started.merged({"seq":attack}))
	var ink:float=actor.ink.amount
	var blocked:=session.send_op("input",{"blocked":true})
	room.command(joined.player_id,{"op":"input","seq":blocked,"blocked":true})
	actor.simulate(.45);session.tick(.45)
	check(actor.combat.projectiles.is_empty() and actor.ink.amount==ink,"authority cancellation creates no arrow and spends no ink")
	room.command(joined.player_id,{"op":"input","seq":blocked+1,"blocked":false})
	# Inherit a real firearm cooldown. Neither side may restart it by switching.
	actor.combat.bow_equipped=false;game.combat.bow_equipped=false
	actor.combat.cooldown=0;game.combat.recoil=0;session.combat_intent.reset(game)
	var firearm:=PaperWeaponGrip.practice_sword();firearm.weapon_type="firearm"
	actor.equipped_weapon=firearm.duplicate(true);game.equipped_weapon=firearm.duplicate(true)
	var shot:=session.send_op("attack",{"direction":Vector2.RIGHT})
	room.command(joined.player_id,{"op":"attack","seq":shot,"direction":Vector2.RIGHT})
	actor.equipped_weapon.weapon_type="bow";game.equipped_weapon.weapon_type="bow"
	actor.simulate(.1);session.tick(.1)
	var early:=session.send_op("attack",{"direction":Vector2.RIGHT})
	var ignored:Dictionary=room.command(joined.player_id,{"op":"attack","seq":early,"direction":Vector2.RIGHT})
	check(ignored.ok and ignored.get("attack_started",true)==false,"cooldown early-return is acknowledged without claiming an attack started")
	check(actor.combat.bow_charge==0 and game.combat.bow_charge==0,"cooling firearm-to-bow transition has no fake charge")
	actor.simulate(.66);session.tick(.66)
	var next:=session.send_op("attack",{"direction":Vector2.RIGHT})
	var accepted:Dictionary=room.command(joined.player_id,{"op":"attack","seq":next,"direction":Vector2.RIGHT})
	check(accepted.get("attack_started",false) and actor.combat.bow_charge>.4 and game.combat.bow_charge>.4,"both sides start the next bow after inherited cooldown expires")
	game.network_session=null;game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("NETWORK BOW TRANSITIONS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
