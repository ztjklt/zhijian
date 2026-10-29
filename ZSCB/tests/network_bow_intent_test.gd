extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL BOW INTENT: ",label)
func state(game, extra: Dictionary = {}) -> Dictionary:
	var result := {"id":"self","name":"我","position":game.player.position,"health":100.0,"bow_equipped":true,"bow_charge":.38,"weapon":game.equipped_weapon,"connected":true}
	result.merge(extra,true)
	return result
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.combat.set_natives(false)
	game.set_physics_process(false)
	var session := PaperNetSession.new()
	root.add_child(session)
	session.set_process(false)
	session.game=game; game.network_session=session
	session.player_id="self"; session.epoch="bow-test"; session.ready_to_play=true
	game.combat.bow_equipped=true
	game.aim_world=game.player.position+Vector2(3,0)
	var ink:float=game.ink.amount
	game.attack()
	var first:float=game.combat.bow_charge
	check(first>.4,"own bow visibly starts in the attack frame before any authority reply")
	check(game.combat.projectiles.is_empty() and game.ink.amount==ink,"cosmetic prediction cannot create arrows or spend ink")
	session.tick(.15)
	var advanced:float=game.combat.bow_charge
	check(advanced>.2 and advanced<.3,"own charge advances with local time")
	game.attack()
	check(is_equal_approx(game.combat.bow_charge,advanced),"repeated attack within cooldown cannot restart the charge")
	session._actor(state(game))
	check(is_equal_approx(game.combat.bow_charge,advanced),"stale authority charge cannot rewind the local animation")
	game.toggle_bag(); session.tick(.01)
	check(game.combat.bow_charge==0,"opening blueprints cancels local charge immediately")
	session._actor(state(game))
	check(game.combat.bow_charge==0,"late authority charge cannot revive a cancelled bow while bag is open")
	game.toggle_bag(); session.tick(.8)
	session._actor(state(game))
	check(game.combat.bow_charge==0,"closing bag does not resurrect the old charge")
	game.attack(); var rejected:int=session.seq
	check(game.combat.bow_charge>0,"a new attack starts after cooldown")
	session._result({"op":"attack","seq":rejected,"ok":false,"error":"rejected"})
	check(game.combat.bow_charge==0,"authority rejection clears the matching predicted charge")
	session.tick(.8); game.attack(); session._actor(state(game,{"health":76.0,"recoil":.2}))
	check(game.combat.bow_charge==0,"actual authority damage interrupts local charging")
	game.combat.recoil=0; game.combat.health=100; session.tick(.8); game.attack()
	session.focus_active=false; session.tick(.01)
	check(game.combat.bow_charge==0,"focus loss cancels charge without waiting for server echo")
	session.focus_active=true; session.tick(.8); game.attack(); session.tick(.5)
	check(game.combat.bow_charge==0 and game.combat.projectiles.is_empty() and game.ink.amount==ink,"local charge expires without firing or charging resources")
	session.tick(.8); game.attack(); session._disconnected()
	check(game.combat.bow_charge==0,"disconnect clears cosmetic combat state")
	session.ended=false; session.ready_to_play=true; session.tick(.8); game.attack()
	session._receive({"type":"world_changed","epoch":"new-world"})
	check(game.combat.bow_charge==0,"world changes cannot carry a prior world's charge")
	session.syncing=false; session.ready_to_play=true; session.tick(.8); game.attack()
	session._actor(state(game,{"bow_charge":0,"bow_direction":Vector2.LEFT}))
	check(game.combat.bow_charge>0 and game.combat.bow_direction.x>.9,"pre-attack authority frame cannot erase local pose or aim")
	session._result({"op":"attack","seq":rejected,"ok":false,"error":"old rejection"})
	check(game.combat.bow_charge>0,"rejection for an older attack cannot cancel the new attack")
	session.tick(.5)
	session._actor(state(game,{"bow_charge":0,"bow_direction":Vector2.LEFT}))
	check(game.combat.bow_direction==Vector2.LEFT,"authority aim remains available for ranged recoil after local charge ends")
	session.tick(.8); game.ink.amount=0; game.attack()
	check(game.combat.bow_charge==0,"insufficient authority ink does not present a false charge")
	game.ink.amount=ink; session.tick(.8); game.attack()
	game.equipped_weapon=PaperWeaponGrip.practice_sword(); session.tick(.01)
	check(game.combat.bow_charge==0,"equipment changes end the previous weapon's local pose")
	session.combat_intent.reset(game); game.combat.bow_equipped=false
	var toggle:int=session.send_op("bow")
	check(game.combat.bow_equipped,"Q immediately presents the requested bow before its reply")
	session._actor(state(game,{"bow_equipped":false,"bow_charge":0}))
	check(game.combat.bow_equipped,"pre-toggle authority frame cannot revert pending Q")
	game.attack()
	check(game.combat.bow_charge>.4,"Q then R in the same frame visibly charges the requested bow")
	session._result({"op":"bow","seq":toggle,"ok":true})
	session._actor(state(game,{"bow_equipped":true,"bow_charge":0}))
	session.tick(.8)
	session.send_op("bow"); game.attack()
	check(not game.combat.bow_equipped and game.combat.bow_charge==0,"Q out of bow then R immediately shows no false bow charge")
	session.combat_intent.reset(game); game.combat.bow_equipped=false
	game.equipped_weapon=PaperWeaponGrip.practice_sword()
	game.equipped_weapon.weapon_type="firearm"
	game.attack()
	game.equipped_weapon.weapon_type="bow"
	session.tick(.1); game.attack()
	check(game.combat.bow_charge==0,"switching from a cooling firearm cannot start a false bow windup")
	session.tick(.66); game.attack()
	check(game.combat.bow_charge>.4,"bow starts once the previous firearm's actual cooldown has expired")
	var ignored:int=session.seq
	session._result({"op":"attack","seq":ignored,"ok":true,"attack_started":false})
	check(game.combat.bow_charge==0,"authority's accepted-but-ignored attack result cancels the matching pose")
	session.combat_intent.reset(game);game.combat.bow_equipped=false
	game.equipped_weapon.weapon_type="firearm"
	game.attack();var ignored_firearm:int=session.seq
	session._result({"op":"attack","seq":ignored_firearm,"ok":true,"attack_started":false})
	session.send_op("bow");session.tick(.1);game.attack()
	check(game.combat.bow_charge>.4,"ignored firearm cannot leave a phantom cooldown that hides the next real bow")
	game.network_session=null; game.queue_free(); session.queue_free(); await process_frame
	print("NETWORK BOW INTENT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
