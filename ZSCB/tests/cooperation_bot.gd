extends "res://tests/network_duel_bot.gd"
static func undo_visible(client:PaperNetSession,expected:Dictionary)->bool:
	if not client.ready_to_play or client.syncing:return false
	for i in client.game.objects.size():
		var object:Dictionary=client.game.objects[i]
		if str(object.id)!=str(expected.id):continue
		if int(object.version)<int(expected.version) or not client.targets.has(str(object.id)):return false
		var target:Dictionary=client.targets[str(object.id)]
		var body:RigidBody2D=client.game.object_nodes[i]
		return body.position.distance_to(target.position)<.025 and absf(angle_difference(body.rotation,float(target.angle)))<.01
	return false
func own_piece()->Dictionary:
	for object in session.game.objects:
		if object.author==session.player_id:return object
	return {}
func lend(enabled:bool)->bool:
	if not await wait_until(func():return session.ready_to_play):return false
	var game=session.game;game.open_cooperation();game.cooperation_panel.selected_id=own_piece().id;game.cooperation_panel.refresh()
	if game.cooperation_panel.share_button.disabled:return false
	var before:int=session.seq
	game.cooperation_panel.share_button.pressed.emit();var number:int=session.seq
	if number<=before:return false
	print("COOP LEND ",role," requested=",number," enabled=",enabled," selected=",game.cooperation_panel.selected_id," state=",game.cooperation)
	if not await wait_until(func():return results.has(number)) or not results[number].ok or results[number].get("op","")!="collaborate":return false
	print("COOP LEND RECEIPT ",role," result=",results[number]," state=",game.cooperation)
	if not await wait_until(func():return (own_piece().id in game.cooperation.get("shared",[]))==enabled):return false
	game.cooperation_panel.close();return true
