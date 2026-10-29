extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL MILL NETWORK: ",label)
func run()->void:
	var room:=PaperNetRoom.new();room.configure("MILL01","medieval-v1","owner",PaperWorldStore.new("user://mill-room"),"world");root.add_child(room)
	room.set_physics_process(false)
	var owner:Dictionary=room.join("","甲");var guest:Dictionary=room.join("","乙")
	room.ready(owner.player_id);room.ready(guest.player_id)
	for actor in room.actors.values():
		actor.player.position=Vector2(129,3.3)
		PhysicsServer2D.body_set_state(actor.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,actor.player.global_transform)
	var prepared:Dictionary=room.command(guest.player_id,{"op":"bridge_trial","action":"prepare","seq":1})
	check(prepared.ok,"nearby guest can prepare the shared optional event")
	if prepared.ok:
		var trial=room.world.medieval_world.bridge_trial
		var started:Dictionary=room.command(owner.player_id,{"op":"bridge_trial","action":"start","seq":1})
		check(started.ok and trial.phase=="running","authority starts actual shared cargo")
		var parcel=trial.parcel
		room.command(owner.player_id,{"op":"bridge_trial","action":"start","seq":1})
		check(trial.attempt==1 and trial.parcel==parcel,"duplicate command cannot create or charge a second attempt")
		var invalid:Dictionary=room.command(guest.player_id,{"op":"bridge_trial","action":"delivered","seq":2,"x":137.8,"completed":true})
		check(not invalid.ok and not trial.completed,"client cannot submit a completion or cargo coordinates")
		var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch
		session.apply_snapshot(room.snapshot())
		var replica=session.game.medieval_world.bridge_trial
		check(replica.phase=="running" and replica.attempt==1 and replica.parcel!=null,"late join snapshot contains the active attempt")
		check(replica.parcel.freeze and replica.parcel.collision_layer==0,"replica cargo cannot simulate or collide independently")
		check(not replica.start().ok,"client presentation cannot start authority physics directly")
		var at:Vector2=replica.parcel.position
		replica.step(2)
		check(replica.parcel.position==at and replica.phase=="running","client tick cannot advance or complete the event")
		trial.parcel.position=Vector2(133,5.6);room.tick+=1
		session.apply_frame(room.frame())
		check(replica.parcel.position.distance_to(Vector2(133,5.6))<.01,"live frame carries shared cargo position")
		room.actors[owner.player_id].player.position=Vector2(20,0)
		check(not room.command(owner.player_id,{"op":"bridge_trial","action":"start","seq":2}).ok,"distant event requests are refused")
		room.actors[owner.player_id].dead_time=3
		check(not room.command(owner.player_id,{"op":"bridge_trial","action":"prepare","seq":3}).ok,"dead players cannot operate the event")
		session.game.queue_free();session.queue_free()
	room.queue_free();await process_frame
	print("MILL BRIDGE NETWORK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
