extends "res://tests/structure_links_test.gd"
func run()->void:
	var room:=PaperNetRoom.new();room.configure("COOP03","paper","owner",PaperWorldStore.new("user://coop-replica"),"replica");root.add_child(room);room.set_physics_process(false)
	var owner:String=room.join("","甲").player_id;var guest:String=room.join("","乙").player_id
	room.ready(owner);room.ready(guest);game=room.world
	block("part",Vector2.ZERO,[Vector2(-.2,-.2),Vector2(.2,-.2),Vector2(.2,.2),Vector2(-.2,.2),Vector2(-.2,-.2)])
	game.objects[0].id="1";game.objects[0].author=owner;game.objects[0].version=1
	room.command(owner,{"op":"collaborate","id":"1","version":1,"enabled":true,"seq":1})
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=guest;session.epoch=room.epoch;session.apply_snapshot(room.snapshot());game=session.game
	check(game.can_cooperate(game.objects[0]),"real snapshot lends the foreign part on replica")
	var old:Dictionary=room.snapshot().cooperation
	game.set_draw_mode(4);game.pointer_down(game.world_to_screen(Vector2.ZERO))
	check(game.selected==0 and game.drag!=null,"normal pointer actually selects a borrowed piece")
	game.refresh_buttons()
	check(game.toolbar.delete_button.disabled,"UI never offers demolition of a borrowed piece")
	var number:int=session.seq
	room.command(owner,{"op":"collaborate","id":"1","version":2,"enabled":false,"seq":2})
	game.receive_cooperation(room.snapshot().cooperation)
	check(game.drag==null and game.selected==-1 and session.seq==number,"revocation cancels local drag without emitting a move")
	game.receive_cooperation(old)
	check(not game.can_cooperate(game.objects[0]),"late snapshot cannot restore revoked permission")
	room.command(owner,{"op":"collaborate","id":"1","version":3,"enabled":true,"seq":3})
	room.command(owner,{"op":"lock","id":"1","version":4,"seq":4})
	var frame:Dictionary=room.frame();frame.tick=10;session.apply_frame(frame)
	check(not game.can_cooperate(game.objects[0]) and game.cooperation.locks.get("1")==owner,"actual frames show friend's current edit lock")
	frame.tick=9;frame.cooperation=old;session.apply_frame(frame)
	check(game.cooperation.locks.get("1")==owner,"older frame cannot roll back edit lock")
	game.open_cooperation();await process_frame
	check(game.cooperation_panel.list.item_count==1 and game.cooperation_panel.share_button.disabled,"borrower sees piece and cannot grant or revoke it")
	check(game.cooperation_panel.details.text.contains("不能拆除"),"borrower panel clearly states retained author rights")
	game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("COOP REPLICA: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
