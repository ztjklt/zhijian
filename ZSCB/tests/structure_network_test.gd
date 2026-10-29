extends "res://tests/structure_links_test.gd"
func run()->void:
	var room:=PaperNetRoom.new();room.configure("LINK01","paper","owner",PaperWorldStore.new("user://structure-room"),"links");root.add_child(room);room.set_physics_process(false)
	var owner:Dictionary=room.join("","甲");var guest:Dictionary=room.join("","乙")
	room.ready(owner.player_id);room.ready(guest.player_id);game=room.world
	var square=[Vector2(-.2,-.2),Vector2(.2,-.2),Vector2(.2,.2),Vector2(-.2,.2),Vector2(-.2,-.2)]
	block("base",Vector2.ZERO,square,false)
	block("beam",Vector2(.5,0),[Vector2(-.5,-.06),Vector2(.5,-.06),Vector2(.5,.06),Vector2(-.5,.06),Vector2(-.5,-.06)])
	for i in game.objects.size():
		game.objects[i].id=str(i+1);game.objects[i].author=owner.player_id;game.objects[i].version=1
	room.next_id=3
	var msg={"op":"structure_link","action":"connect","a":"base","b":"beam","point":Vector2(.2,0),"kind":"fixed","seq":1}
	check(not room.command(guest.player_id,msg).ok,"guest cannot attach another author's creations")
	var result:Dictionary=room.command(owner.player_id,msg)
	check(result.ok and game.structure_links.records.size()==1,"near owner creates an authoritative joint")
	if not result.ok:room.queue_free();quit(1);return
	room.command(owner.player_id,msg)
	check(game.structure_links.records.size()==1,"duplicate sequence does not create a second constraint")
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch
	session.apply_snapshot(room.snapshot())
	check(session.game.structure_links.records.size()==1 and session.game.structure_links.joints.is_empty(),"late join displays matching links with zero local joints")
	check(not session.game.structure_links.create("base","beam",Vector2(.2,0),"hinge").ok,"replica cannot create authority physics")
	check(not room.command(owner.player_id,{"op":"lock","id":"2","version":1,"seq":2}).ok,"connected pieces cannot be independently dragged")
	var id:String=game.structure_links.records[0].id
	check(not room.command(guest.player_id,{"op":"structure_link","action":"unlink","id":id,"seq":2}).ok,"guest cannot unlink another author's structure")
	room.actors[owner.player_id].player.position=Vector2(100,0)
	check(not room.command(owner.player_id,{"op":"structure_link","action":"unlink","id":id,"seq":3}).ok,"distant unlink is refused")
	room.actors[owner.player_id].player.position=Vector2(-5,0);room.actors[owner.player_id].dead_time=3
	check(not room.command(owner.player_id,{"op":"structure_link","action":"unlink","id":id,"seq":4}).ok,"dead actors cannot modify links")
	room.actors[owner.player_id].dead_time=0
	check(room._save().ok,"authority writes actual linked world to disk")
	check(room.command(owner.player_id,{"op":"structure_link","action":"unlink","id":id,"seq":5}).ok,"owner explicitly removes its connection")
	check(room.command(owner.player_id,{"op":"undo","seq":6}).ok and game.structure_links.records.size()==1,"authority undo restores the removed link")
	room.command(owner.player_id,{"op":"structure_link","action":"unlink","id":id,"seq":7})
	room.actors[owner.player_id].player.position=Vector2(100,0)
	check(not room.command(owner.player_id,{"op":"undo","seq":8}).ok and game.structure_links.records.is_empty(),"undo cannot bypass connection distance checks")
	room.actors[owner.player_id].player.position=Vector2(-5,0)
	room.command(owner.player_id,dict_msg(9))
	var snap:Dictionary=room.snapshot();var imported:Dictionary={"objects":snap.objects,"world":snap.world}
	check(room._import_world(room.actors[owner.player_id],imported).ok and game.structure_links.records.size()==1,"import remaps network IDs while preserving part connection identities")
	var revision:int=room.revision
	var beam=game.structure_links.body("beam")
	PaperObjectDamage.add_cut(beam.data,Vector2(.2,0),40);beam.rebuild_damage()
	room._save()
	check(game.structure_links.records.is_empty() and room.revision>revision,"save-time severing publishes a new revision to both clients")
	beam.data.damage_cuts=[];beam.rebuild_damage()
	game.structure_links.create("base","beam",Vector2(.2,0),"fixed")
	revision=room.revision
	PaperObjectDamage.add_cut(beam.data,Vector2(.2,0),40);beam.rebuild_damage()
	room.snapshot()
	check(game.structure_links.records.is_empty() and room.revision>revision,"snapshot-time severing also publishes a new revision")
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("STRUCTURE NETWORK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func dict_msg(seq:int)->Dictionary:
	return {"op":"structure_link","action":"connect","a":"base","b":"beam","point":Vector2(.2,0),"kind":"fixed","seq":seq}
