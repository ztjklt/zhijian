extends "res://tests/structure_links_test.gd"
var room
var owner:String
var guest:String
var sequence:Dictionary={}
func op(who:String,data:Dictionary)->Dictionary:
	sequence[who]=sequence.get(who,0)+1;data.seq=sequence[who]
	return room.command(who,data)
func grant(who:String,id:String,enabled:bool)->Dictionary:
	var obj:Dictionary=game.objects[room._object_index(id)]
	return op(who,{"op":"collaborate","id":id,"version":obj.version,"enabled":enabled})
func edit(who:String,action:String,id:String,extra:Dictionary={})->Dictionary:
	var obj:Dictionary=game.objects[room._object_index(id)]
	var data={"op":action,"id":id,"version":obj.version};data.merge(extra)
	return op(who,data)
func connect_parts(who:String)->Dictionary:
	return op(who,{"op":"structure_link","action":"connect","a":"base","b":"beam","point":Vector2(.2,0),"kind":"fixed"})
func run()->void:
	room=PaperNetRoom.new();room.configure("COOP01","paper","owner",PaperWorldStore.new("user://coop-room"),"cooperation");root.add_child(room);room.set_physics_process(false)
	owner=room.join("","甲").player_id;guest=room.join("","乙").player_id
	room.ready(owner);room.ready(guest);game=room.world
	var square=[Vector2(-.2,-.2),Vector2(.2,-.2),Vector2(.2,.2),Vector2(-.2,.2),Vector2(-.2,-.2)]
	block("base",Vector2.ZERO,square,false)
	block("beam",Vector2(.7,0),[Vector2(-.5,-.06),Vector2(.5,-.06),Vector2(.5,.06),Vector2(-.5,.06),Vector2(-.5,-.06)])
	block("move_part",Vector2(3,0),square)
	for i in game.objects.size():
		game.objects[i].id=str(i+1);game.objects[i].author=guest if i==1 else owner;game.objects[i].version=1
	room.next_id=4
	check(not edit(guest,"lock","3").ok,"default author protection remains")
	check(not grant(guest,"3",true).ok,"friend cannot grant another author's piece")
	var world_revision:int=room.revision
	check(grant(owner,"3",true).ok,"author explicitly lends one piece")
	check(room.revision==world_revision,"lending metadata never interrupts an active canvas with a full world resync")
	if room.get("cooperation")==null:room.queue_free();await process_frame;print("COOP: ",checks," checks, ",failures.size()," failures");quit(1);return
	check(not op(owner,{"op":"collaborate","id":"3","version":2,"enabled":"yes"}).ok,"nonboolean permission is rejected")
	var version:int=game.objects[2].version
	var duplicate={"op":"collaborate","id":"3","version":version,"enabled":true,"seq":sequence[owner]+1}
	room.command(owner,duplicate);room.command(owner,duplicate);sequence[owner]=duplicate.seq
	check(game.objects[2].version==version,"duplicate grant does not mutate piece version twice")
	check(room.snapshot().cooperation.shared==["3"],"late snapshot includes temporary shared piece only")
	check(edit(guest,"lock","3").ok,"friend can lock an explicitly shared piece")
	check(not edit(owner,"lock","3").ok,"author cannot steal a friend's active edit lock")
	check(not edit(guest,"delete","3").ok,"shared permission never includes demolition")
	check(edit(guest,"move","3",{"position":Vector2(3,1)}).ok,"friend's real authoritative safe move succeeds")
	check(game.objects[2].author==owner and game.object_nodes[2].position.y>=1,"moving keeps author and actual body")
	check(op(guest,{"op":"undo"}).ok,"friend may undo their own unchanged move")
	check(edit(guest,"lock","3").ok,"friend can begin another move")
	var old_version:int=game.objects[2].version
	check(grant(owner,"3",false).ok and not room.locks.has("3"),"revocation releases borrowed lock immediately")
	check(not op(guest,{"op":"move","id":"3","version":old_version,"position":Vector2(4,1)}).ok,"late move after revocation is rejected")
	check(not connect_parts(owner).ok,"cross-author link requires permission on foreign endpoint")
	check(grant(guest,"2",true).ok and connect_parts(owner).ok,"two authors' actual pieces form a fixed structure")
	check(game.structure_links.records.size()==1 and not game.structure_links.joints.is_empty(),"shared structure uses real authority constraints")
	check(not op(guest,{"op":"structure_link","action":"unlink","id":game.structure_links.records[0].id}).ok,"unshared other endpoint still protects unlink")
	check(grant(owner,"1",true).ok,"other author also opens their endpoint")
	var link_id:String=game.structure_links.records[0].id
	check(op(guest,{"op":"structure_link","action":"unlink","id":link_id}).ok,"both opened endpoints allow partner unlink")
	check(op(guest,{"op":"undo"}).ok,"partner can restore their unchanged unlink")
	check(not op(owner,{"op":"undo"}).ok and game.structure_links.records.size()==1,"old creator undo cannot erase partner's later structural edit")
	check(grant(owner,"1",false).ok and game.structure_links.records.size()==1,"revoking permission preserves completed structure")
	check(not op(guest,{"op":"structure_link","action":"unlink","id":link_id}).ok,"revocation also prevents later unlink")
	check(grant(owner,"3",true).ok and edit(guest,"lock","3").ok,"borrow another piece for range regression")
	check(edit(guest,"move","3",{"position":Vector2(3,1)}).ok,"second borrowed move is confirmed")
	room.actors[guest].player.position=Vector2(100,0)
	check(not op(guest,{"op":"undo"}).ok,"undo cannot bypass12metre range")
	room.actors[guest].player.position=Vector2(-4,0)
	check(edit(owner,"delete","1").ok,"author may remove their own endpoint while keeping friend's piece")
	await process_frame
	block("support",Vector2(1.4,0),square,false)
	game.objects[-1].id="4";game.objects[-1].author=guest;game.objects[-1].version=1
	check(op(guest,{"op":"structure_link","action":"connect","a":"beam","b":"support","point":Vector2(1.2,0),"kind":"fixed"}).ok,"friend makes a later real structure on surviving endpoint")
	var old_undo:Dictionary=op(owner,{"op":"undo"})
	print("COOP DELETE UNDO ",old_undo)
	check(not old_undo.ok and game.objects.size()==3 and game.structure_links.records.size()==1,"old deletion undo cannot reattach across friend's later structural work")
	check(room._save().ok,"co-created structure can be saved")
	var saved:Dictionary=room.store.load_world(room.world_id)
	check(not saved.get("data",{}).has("cooperation") and not saved.get("data",{}).get("world",{}).has("cooperation"),"temporary permission is absent from persistent world")
	room.disconnect_player(guest)
	check(room.snapshot().cooperation.shared.is_empty() and room.locks.is_empty(),"either friend's disconnect clears all borrowed permissions and locks")
	check(game.structure_links.records.size()==1,"disconnect keeps the co-created structure")
	room.cooperation.shared["destroyed_part"]=true
	check(not room.snapshot().cooperation.shared.has("destroyed_part"),"destroyed pieces cannot exhaust temporary lending capacity")
	var restore=PaperNetRoom.new();restore.configure("COOP02","paper","owner",room.store,room.world_id);root.add_child(restore);restore.set_physics_process(false)
	check(restore.world.structure_links.records.size()==1 and restore.snapshot().cooperation.shared.is_empty(),"reopen restores creations and authors but never old lending")
	restore.queue_free();room.queue_free();await process_frame
	print("COOP: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
