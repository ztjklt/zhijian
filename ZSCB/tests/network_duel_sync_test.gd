extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);print("FAIL DUEL SYNC: ",label)
func run() -> void:
	var room=PaperNetRoom.new()
	room.configure("SYNC01","paper","owner",PaperWorldStore.new("user://duel-sync"),"world")
	root.add_child(room)
	var a:Dictionary=room.join("","甲");var b:Dictionary=room.join("","乙")
	room.ready(a.player_id);room.ready(b.player_id)
	var actor=room.actors[a.player_id]
	var session=PaperNetSession.new();root.add_child(session)
	session.epoch=room.epoch;session.player_id=a.player_id
	session.apply_snapshot(room.snapshot())
	var game=session.game
	var revision:int=room.revision
	room.command(a.player_id,{"op":"equip","seq":1,"weapon":PaperWeaponGrip.practice_sword()})
	check(room.revision==revision,"equipping weapon does not force full world resync")
	var frame:Dictionary=room.frame();frame.tick=1
	session.apply_frame(frame)
	check(not game.equipped_weapon.is_empty(),"new authority equipment appears through incremental frame")
	room.command(a.player_id,{"op":"equip","seq":2,"weapon":{}})
	frame=room.frame();frame.tick=2;session.apply_frame(frame)
	check(game.equipped_weapon.is_empty(),"empty authority equipment actually removes displayed sword")
	var spawned:Dictionary=room.command(a.player_id,{"op":"spawn","seq":3,"object":{"kind":"freehand","x":-3.0,"y":0.0,"paths":[{"points":[Vector2(-.5,0),Vector2(.5,0)],"collision":true}]}})
	check(spawned.ok,"authority creates damage fixture")
	await physics_frame
	session.apply_snapshot(room.snapshot());revision=room.revision
	actor.combat.damage_building(0,20)
	await physics_frame;await physics_frame
	check(room.revision==revision,"health-only building damage does not force full snapshot")
	frame=room.frame();frame.tick=3;session.apply_frame(frame)
	check(game.objects[0].health==100 and not session.syncing,"damage and entity version arrive without pausing controls")
	# The server's real combat event must reach the display once, even in repeated frames.
	actor.combat.invulnerable=0;actor.hit(20,Vector2.RIGHT)
	frame=room.frame();frame.tick=4;session.apply_frame(frame)
	var hurts:Array=game.feedback.events.filter(func(event):return event.kind=="hurt")
	check(hurts.size()==1,"authoritative hurt produces one local hit flash and sound event")
	frame.tick=5;session.apply_frame(frame)
	check(game.feedback.events.filter(func(event):return event.kind=="hurt").size()==1,"repeated network event never plays hit twice")
	# Personal death closes live edits and preserves the in-progress stroke as a draft.
	game.active_stroke={"points":[Vector2(1,2),Vector2(2,3)]}
	actor.combat.health=5;actor.combat.invulnerable=0;actor.hit(20,Vector2.RIGHT)
	frame=room.frame();frame.tick=6;session.apply_frame(frame)
	check(game.active_stroke==null and game.draft.size()==1,"death retains unfinished ink without leaving an active pointer")
	var before:int=game.draft.size()
	game.pointer_down(Vector2(500,300))
	check(game.active_stroke==null and game.draft.size()==before,"dead player cannot begin another drawing operation")
	game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("NETWORK DUEL SYNC: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
