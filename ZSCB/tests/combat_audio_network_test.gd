extends SceneTree
var count:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("AUDIO NET: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var room:=PaperNetRoom.new();room.configure("AUDIO1","paper","audio-owner",PaperWorldStore.new("user://audio-worlds"),"audio");root.add_child(room)
	var owner:Dictionary=room.join("","主人");room.ready(owner.player_id);room.set_physics_process(false)
	var actor=room.actors[owner.player_id];actor.combat.health=1;actor.combat.invulnerable=0
	actor.hit(10,Vector2.RIGHT);actor.hit(10,Vector2.RIGHT)
	check(room.combat_events.filter(func(e):return e.kind=="voice").size()==1,"authority emits death cry only on alive-to-dead transition")
	check(actor.feedback.has_method("emit_combat"),"authority supports explicit weapon sound")
	if actor.feedback.has_method("emit_combat"):
		actor.feedback.emit_combat("hit",actor.player.position,"hammer")
		check(room.combat_events.back().get("audio","")=="hammer_hit","authority retains attacker sound independently of listener equipment")
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch;session.apply_snapshot(room.snapshot())
	session.game.equipped_weapon=PaperWeaponGrip.practice_sword();session.game.feedback.events.clear();session.last_event=0
	session._apply_feedback(room.combat_events)
	var before:int=session.game.feedback.events.size()
	session._apply_feedback(room.combat_events)
	check(session.game.feedback.events.size()==before,"repeated network events never replay audio")
	check(session.game.feedback.events.any(func(e):return e.kind=="voice" and e.get("audio","")=="death_human_low"),"listener receives actual death cry")
	if actor.feedback.has_method("emit_combat"):
		check(session.game.feedback.events.any(func(e):return e.get("audio","")=="hammer_hit"),"client renders remote hammer rather than its sword")
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("AUDIO NET: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
