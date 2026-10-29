extends "res://tests/network_duel_bot.gd"
## Two complete game clients travel, draw, retry and save against the real authority.
var mill_diagnostic_clock:=0.0
func _process(delta:float)->bool:
	mill_diagnostic_clock+=delta
	if mill_diagnostic_clock>=2 and session!=null and session.game!=null and phase=="shared event":
		mill_diagnostic_clock=0
		var trial=session.game.medieval_world.bridge_trial
		print("MILL STATE ",role," phase=",trial.phase," attempt=",trial.attempt," cargo=",trial.parcel.position if is_instance_valid(trial.parcel) else Vector2.ZERO," objects=",session.game.objects.size()," ping=",session.round_trip_ms)
	return false
func run()->void:
	session=PaperNetSession.new();root.add_child(session)
	session.operation_finished.connect(func(result):results[int(result.get("seq",0))]=result)
	if role=="owner":session.connect_room(address,"create","","试桥甲","medieval-v1")
	else:
		if not await wait_until(func():return marked("invite")):fail("missing invite");return
		session.connect_room(address,"join",FileAccess.get_file_as_string(folder.path_join("invite")),"试桥乙","medieval-v1")
	if not await wait_until(func():return session.ready_to_play):fail("not ready");return
	if role=="owner":mark("invite",session.code)
	if not await wait_until(func():return session.remotes.size()==1):fail("missing partner");return
	var game=session.game
	phase="walk to mill"
	Input.action_press("move_right")
	var arrived:bool=await wait_until(func():return game.player.position.x>=130,65)
	Input.action_release("move_right")
	print("MILL ARRIVAL ",role," x=",game.player.position.x," target=",session.local_target," ping=",session.round_trip_ms," input_down=",Input.is_action_pressed("move_right"))
	if not arrived:fail("actual controls could not reach mill");return
	await create_timer(maxf(.8,session.round_trip_ms/1000.0+.2)).timeout
	mark(role+".at_mill")
	if not await wait_until(func():return marked("owner.at_mill") and marked("guest.at_mill"),10):fail("partner did not reach mill");return
	var trial=game.medieval_world.bridge_trial
	print("MILL AT REST ",role," x=",game.player.position.x," target=",session.local_target," ping=",session.round_trip_ms)
	phase="shared event"
	if role=="owner":
		game.bridge_trial_action("prepare")
		if not await wait_until(func():return trial.phase=="ready"):fail("stands not confirmed");return
		game.bridge_trial_action("start")
		if not await wait_until(func():return trial.phase=="failed",10):fail("missing bridge did not fail");return
		if not await wait_until(func():return game.objects.size()==1,12):fail("partner bridge missing");return
		await create_timer(1).timeout
		game.bridge_trial_action("start")
	else:
		if not await wait_until(func():return trial.phase=="failed",15):fail("failed cargo not shared");return
		var before:int=game.bag.entries.size()
		game.activate_draw_mode(3);game.build_kind="freehand"
		game.draft=[{"points":[Vector2(129.6,5.47),Vector2(137.4,5.47),Vector2(137.4,5.53),Vector2(129.6,5.53),Vector2(129.6,5.47)]}]
		game.generate()
		if not await wait_until(func():return game.objects.size()==1 and game.bag.entries.size()==before+1):fail("actual drawing/confirmation did not create a private blueprint and shared bridge");return
		print("MILL BRIDGE CREATED ",game.objects[0])
	if not await wait_until(func():return trial.phase=="delivered",25):fail("real bridge did not carry cargo");return
	if trial.attempt!=2 or not trial.completed or game.objects.size()!=1 or not trial.parcel.freeze:fail("delivery state or retained construction invalid");return
	print("MILL CLIENT ",role," observed missing-bridge failure, actual partner-drawn support and delivered attempt=",trial.attempt)
	mark(role+".delivered")
	if not await wait_until(func():return marked("owner.delivered") and marked("guest.delivered")):fail("partner completion missing");return
	if role=="guest":
		mark("guest.checked")
		if not await wait_until(func():return session.ended,10):fail("owner close missing");return
	else:
		var number:=session.send_op("save")
		if not await wait_until(func():return results.has(number)) or not results[number].ok:fail("save failed");return
		mark("world_id",session.world_id);mark("owner.checked")
		session.leave()
		if not await wait_until(func():return session.ended,5):fail("close failed");return
	quit()
