extends SceneTree
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: push_error(label); quit(1)
func _init() -> void: call_deferred("run")
func run() -> void:
	var room = PaperNetRoom.new()
	room.configure("INK001", "paper", "owner", PaperWorldStore.new("user://ink-test"), "world")
	root.add_child(room)
	var joined: Dictionary = room.join("", "甲")
	room.ready(joined.player_id)
	var actor = room.actors[joined.player_id]
	if not "ink" in actor:
		print("FAIL: authority has no ink reserve"); room.queue_free(); await process_frame; quit(1); return
	var obj := {"kind":"freehand", "x":-2.0, "y":1.0, "paths":[{"points":[Vector2.ZERO,Vector2(1,0)],"collision":true}]}
	var request := {"op":"spawn","seq":1,"object":obj,"cost":0,"ink":999999}
	var result: Dictionary = room.command(joined.player_id, request)
	check(result.ok and actor.ink.amount == 294, "authority prices geometry, ignoring client price and balance")
	room.command(joined.player_id, request)
	check(actor.ink.amount == 294 and room.world.objects.size()==1, "duplicate command never charges twice")
	actor.ink.amount = 0
	result = room.command(joined.player_id,{"op":"spawn","seq":2,"object":obj})
	check(not result.ok and room.world.objects.size()==1 and actor.ink.amount==0, "insufficient ink is atomic")
	actor.ink.step(3); check(actor.ink.amount==25, "authority reserve recovers after delay")
	actor.combat.health=5; actor.combat.invulnerable=0
	actor.hit(40,Vector2.RIGHT)
	check(actor.combat.health==0 and room.combat_events.filter(func(e):return e.kind=="hurt").back().amount==5 and room.combat_events.back().kind=="voice" and room.combat_events.back().amount==0, "lethal hit reports actual HP lost independently of death voice")
	check(actor.state().ink==25 and actor.state().ink_wait==0, "reserve is replicated with actor state")
	actor.simulate(1)
	check(actor.ink.amount==50 and actor.dead_time>0, "death naturally recovers without refill")
	room.disconnect_player(joined.player_id)
	actor.simulate(10)
	check(actor.ink.amount==50, "disconnected reserve does not regenerate")
	var again: Dictionary = room.join(joined.token, "甲")
	check(again.player_id==joined.player_id and room.actors[again.player_id].ink.amount==50, "credential reconnect does not refill reserve")
	room.ready(joined.player_id); actor.dead_time=0; actor.set_active(true)
	var sword := PaperWeaponGrip.practice_sword()
	result=room.command(joined.player_id,{"op":"equip","seq":3,"weapon":sword})
	var after: float=actor.ink.amount
	check(result.ok and after<50, "weapon materialization has authority cost")
	room.command(joined.player_id,{"op":"equip","seq":4,"weapon":sword})
	check(actor.ink.amount==after, "same normalized weapon is not charged again")
	actor.ink.amount=0
	var old: Dictionary=actor.equipped_weapon.duplicate(true)
	result=room.command(joined.player_id,{"op":"equip","seq":5,"weapon":PaperWeaponGrip.make_weapon([{"points":[Vector2.ZERO,Vector2(0,2)]}],Vector2.ZERO)})
	check(not result.ok and actor.equipped_weapon==old, "failed forge keeps equipped weapon")
	room.queue_free(); await process_frame
	print("NETWORK INK: ", checks, " checks passed"); quit()
