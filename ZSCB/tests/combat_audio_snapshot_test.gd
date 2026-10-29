extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error("AUDIO SNAPSHOT: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var room:=PaperNetRoom.new();room.configure("LOADS1","paper","audio-load",PaperWorldStore.new("user://audio-load-worlds"),"audio-load");root.add_child(room)
	var owner:Dictionary=room.join("","作者");var guest:Dictionary=room.join("","朋友")
	room.ready(owner.player_id);room.ready(guest.player_id);room.set_physics_process(false)
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch;session.apply_snapshot(room.snapshot())
	var actor=room.actors[guest.player_id];actor.combat.health=1;actor.combat.invulnerable=0;actor.hit(10,Vector2.RIGHT)
	check(room.combat_events.any(func(e):return e.kind=="voice"),"death happened while listener had not received its frame")
	# Short reconnect/resync takes a current snapshot, not a backlog of old sounds.
	session.apply_snapshot(room.snapshot());session.game.feedback.events.clear()
	session._apply_feedback(room.combat_events)
	check(session.game.feedback.events.is_empty(),"snapshot cursor suppresses all historical death and impact sounds")
	room.record_feedback("voice",actor.player.position,"",0,"death_horse")
	session._apply_feedback(room.combat_events)
	check(session.game.feedback.events.size()==1 and session.game.feedback.events[0].get("audio","")=="death_horse","new death after snapshot still plays once")
	# Import changes the shared epoch; previous-world sounds must not cross it.
	var data:Dictionary={"paper":"lined","objects":[],"world":{"id":"paper"}}
	var imported:Dictionary=room.command(owner.player_id,{"op":"import","seq":1,"data":data})
	check(imported.ok,"real owner world import succeeds")
	check(room.combat_events.is_empty(),"new world epoch has no prior-world combat sounds")
	session.epoch=room.epoch;session.apply_snapshot(room.snapshot());session.game.feedback.events.clear();session._apply_feedback(room.frame().events)
	check(session.game.feedback.events.is_empty(),"loading a world remains silent")
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("AUDIO SNAPSHOT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
