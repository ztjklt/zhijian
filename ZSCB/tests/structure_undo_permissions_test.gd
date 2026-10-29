extends "res://tests/structure_links_test.gd"
func run()->void:
	for scenario in ["locked", "distant", "normal"]:
		var room:=PaperNetRoom.new();room.configure("LINK01","paper","owner",PaperWorldStore.new("user://structure-undo-"+scenario),"world");root.add_child(room);room.set_physics_process(false)
		var owner:Dictionary=room.join("","甲");room.ready(owner.player_id);game=room.world
		block("base",Vector2.ZERO,[Vector2(-.3,-.3),Vector2(.3,-.3),Vector2(.3,.3),Vector2(-.3,.3),Vector2(-.3,-.3)],false)
		block("beam",Vector2(1.4,0),[Vector2(-1,-.06),Vector2(1,-.06),Vector2(1,.06),Vector2(-1,.06),Vector2(-1,-.06)])
		for i in game.objects.size():game.objects[i].id=str(i+1);game.objects[i].author=owner.player_id;game.objects[i].version=1
		room.next_id=3
		check(room.command(owner.player_id,{"op":"structure_link","action":"connect","a":"base","b":"beam","point":Vector2(.35,0),"kind":"fixed","seq":1}).ok,"connected fixture for "+scenario)
		check(room.command(owner.player_id,{"op":"delete","id":"2","version":game.objects[1].version,"seq":2}).ok,"owner removes one connected part for "+scenario)
		if scenario=="locked":check(room.command(owner.player_id,{"op":"lock","id":"1","version":game.objects[0].version,"seq":3}).ok,"surviving endpoint can enter edit lock")
		if scenario=="distant":room.actors[owner.player_id].player.position=Vector2(12.5,0)
		var result:Dictionary=room.command(owner.player_id,{"op":"undo","seq":4})
		check(result.ok==(scenario=="normal"),"delete undo checks both connection endpoints for "+scenario)
		check(game.structure_links.records.size()==(1 if scenario=="normal" else 0) and game.objects.size()==(2 if scenario=="normal" else 1),"rejected restoration changes neither bodies nor connections for "+scenario)
		room.queue_free();await process_frame
	print("STRUCTURE UNDO PERMISSIONS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
