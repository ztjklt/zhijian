extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL WEB SAVE FEEDBACK: ",label)
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);game.set_physics_process(false);game.combat.set_natives(false)
	var session:=PaperNetSession.new();root.add_child(session);session.set_process(false)
	session.game=game;game.network_session=session;session.is_owner=true;session.ready_to_play=true;session.epoch="feedback";session.world_id="world"
	var panel=load("res://scripts/net/online_panel.gd").new();panel.session=session;game.add_child(panel)
	game.save_game();var first:int=session.save_request.sequence
	session._result({"op":"save","seq":first,"ok":false,"error":"存储不可写"})
	check(panel.notice.text.contains("存储不可写"),"actual save failure reaches the Web notice")
	game.save_game();var next:int=session.save_request.sequence
	session._result({"op":"save","seq":first,"ok":true})
	check(not panel.notice.text.contains("已保存") and panel.notice.text.contains("确认"),"late old success cannot replace current Web saving notice")
	session._result({"op":"save","seq":next,"ok":true})
	check(panel.notice.text.contains("已保存"),"matching success still confirms to the Web player")
	session.ready_to_play=false;session.syncing=true
	var save_button:Button=null
	for child in panel.menu.get_children():
		if child is Button and child.text=="保存云端世界":save_button=child;break
	check(save_button!=null,"actual Web room-menu save button is present")
	var before:int=session.save_request.ticket
	if save_button!=null:save_button.pressed.emit()
	check(session.save_request.ticket==before+1 and session.save_request.phase=="waiting","actual Web room-menu click queues current session save during sync")
	check(panel.notice.text.contains("等待") and not panel.notice.text.contains("已保存"),"Web queued save displays waiting rather than false completion")
	game.network_session=null;session.game=null;session.free();game.free();await process_frame
	print("WEB SAVE FEEDBACK: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
