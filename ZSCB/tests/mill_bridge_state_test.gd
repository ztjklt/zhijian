extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL MILL STATE: ",label)
func run()->void:
	var game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	game.set_physics_process(false);game.player.freeze=true;game.player.position=Vector2(30,0)
	var world:Dictionary=game.world_save_state()
	check(world.has("bridge_trial"),"world saves include explicit optional trial progress")
	if world.has("bridge_trial"):
		var trial=game.medieval_world.bridge_trial
		check(trial.prepare().ok,"fixture prepares a real trial")
		check(trial.start().ok,"fixture starts a real cargo")
		world=game.world_save_state()
		check(world.bridge_trial.phase=="running" and world.bridge_trial.attempt==1,"running cargo and attempt are part of the actual world save")
		var saved:Dictionary=SaveStore.save_game(game.paper,game.objects,game.bag,game.camera_x,game.player.position.x,game.equipped_weapon,world)
		check(saved.ok,"real JSON save accepts active cargo")
		var loaded:Dictionary=SaveStore.load_game("medieval-v1")
		check(loaded.error=="" and loaded.data.world.bridge_trial.attempt==1,"real disk load retains optional progress")
		var copy:Dictionary=loaded.data.world
		check(game.medieval_world.restore_state(copy.entities,copy.terrain_version,copy.content_version,copy.bridge_trial),"world restoration restores cargo alongside existing map state")
		check(trial.phase=="running" and trial.parcel!=null and trial.attempt==1,"active cargo survives reconstruction")
		game.change_map("knowledge-v1");game.change_map("medieval-v1")
		trial=game.medieval_world.bridge_trial
		check(trial.phase=="running" and trial.parcel!=null and trial.attempt==1,"switching maps and returning retains the same active event")
		var before:=JSON.stringify(game.world_save_state())
		var bad:Dictionary=world.duplicate(true);bad.bridge_trial.x=NAN
		check(not MedievalWorld.validate_snapshot(bad),"nonfinite event coordinates are rejected")
		check(not game.medieval_world.restore_state(bad.entities,bad.terrain_version,bad.content_version,bad.bridge_trial) and JSON.stringify(game.world_save_state())==before,"bad event restore is atomic for map entities and trial")
		check(not SaveStore.save_game(game.paper,game.objects,game.bag,game.camera_x,game.player.position.x,game.equipped_weapon,bad).ok,"bad event cannot replace valid disk save")
		bad=world.duplicate(true);bad.bridge_trial.phase="delivered";bad.bridge_trial.completed=false
		check(not MedievalWorld.validate_snapshot(bad),"delivered phase requires an actual completion record")
		var legacy:Dictionary=world.duplicate(true);legacy.erase("bridge_trial")
		check(MedievalWorld.validate_snapshot(legacy),"old world without an event remains valid")
		check(game.medieval_world.restore_state(legacy.entities,legacy.terrain_version,legacy.content_version),"legacy three-argument restoration still works")
		check(trial.phase=="idle" and trial.platforms.is_empty() and trial.parcel==null,"legacy restore creates no surprise trial colliders")
	game.queue_free();await process_frame
	print("MILL BRIDGE STATE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
