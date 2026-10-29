extends SceneTree
var failed: Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failed.append(label);print("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game);current_scene=game
	game.combat.set_natives(false)
	var session=PaperNetSession.new();root.add_child(session)
	session.game=game;game.network_session=session
	session.address="ws://127.0.0.1:51991/ws";session.token="fixture"
	session.ended=true;session.retries=3
	game.draft=[{"points":[Vector2(1,2),Vector2(2,3)]}]
	check(session.has_method("retry_now"),"manual reconnect is available after auto retries end")
	if session.has_method("retry_now"):
		session.retry_now()
		check(not session.ended and session.mode=="join" and session.retries==0,"manual retry resumes current session")
		check(game.draft.size()==1 and session.game==game,"retry preserves actual unfinished drawing and game")
		session.socket.close();session.socket=null
	var panel_path="res://scripts/net/online_panel.gd"
	check(ResourceLoader.exists(panel_path),"online room controls are available")
	if ResourceLoader.exists(panel_path):
		session.is_owner=true
		var panel=load(panel_path).new();panel.session=session;session.flow_ui=panel;game.add_child(panel)
		session.is_owner=true;session.ended=false;session.ready_to_play=true
		panel.request_exit("res://scenes/network_lobby.tscn")
		check(panel.dialog.visible and not session.leaving,"owner must see room-ending confirmation before leave")
		check(bool(session.get_meta("flow_modal",false)),"room dialog blocks gameplay controls")
		panel.dialog.canceled.emit();panel.dialog.hide()
		check(not bool(session.get_meta("flow_modal",false)) and not session.leaving,"cancel confirmation keeps room active")
		session.is_owner=false
		panel.request_exit("res://scenes/network_lobby.tscn")
		check(panel.dialog.dialog_text.contains("继续") and not panel.dialog.dialog_text.contains("结束房间并保存"),"guest is told friend can continue")
		panel.dialog.canceled.emit();panel.dialog.hide()
		panel.request_import()
		check(not panel.dialog.visible,"guest cannot open world-replacing import")
		check(game.draft.size()==1,"opening and canceling room controls preserve draft")
		# Exercise the actual touch router, rather than emitting a button signal directly.
		session.is_owner=true;session.ended=false;session.ready_to_play=true
		panel._process(0)
		for i in 4: await process_frame
		var invite_button:Button
		for button in panel.panel.find_children("*","Button",true,false):
			if button.text=="邀请朋友":invite_button=button
		var touch=game.touch_controls;touch.force_visible=true
		var press:=InputEventScreenTouch.new();press.index=44;press.pressed=true;press.position=invite_button.get_global_rect().get_center()
		touch.handle_touch(press)
		check(touch.owners.get(44,"")!="draw" and game.active_stroke==null,"touching room controls never starts drawing")
		var release:=InputEventScreenTouch.new();release.index=44;release.position=press.position
		touch.handle_touch(release)
		check(panel.invite_dialog.visible,"actual touch press/release opens invitation")
		press.index=45;press.position=Vector2(400,300)
		check(not touch.handle_touch(press) and touch.owners.get(45,"")=="native","invite modal routes touches to GUI")
		release.index=45;release.position=press.position;touch.handle_touch(release)
		panel.invite_dialog.confirmed.emit();panel.invite_dialog.hide()
		game.combat.health=75;session.local_protection=1
		panel._process(0)
		check(panel.connection.text.contains("75") and panel.connection.text.contains("保护"),"room HUD retains local health and protection")
		# A failed or uncertain leave must expose a working reconnect without losing drawing.
		session.is_owner=false;session.ended=false;session.ready_to_play=true
		session.save_and_return_to_selector("res://scenes/network_lobby.tscn")
		session._result({"op":"leave","seq":session.seq,"ok":false,"error":"fixture save failure"})
		for i in 4:await process_frame
		panel._process(0)
		check(not session.leaving and panel.retry_button.visible and not panel.retry_button.disabled,"failed leave offers draft-preserving retry")
		panel.retry_button.pressed.emit()
		check(not session.ended and game.draft.size()==1,"retry after failed leave actually reconnects and preserves draft")
		session.socket.close();session.socket=null
		session.ended=false;session.ready_to_play=true;session.leaving=false;session.leave_seq=-1
		session.return_to_selector("res://scenes/network_lobby.tscn",true)
		await create_timer(3.2).timeout
		panel._process(0)
		check(not session.leaving and not session.ready_to_play and panel.retry_button.visible,"leave timeout releases navigation and offers reconnect")
		check(game.draft.size()==1 and current_scene==game,"leave timeout retains current drawing and scene")
	game.network_session=null;session.free();game.free()
	print("ONLINE_SESSION: ",checks," checks, ",failed.size()," failures")
	quit(0 if failed.is_empty() else 1)
