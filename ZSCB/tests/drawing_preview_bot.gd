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
func marked(name:String)->bool:return FileAccess.file_exists(folder.path_join(name))
func draw_strokes(count:int)->void:
	var game=session.game;game.set_draw_mode(3)
	for stroke in count:
		var at:Vector2=game.player.position+Vector2(-3+(stroke%16)*.28,1+floorf(stroke/16.0)*.30)
		game.pointer_down(game.world_to_screen(at))
		for point in range(1,64):
			game.pointer_move(game.world_to_screen(at+Vector2(point*.08,.10*sin(point*TAU/14.0))))
		game.pointer_up(game.world_to_screen(at+Vector2(63*.08,.10*sin(63*TAU/14.0))))
func peer_matches(file:String,count:int)->bool:
	if session.remotes.is_empty() or not marked(file):return false
	var expected=PaperNetCodec.decode(FileAccess.get_file_as_string(folder.path_join(file)))
	var actual:Array=session.remotes.values().front().preview
	if actual.size()!=count:return false
	var total:=0
	for i in count:
		var points:Array=actual[i].points;total+=points.size()
		if points.size()<2 or points.front().distance_to(expected[i].points.front())>.00001 or points.back().distance_to(expected[i].points.back())>.00001:return false
	return total<=500
func run()->void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):
		seq_results[int(result.get("seq",0))]=result
		if result.get("op","") in ["spawn","save","leave"]:print("DRAW RECEIPT ",role," op=",result.get("op","")," seq=",result.get("seq",-1)," ok=",result.get("ok",false)," error=",result.get("error","")))
	if role=="owner":session.connect_room(address,"create","","甲",map_id)
	else:
		if not await wait_until(func():return marked("invite")):fail("invite missing");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite")),"乙",map_id)
	if not await wait_until(func():return session.ready_to_play):fail("snapshot handshake missing");return
	if role=="owner":write_file("invite",session.code)
	if not await wait_until(func():return session.remotes.size()==1 and session.game.on_ground):fail("friend/ground missing");return
	draw_strokes(128)
	var original:Array=session.game.draft.duplicate(true)
	var source_points:=0
	for path in original:source_points+=path.points.size()
	if original.size()!=128 or source_points!=8192:fail("actual128-stroke/8192-point source invalid: "+str(source_points));return
	write_file(role+".draft",PaperNetCodec.encode(original))
	var peer_role:="guest" if role=="owner" else "owner"
	if not await wait_until(func():return peer_matches(peer_role+".draft",128),20):fail("peer128 strokes/ends not complete");return
	if session.game.draft!=original or not session.game.objects.is_empty():fail("preview changed source or generated a body");return
	print("DRAW PREVIEW ",role,": actual128 strokes8192 source points; all remote endpoints retained <=500 points")
	write_file(role+".preview","ok")
	if role=="guest":
		if not await wait_until(func():return marked("owner.cleared") and session.remotes.values().front().preview.is_empty()):fail("owner clear missing");return
		write_file("guest.clear_seen","ok")
		if not await wait_until(func():return peer_matches("owner.redraw",1)):fail("pen-release redraw endpoint missing");return
		var game=session.game;var id=session.player_id
		session.socket.close(1001,"preview reconnect fixture")
		if not await wait_until(func():return not session.ready_to_play,4):fail("disconnect missing");return
		if not await wait_until(func():return session.ready_to_play,12):fail("reconnect missing");return
		if session.game!=game or session.player_id!=id or game.draft!=original:fail("reconnect lost local draft/identity");return
		if not await wait_until(func():return peer_matches("owner.redraw",1)):fail("snapshot lost stationary peer drawing");return
		write_file("guest.checked","preview,reconnect")
		if not await wait_until(func():return game.objects.size()==1 and session.remotes.values().front().preview.is_empty()):fail("generated body or preview clear missing");return
		if game.objects[0].paths[0].points.size()!=64:fail("final actual object was sampled like its preview");return
		write_file("guest.spawn_seen","ok")
		if not await wait_until(func():return session.ended):fail("close missing");return
		quit()
	else:
		if not await wait_until(func():return marked("guest.preview")):fail("peer did not verify drawing");return
		if DisplayServer.get_name()!="headless":
			var captures:=OS.get_environment("PAPER_NET_CAPTURE_DIR")
			if captures!="":
				DirAccess.make_dir_recursive_absolute(captures)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(captures.path_join("drawing-preview-128.png"))
		session.game.toolbar.clear_button.pressed.emit();write_file("owner.cleared","ok")
		if not await wait_until(func():return marked("guest.clear_seen")):fail("peer did not see clear");return
		draw_strokes(1);write_file("owner.redraw",PaperNetCodec.encode(session.game.draft))
		if not await wait_until(func():return marked("guest.checked") and peer_matches("guest.draft",128),20):fail("reconnect did not restore peer preview");return
		session.game.release_building()
		if not await wait_until(func():return session.game.objects.size()==1 and session.game.draft.is_empty()):fail("normal generation missing");return
		if not await wait_until(func():return marked("guest.spawn_seen")):fail("peer did not see actual full object");return
		if not await wait_until(func():return session.ready_to_play):fail("save readiness missing");return
		var number:=session.send_op("save")
		print("DRAW SAVE request=",number," ready=",session.ready_to_play," syncing=",session.syncing," revision=",session.revision)
		if not await wait_until(func():return seq_results.has(number)) or not seq_results[number].ok:fail("save missing: "+str(seq_results.get(number,{}))+" ready="+str(session.ready_to_play)+" syncing="+str(session.syncing));return
		write_file("world_id",session.world_id);write_file("owner.checked","128strokes,ends,clear,reconnect,actual64-point-body,save")
		session.leave()
		if not await wait_until(func():return session.ended):fail("leave missing");return
		print("DRAW PREVIEW owner: clear, redraw, reconnect, full actual body and save confirmed")
		quit()
