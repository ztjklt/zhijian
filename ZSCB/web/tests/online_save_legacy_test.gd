extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL LEGACY SAVE UI: ",label)
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);game.set_physics_process(false);game.combat.set_natives(false)
	var session:=PaperNetSession.new();root.add_child(session);session.set_process(false)
	session.game=game;game.network_session=session;session.is_owner=true
	var panel=load("res://scripts/net/online_panel.gd").new();panel.session=session;game.add_child(panel)
	check(not session.has_method("save_feedback"),"fixture is actually a legacy session without queued-save capability")
	var before:int=session.seq;panel.request_save()
	check(session.seq==before and panel.notice.text.contains("不能确认"),"legacy unready session retains original readiness guard")
	session.ready_to_play=true;panel.request_save()
	check(session.seq==before+1,"legacy ready session still issues its normal save")
	session._result({"op":"save","seq":session.seq,"ok":true})
	check(panel.notice.text.contains("已保存"),"legacy success still uses its original acknowledgement notice")
	game.network_session=null;session.game=null;session.free();game.free();await process_frame
	print("LEGACY SAVE UI: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
