extends SceneTree
var count:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("PROGRESSIVE NETWORK: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var room:=PaperNetRoom.new();room.configure("CHIPS1","paper","chip-owner",PaperWorldStore.new("user://chip-worlds"),"chips");root.add_child(room)
	var owner:Dictionary=room.join("","主人");var friend:Dictionary=room.join("","朋友")
	room.ready(owner.player_id);room.ready(friend.player_id)
	room.set_physics_process(false)
	var actor=room.actors[owner.player_id]
	var object:Dictionary={"kind":"freehand","x":actor.player.position.x+2,"y":-1.8,"paths":[{"points":[Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5),Vector2(-.5,-.5)],"collision":true}]}
	var spawned:Dictionary=room.command(owner.player_id,{"op":"spawn","seq":1,"object":object})
	check(spawned.ok,"owner actually creates a freehand object in authority")
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch;session.apply_snapshot(room.snapshot())
	var target:Dictionary=room.world.objects[0]
	room.actors[friend.player_id].combat.damage_building(0,18,Vector2(target.x-.5,target.y))
	check(target.health==102,"friend may damage owner's drawing")
	target.version+=1
	room.tick+=1
	var frame:Dictionary=room.frame()
	check(frame.bodies[0].get("damage_cuts",[]).size()==1,"authoritative frame carries real damage geometry")
	session.apply_frame(frame)
	check(session.game.objects[0].get("damage_cuts",[]).size()==1,"other client receives progressive cutout")
	check(room.save_now().ok if room.has_method("save_now") else room._save().ok,"authoritative damaged world saves")
	var restored:Dictionary=room.store.load_world("chips")
	check(restored.ok and restored.data.objects[0].get("damage_cuts",[]).size()==1,"cloud-store format preserves damaged geometry")
	var forged:Dictionary=restored.data.duplicate(true)
	forged.erase("owner_token");forged.erase("member_credentials")
	check(PaperWorldStore._valid_data(forged),"stored damaged world is otherwise valid")
	forged.objects[0].damage_cuts=[{"x":0,"y":0,"r":INF}]
	check(not PaperWorldStore._valid_data(forged),"malformed stored cutouts cannot enter world")
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("PROGRESSIVE NETWORK: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
