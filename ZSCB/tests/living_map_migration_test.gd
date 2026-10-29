extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error("LIVING MIGRATION: "+label)
func run()->void:
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false;root.add_child(game);await process_frame
	game.onboarding.dismiss();game.set_physics_process(false);game.player.freeze=true
	var terrain=game.medieval_world.terrain
	var original:=Vector2(3,-1.2)
	var expected:Vector2=terrain.upgrade_position(original,2)
	var object:={"kind":"freehand","source":"own","dynamic":true,"x":original.x,"y":original.y,"angle":.27,"paths":[{"points":[Vector2(-.2,-.2),Vector2(.2,-.2),Vector2(.2,.2),Vector2(-.2,.2),Vector2(-.2,-.2)],"collision":true}]}
	var paths:Array=object.paths.duplicate(true)
	var old_tree:=MedievalEntity.new()
	old_tree.setup("oak",Vector2(8.2,0.04),"oak-1",.04)
	var record:Dictionary=old_tree.save_record();old_tree.free()
	record.health=120.0;record.cuts=[{"x":0.0,"y":.5,"radius":.3,"side":0}]
	var details:Dictionary=game.world_save_state()
	details.terrain_version=2;details.content_version=2;details.entities=[record]
	details.player_y=-1.64;details.camera_y=0.0
	var saved:Dictionary=SaveStore.save_game(game.paper,[object],game.bag,3,3,{},details)
	check(saved.ok,"normal save API accepts legacy v2 terrain/content fixture")
	game.load_game()
	check(game.objects.size()==1,"normal load preserves one creation")
	check(absf(game.objects[0].y-expected.y)<.001,"normal load upgrades creation from exact v2 terrain height")
	check(game.objects[0].paths==paths and is_equal_approx(game.objects[0].angle,.27),"migration preserves contour and angle")
	var expected_player:Vector2=terrain.upgrade_position(Vector2(3,-1.64),2)
	check(absf(game.player.position.x-expected_player.x)<.51 and game.player.position.y>=expected_player.y-.01 and game.player.position.y<=expected_player.y+.3,"player upgrades above new mountain with only the needed slope-footprint clearance")
	var tree=game.medieval_world.entity_by_id("oak-1")
	check(tree!=null and tree.health==120 and tree.cuts.size()==1,"retired tree with user damage remains intact in migration")
	check(game.world_save_state().terrain_version==3 and game.world_save_state().content_version==3,"current snapshots explicitly use both v3 revisions")
	check(game.save_game(),"upgraded work saves through normal API")
	var healthy_local:=FileAccess.get_file_as_string("user://paper_castle_medieval_v1.json")
	var invalid_local:Dictionary=game.world_save_state()
	invalid_local.content_version=1
	invalid_local.entities=invalid_local.entities.slice(0,97)
	check(not SaveStore.save_game(game.paper,game.objects,game.bag,3,3,{},invalid_local).ok,"oversized version1 snapshot is rejected before local persistence")
	check(FileAccess.get_file_as_string("user://paper_castle_medieval_v1.json")==healthy_local,"invalid migration input preserves healthy local work")
	game.load_game()
	check(absf(game.objects[0].y-expected.y)<.001,"second load never applies terrain shift twice")
	game.queue_free();await process_frame
	var room:=PaperNetRoom.new()
	room.configure("HILLS","medieval-v1","owner-living",PaperWorldStore.new("user://living_migration_room"),"world")
	root.add_child(room)
	var owner:Dictionary=room.join("","画家");room.ready(owner.player_id)
	var imported:Dictionary=room.command(owner.player_id,{"op":"import","seq":1,"data":{"objects":[object.duplicate(true)],"world":details.duplicate(true)}})
	check(imported.ok,"authority imports old terrain work transactionally")
	if imported.ok:
		check(absf(room.world.objects[0].y-expected.y)<.001,"authority imports creation at new terrain height")
		check(room.world._world_details().terrain_version==3,"authority emits current terrain revision")
		var healthy_path:String=room.store.directory.path_join("world.json")
		var healthy_server:=FileAccess.get_file_as_string(healthy_path)
		var invalid_details:Dictionary=details.duplicate(true)
		invalid_details.terrain_version=4
		check(not room.command(owner.player_id,{"op":"import","seq":2,"data":{"objects":[],"world":invalid_details}}).ok,"unknown terrain version cannot replace authoritative work")
		invalid_details=room.world._world_details().duplicate(true)
		invalid_details.content_version=1;invalid_details.entities=invalid_details.entities.slice(0,97)
		check(not room.command(owner.player_id,{"op":"import","seq":3,"data":{"objects":[],"world":invalid_details}}).ok,"oversized version1 import is rejected before mutation")
		check(room.world.objects.size()==1 and absf(room.world.objects[0].y-expected.y)<.001 and FileAccess.get_file_as_string(healthy_path)==healthy_server,"rejected authority imports preserve live creation and disk snapshot")
		var invalid_stored:Dictionary=room.store.load_world("world").data
		invalid_stored.world.content_version=4
		check(not room.store.save("world",invalid_stored).ok and FileAccess.get_file_as_string(healthy_path)==healthy_server,"server persistence independently validates complete migration metadata")
	room.queue_free();await process_frame
	room=PaperNetRoom.new()
	room.configure("HILLS2","medieval-v1","owner-living",PaperWorldStore.new("user://living_migration_room"),"world")
	root.add_child(room)
	check(not room.closed and room.world.objects.size()==1,"server reload recovers the atomically saved import")
	if not room.world.objects.is_empty():check(absf(room.world.objects[0].y-expected.y)<.001,"server restart upgrades source coordinates exactly once")
	room.queue_free();await process_frame
	print("LIVING MAP MIGRATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
