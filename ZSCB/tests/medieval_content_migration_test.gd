extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false);game.player.freeze=true
	var snapshot:Dictionary=game.snapshot()
	snapshot.world.erase("content_version")
	snapshot.world.entities=snapshot.world.entities.filter(func(r):return r.kind=="castle_piece" or int(str(r.id).get_slice("-",1))<100)
	for r in snapshot.world.entities:
		if r.id=="house-0":r.health=0;r.alive=false;r.state="destroyed"
	snapshot.objects=[{"x":26.0,"y":5.0,"kind":"freehand","dynamic":false,"paths":[{"points":[Vector2(-1,0),Vector2(1,0)],"collision":true}]}]
	game.select_world("paper")
	game.restore(snapshot)
	check(game.medieval_world.entities.size()>200,"main restore upgrades an old snapshot with the revised living-map composition")
	check(not game.medieval_world.entity_by_id("house-0").alive,"upgrade preserves destroyed original building")
	check(game.objects.size()==1 and game.objects[0].x==26,"upgrade preserves the player's drawn creation")
	check(game.snapshot().world.content_version==3,"upgraded snapshots explicitly record the content revision")
	game.medieval_world.damage_entity(game.medieval_world.entity_by_id("grass_meadow-100"),99,Vector2.ZERO,Vector2.ZERO)
	check(game.save_game(),"expanded content with cut grass saves through normal game flow")
	var loaded:Dictionary=SaveStore.load_game("medieval-v1")
	check(loaded.error.is_empty() and loaded.data.world.content_version==3,"JSON save retains content revision")
	game.load_game()
	var current:Dictionary=game.snapshot()
	var count:int=current.world.entities.size()
	game.restore(current)
	check(game.medieval_world.entities.size()==count and not game.medieval_world.entity_by_id("grass_meadow-100").alive,"current restore neither duplicates the new map nor resurrects cut grass")
	var invalid:Dictionary=game.world_save_state()
	invalid.content_version=4
	var preserved:=FileAccess.get_file_as_string("user://paper_castle_medieval_v1.json")
	var rejected:Dictionary=SaveStore.save_game(game.paper,game.objects,game.bag,game.camera_x,game.player.position.x,game.equipped_weapon,invalid)
	check(not rejected.ok and FileAccess.get_file_as_string("user://paper_castle_medieval_v1.json")==preserved,"unknown content revision cannot overwrite a healthy work")
	game.queue_free();await process_frame
	print("CONTENT MIGRATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
