extends "res://tests/structure_links_test.gd"
func run()->void:
	game=load("res://scenes/sandbox.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);game.set_physics_process(false);game.player.freeze=true
	var square=[Vector2(-.2,-.2),Vector2(.2,-.2),Vector2(.2,.2),Vector2(-.2,.2),Vector2(-.2,-.2)]
	block("base",Vector2(30,12),square,false)
	block("beam",Vector2(30.5,12),[Vector2(-.5,-.06),Vector2(.5,-.06),Vector2(.5,.06),Vector2(-.5,.06),Vector2(-.5,-.06)])
	var links=game.structure_links
	check(links.create("base","beam",Vector2(30.2,12),"fixed").ok,"fixture has a genuine connection")
	var world:Dictionary=game.world_save_state()
	check(world.get("connections",[]).size()==1,"world save includes connections")
	if not world.has("connections"):game.queue_free();quit(1);return
	check(game.save_game(),"actual local JSON save succeeds")
	var loaded:Dictionary=SaveStore.load_game()
	check(loaded.error=="" and loaded.data.world.connections.size()==1,"actual disk round trip retains the link")
	links.clear();game.load_game()
	check(links.records.size()==1 and links.joints.size()==1,"loading restores active physical constraints")
	var before:Dictionary=game.snapshot()
	game.change_map("nature-v1")
	check(links.records.is_empty(),"another map receives no foreign connections")
	game.change_map("knowledge-v1")
	check(links.records.size()==1 and game.objects.size()==2,"returning restores the original structure")
	var bad:Dictionary=game.snapshot();bad.world.connections[0].a="missing"
	var untouched:Dictionary=game.snapshot();game.restore(bad)
	check(game.snapshot()==untouched,"invalid reference restore is atomic")
	check(not SaveStore.save_game(game.paper,game.objects,game.bag,game.camera_x,game.player.position.x,{},bad.world).ok,"invalid links cannot replace a valid disk save")
	var malformed:Dictionary=before.duplicate(true);malformed.world.connections[0].ax=NAN
	check(not links.valid_state(malformed.world.connections,game.objects),"nonfinite anchors are invalid")
	malformed=before.duplicate(true);malformed.world.connections.append(malformed.world.connections[0].duplicate(true))
	check(not links.valid_state(malformed.world.connections,game.objects),"duplicate constraints are invalid")
	game.record();links.remove(links.records[0].id);game.undo()
	check(links.records.size()==1,"undo restores a removed constraint")
	game.redo();check(links.records.is_empty(),"redo removes it again")
	before.world.erase("connections");game.restore(before)
	check(links.records.is_empty(),"legacy missing field means no automatic joints")
	game.queue_free();await process_frame
	print("STRUCTURE STATE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
