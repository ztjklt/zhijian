extends SceneTree
var session: PaperNetSession
var role := ""
var folder := ""
var address := ""
var map_id := "paper"
var seq_results: Dictionary = {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role=arg.trim_prefix("--role=")
		elif arg.begins_with("--coord="): folder=arg.trim_prefix("--coord=")
		elif arg.begins_with("--map="): map_id=arg.trim_prefix("--map=")
		elif arg.begins_with("--address="): address=arg.trim_prefix("--address=")
	call_deferred("run")
func wait_until(condition: Callable, seconds: float=12) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call(): return true
		await process_frame
	return false
func write_file(name: String, text: String) -> void:
	var file:=FileAccess.open(folder.path_join(name),FileAccess.WRITE)
	file.store_string(text); file.close()
func fail(text: String) -> void:
	write_file(role+".failed",text)
	print("BOT_FAIL: ",role,": ",text)
	quit(1)
func click_save_entry() -> void:
	if "flow_ui" in session and session.flow_ui!=null:
		for child in session.flow_ui.menu.get_children():
			if child is Button and child.text=="保存云端世界":
				child.pressed.emit();return
	session.game.toolbar.works.get_popup().id_pressed.emit(0)

func capture_save_stage(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var captures:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
	if captures=="":return
	DirAccess.make_dir_recursive_absolute(captures)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join("save-"+label+".png"))
	var record:=FileAccess.open(captures.path_join("save-"+label+".json"),FileAccess.WRITE)
	record.store_string(PaperNetCodec.encode({"phase":session.save_request.phase,"message":session.save_request.text}));record.close()

func run() -> void:
	session=PaperNetSession.new(); root.add_child(session)
	session.operation_finished.connect(func(result):
		seq_results[int(result.get("seq",0))]=result
		if result.get("op","") not in ["","input","preview"]: print("RESULT ",role,": ",result.get("op","")," ok=",result.get("ok",false)," seq=",result.get("seq",0)," error=",result.get("error","")))
	if role=="owner":
		session.connect_room(address,"create","","甲",map_id)
	else:
		if not await wait_until(func():return FileAccess.file_exists(folder.path_join("invite"))): fail("没有收到邀请"); return
		var code:=FileAccess.get_file_as_string(folder.path_join("invite"))
		session.connect_room(address,"join",code,"乙","paper")
	if not await wait_until(func():return session.ready_to_play): fail("客户端未完成快照握手："+session.status); return
	if role=="owner":
		write_file("invite",session.code)
		if not await wait_until(func():return session.remotes.size()==1): fail("未显示朋友"); return
		var game:PaperCastleMain=session.game
		game.draw_mode=3
		var x:=game.player.position.x+3.0
		var y:=game.player.position.y+5
		game.draft=[{"points":[Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+.5),Vector2(x,y+.5),Vector2(x,y)]}]
		game.release_building()
		if not await wait_until(func():return game.objects.size()==1 and game.draft.is_empty() and session.ready_to_play): fail("实际建筑生成未完成"); return
		if game.bag.entries.size()!=7: fail("新图纸未收入个人背包"); return
		var grip:Vector2=game.player.position+Vector2(0,2)
		game.draw_mode=2
		game.draft=[{"points":[grip,grip+Vector2(0,.9)]}]
		game.generate();game.select_weapon_grip(grip);game.generate();game.select_weapon_type("sword");game.generate()
		if not await wait_until(func():return not game.equipped_weapon.is_empty() and session.sent_weapon==game.equipped_weapon and not session.equip_wait): fail("装备未得到服务器确认："+session.status+" ready="+str(session.ready_to_play)+" wait="+str(session.equip_wait)+" pending="+str(session.pending.keys())); return
		if not await wait_until(func():return FileAccess.file_exists(folder.path_join("guest.checked")),25): fail("朋友未验证共享世界"); return
		var diagnostics:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
		if diagnostics!="":
			DirAccess.make_dir_recursive_absolute(diagnostics)
			var capture:=FileAccess.open(diagnostics.path_join("world-state.json"),FileAccess.WRITE)
			capture.store_string(PaperNetCodec.encode({"world":game.world_save_state(),"camera_x":game.camera_x,"camera_y":game.camera_y,"pixels":game.PIXELS_PER_UNIT}));capture.close()
		if DisplayServer.get_name()!="headless":
			var captures:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
			if captures!="":
				DirAccess.make_dir_recursive_absolute(captures)
				for i in 8: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(captures.path_join("online-"+map_id+".png"))
		# Exercise a real resync, not a locally forged Ready flag.
		await create_timer(1.2).timeout
		session._send({"type":"resync"})
		if not await wait_until(func():return not session.ready_to_play):fail("real resync did not block Ready");return
		click_save_entry();var save_ticket:int=session.save_request.ticket
		click_save_entry()
		if session.save_request.ticket!=save_ticket or session.save_request.sequence>=0:fail("queued save duplicated or sent before Ready");return
		await capture_save_stage("queued")
		if not await wait_until(func():return session.save_request.completed.has(save_ticket),14):fail("queued save never completed");return
		if not session.save_request.completed[save_ticket].ok:fail("queued save failed: "+str(session.save_request.completed[save_ticket]));return
		var number:int=session.save_request.sequence
		if not seq_results.has(number) or not seq_results[number].ok:fail("actual save receipt missing");return
		await capture_save_stage("confirmed")
		print("SAVE REQUEST owner: real resync, duplicate user clicks joined one save, Ready then actual success")
		write_file("world_id",session.world_id)
		write_file("owner.checked","spawn,blueprint,equip,save")
		session.leave()
		if not await wait_until(func():return session.ended,5): fail("创建者退出未得到保存确认"); return
		for i in 12: await process_frame
		quit()
	else:
		if not await wait_until(func():return session.game.objects.size()==1 and session.ready_to_play): fail("朋友看不到造物"); return
		print("GUEST saw object revision=",session.revision," status=",session.status)
		var remote=session.remotes.values().front()
		if not await wait_until(func():return not remote.equipped_weapon.is_empty() and session.ready_to_play): fail("朋友看不到装备"); return
		print("GUEST saw weapon status=",session.status)
		if session.game.bag.entries.size()!=6: fail("个人图纸被创建者覆盖"); return
		print("GUEST bag=",session.game.bag.entries.size())
		var object:Dictionary=session.game.objects[0]
		var number:=session.send_op("delete",{"id":object.id,"version":object.version})
		if not await wait_until(func():return seq_results.has(number)): fail("越权操作没有结果"); return
		print("GUEST permission result=",seq_results[number])
		if seq_results[number].ok: fail("能够删除朋友作品"); return
		write_file("guest.checked","shared-object,remote-weapon,private-bag,permission")
		if not await wait_until(func():return session.ended): fail("创建者退出未结束房间"); return
		quit()
