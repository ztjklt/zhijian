extends "res://tests/network_duel_bot.gd"
## Full clients use the normal draw and connection entry points.
func run()->void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):results[int(result.get("seq",0))]=result)
	if role=="owner":session.connect_room(address,"create","","搭建甲","paper")
	else:
		if not await wait_until(func():return marked("invite")):fail("invite missing");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite")),"搭建乙","paper")
	if not await wait_until(func():return session.ready_to_play):fail("not ready");return
	if role=="owner":mark("invite",session.code)
	if not await wait_until(func():return session.remotes.size()==1):fail("partner missing");return
	var game=session.game;var links=game.structure_links
	if role=="owner":
		for points in [[Vector2(-1,-2.3),Vector2(.3,-2.3)],[Vector2(.42,-2.3),Vector2(1.72,-2.3)]]:
			game.activate_draw_mode(3);game.build_kind="freehand";game.draft=[{"points":points}];game.generate()
			var count:int=game.bag.entries.size()
			if not await wait_until(func():return game.draft.is_empty() and game.bag.entries.size()>count):fail("drawing not confirmed");return
		if not await wait_until(func():return game.objects.size()==2):fail("two creations missing");return
		await create_timer(1).timeout
		game.set_draw_mode(4);game.set_connection_tool("fixed")
		for object in game.objects:
			var end:Vector2=game.object_point(object,object.paths[0].points[-1] if object.x<.5 else object.paths[0].points[0])
			game.pointer_down(game.world_to_screen(end));game.pointer_up(game.world_to_screen(end))
	if not await wait_until(func():return links.records.size()==1):fail("fixed link did not reach full clients");return
	if not await wait_until(func():return session.ready_to_play):fail("fixed resync not ready");return
	phase="fixed shared"
	if not links.joints.is_empty():fail("client simulated a physical joint");return
	mark(role+".fixed")
	if role=="guest":
		var number:=session.send_op("structure_link",{"action":"unlink","id":links.records[0].id})
		print("STRUCTURE PERMISSION request=",number," ready=",session.ready_to_play)
		if not await wait_until(func():return results.has(number)) or results[number].ok:fail("guest bypassed author permission");return
		mark("guest.denied")
	else:
		if not await wait_until(func():return marked("guest.denied") and marked("guest.fixed")):fail("partner did not verify fixed link");return
		game.set_connection_tool("unlink");var point:Vector2=links.marker(links.records[0])
		game.pointer_down(game.world_to_screen(point));game.pointer_up(game.world_to_screen(point))
	if not await wait_until(func():return links.records.is_empty()):fail("unlink not shared");return
	if not await wait_until(func():return session.ready_to_play):fail("unlink resync not ready");return
	phase="unlinked shared"
	mark(role+".unlinked")
	if role=="owner":
		if not await wait_until(func():return marked("guest.unlinked")):fail("partner unlink missing");return
		game.set_connection_tool("hinge")
		for object in game.objects:
			var end:Vector2=game.object_point(object,object.paths[0].points[-1] if object.x<.5 else object.paths[0].points[0])
			game.pointer_down(game.world_to_screen(end));game.pointer_up(game.world_to_screen(end))
	if not await wait_until(func():return links.records.size()==1 and links.records[0].kind=="hinge"):fail("hinge not shared");return
	if not await wait_until(func():return session.ready_to_play):fail("hinge resync not ready");return
	if game.objects.size()!=2:fail("connection replaced source parts");return
	print("STRUCTURE CLIENT ",role," confirmed fixed/unlink/hinge, retained drawings, authority permission and no replica physics")
	mark(role+".structure")
	if not await wait_until(func():return marked("owner.structure") and marked("guest.structure")):fail("partner result missing");return
	if role=="owner":
		var number:=session.send_op("save")
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("linked save failed");return
		mark("world_id",session.world_id);mark("owner.checked");session.leave()
		if not await wait_until(func():return session.ended):fail("close failed");return
	else:
		mark("guest.checked")
		if not await wait_until(func():return session.ended):fail("owner close missing");return
	quit()