func run()->void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):
		results[int(result.get("seq",0))]=result
		if result.get("op","")=="structure_link":print("COOP CONNECT RECEIPT ",result))
	if role=="owner":session.connect_room(address,"create","","共建甲","paper")
	else:
		if not await wait_until(func():return marked("invite")):fail("invite missing");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite")),"共建乙","paper")
	if not await wait_until(func():return session.ready_to_play):fail("not ready");return
	if role=="owner":mark("invite",session.code)
	if not await wait_until(func():return session.remotes.size()==1):fail("partner missing");return
	var game=session.game
	game.activate_draw_mode(3);game.build_kind="freehand"
	game.draft=[{"points":[Vector2(-1,-2.3),Vector2(.3,-2.3)] if role=="owner" else [Vector2(.42,-2.3),Vector2(1.72,-2.3)]}]
	var bag_count:int=game.bag.entries.size();game.generate()
	if not await wait_until(func():return game.draft.is_empty() and game.bag.entries.size()>bag_count and not own_piece().is_empty()):fail("own complete drawing not generated");return
	mark(role+".drawn")
	if not await wait_until(func():return game.objects.size()==2 and marked("owner.drawn") and marked("guest.drawn")):fail("two authors' pieces missing");return
	await create_timer(1).timeout
	if not await lend(true):fail("actual panel could not lend own piece");return
	mark(role+".shared")
	if not await wait_until(func():return session.ready_to_play and game.cooperation.get("shared",[]).size()==2 and marked("owner.shared") and marked("guest.shared")):fail("lending not visible on both clients");return
	phase="shared move"
	if role=="guest":
		var foreign:Dictionary=game.objects.filter(func(object):return object.author!=session.player_id)[0]
		var expected_undo:Dictionary={"id":str(foreign.id),"version":int(foreign.version)+2}
		var before:=Vector2(foreign.x,foreign.y);game.set_draw_mode(4);game.set_connection_tool("move")
		var previous_seq:int=session.seq
		game.pointer_down(game.world_to_screen(before));var lock_number:int=session.seq
		print("COOP POINTER ",role," screen=",game.world_to_screen(before)," blocked=",game.toolbar.blocks_canvas(game.world_to_screen(before))," selected=",game.selected," drag=",game.drag!=null," sequence=",previous_seq,"->",lock_number)
		if lock_number<=previous_seq:fail("borrowed pointer did not start a real lock");return
		if not await wait_until(func():return results.has(lock_number)) or not results[lock_number].ok:fail("borrowed edit lock denied");return
		print("COOP LOCK CONFIRMED ",role," selected=",game.selected," drag=",game.drag!=null," ready=",session.ready_to_play)
		game.pointer_move(game.world_to_screen(before+Vector2(-.4,0)));game.pointer_up(game.world_to_screen(before+Vector2(-.4,0)))
		var number:int=session.seq
		print("COOP MOVE REQUEST ",role," number=",number," ready=",session.ready_to_play)
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("borrowed actual move denied");return
		if not await wait_until(func():return session.ready_to_play):fail("move state not ready for undo");return
		number=session.send_op("undo")
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("borrowed move undo denied");return
		if not await wait_until(func():return undo_visible(session,expected_undo)):fail("guest undo replica not current");return
		# Publish the receipt only after its complete JSON is on disk.
		mark("guest.moved.tmp",JSON.stringify(expected_undo))
		if DirAccess.rename_absolute(folder.path_join("guest.moved.tmp"),folder.path_join("guest.moved"))!=OK:fail("undo coordination receipt could not be published");return
	else:
		if not await wait_until(func():return marked("guest.moved")):fail("partner move missing");return
		var expected_undo:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("guest.moved")))
		if not await wait_until(func():return undo_visible(session,expected_undo)):fail("owner undo replica not current");return
		print("COOP CONNECT BEGIN ready=",session.ready_to_play," seq=",session.seq," revision=",session.revision)
		game.set_draw_mode(4);game.set_connection_tool("fixed")
		for object in game.objects:
			var point:Vector2=game.object_point(object,object.paths[0].points[-1] if object.author==session.player_id else object.paths[0].points[0])
			var previous:int=session.seq
			game.pointer_down(game.world_to_screen(point));game.pointer_up(game.world_to_screen(point))
			print("COOP CONNECT CLICK ready=",session.ready_to_play," point=",point," source=",game.connection_source," seq=",previous,"->",session.seq," note=",game.toolbar.status_text)
	if not await wait_until(func():return game.structure_links.records.size()==1 and session.ready_to_play):fail("cross-author real fixed joint missing");return
	if not game.structure_links.joints.is_empty():fail("client created its own physics joints");return
	mark(role+".connected")
	if not await wait_until(func():return marked("owner.connected") and marked("guest.connected")):fail("partner joint missing");return
	if role=="owner":
		if DisplayServer.get_name()!="headless":
			var captures:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
			DirAccess.make_dir_recursive_absolute(captures)
			for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
				root.content_scale_size=Vector2i.ZERO;root.size=size;game.open_cooperation()
				for i in 8:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(captures.path_join("cooperation-%dx%d.png"%[size.x,size.y]))
				game.cooperation_panel.close()
		if not await lend(false):fail("author could not withdraw via actual panel");return
		mark("owner.revoked")
	else:
		if not await wait_until(func():return session.ready_to_play and marked("owner.revoked") and game.cooperation.get("shared",[]).size()==1):fail("revocation did not reach partner");return
		var number:=session.send_op("structure_link",{"action":"unlink","id":game.structure_links.records[0].id})
		if not await wait_until(func():return results.has(number)) or results[number].ok:fail("revoked partner could still unlink");return
		mark("guest.denied")
	if role=="owner":
		if not await wait_until(func():return session.ready_to_play and marked("guest.denied")):fail("partner denial missing");return
		var number:=session.send_op("save")
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("co-created save failed");return
		session.leave()
	if not await wait_until(func():return session.ended):fail("first room close missing");return
	var credential:String=session.token;var saved_world:String=session.world_id;var original_id:String=session.player_id
	game.queue_free();session.queue_free();await process_frame
	session=PaperNetSession.new();root.add_child(session);results.clear()
	session.operation_finished.connect(func(result):
		results[int(result.get("seq",0))]=result
		if result.get("op","")=="structure_link":print("COOP CONNECT RECEIPT ",result))
	if role=="owner":session.connect_room(address,"create","","共建甲","paper",credential,saved_world)
	else:
		if not await wait_until(func():return marked("invite2")):fail("reopen invite missing");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite2")),"共建乙","paper",credential)
	if not await wait_until(func():return session.ready_to_play):fail("saved world could not reopen");return
	if role=="owner":mark("invite2",session.code)
	game=session.game
	if session.player_id!=original_id or game.objects.size()!=2 or game.structure_links.records.size()!=1 or not game.cooperation.get("shared",[]).is_empty():fail("reopen did not preserve authors/structure and clear permission");return
	mark(role+".restored")
	if not await wait_until(func():return marked("owner.restored") and marked("guest.restored")):fail("partner reopen missing");return
	print("COOP CLIENT ",role," actual own drawing, lending panel, shared move/undo, cross-author fixed joint, revocation denial, saved reopen with authors and no stale permissions")
	mark(role+".checked");mark("world_id",saved_world)
	if role=="owner":session.leave()
	if not await wait_until(func():return session.ended):fail("final close missing");return
	quit()
