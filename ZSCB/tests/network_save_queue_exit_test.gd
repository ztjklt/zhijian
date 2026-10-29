extends SceneTree
class CapturingSession extends PaperNetSession:
	var outgoing:Array=[]
	func _send(message:Dictionary)->void:outgoing.append(message.duplicate(true))
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL QUEUED SAVE EXIT: ",label)
func _initialize()->void:call_deferred("run")
func frames()->void:
	for i in 4:await process_frame
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);current_scene=game;game.set_physics_process(false);game.combat.set_natives(false)
	var session:=CapturingSession.new();root.add_child(session);session.set_process(false)
	session.game=game;game.network_session=session;session.is_owner=true;session.epoch="save-exit";session.world_id="world"
	game.draft=[{"points":[Vector2(1,2),Vector2(2,3)]}]
	game.save_game();var ticket:int=session.save_request.ticket
	game.save_and_return_to_title();game.save_and_return_to_title()
	check(session.save_request.ticket==ticket and session.save_exit_pending,"manual queued save and repeated save-return join the same pending request")
	session._receive({"type":"ready","epoch":session.epoch})
	var saves:Array=session.outgoing.filter(func(message):return message.get("op","")=="save")
	check(saves.size()==1,"queued save-return issues one real save when ready")
	session._result({"op":"save","seq":session.save_request.sequence,"ok":false,"error":"fixture write failure"});await frames()
	check(current_scene==game and not session.save_exit_pending and game.draft.size()==1,"joined save-return failure stays with original draft and permits retry")
	game.save_game();game.save_and_return_to_title()
	session._result({"op":"save","seq":session.save_request.sequence,"ok":true});await frames()
	check(session.leaving and current_scene==game,"save success still waits for actual leave acknowledgement")
	session._result({"op":"leave","seq":session.seq,"ok":false,"error":"fixture close failure"});await frames()
	check(current_scene==game and game.draft.size()==1,"leave failure cannot discard source after a joined successful save")
	session.ended=false;session.ready_to_play=true;session.leaving=false;session.leave_seq=-1
	game.save_and_return_to_title();var late_seq:int=session.save_request.sequence
	session.save_request.step(session,3.1)
	session._result({"op":"save","seq":late_seq,"ok":true});await frames()
	check(current_scene==game and not session.leaving and not session.navigation_pending,"timeout completion is immutable even when a late success arrives before the exit waiter resumes")
	check(game.toolbar.status_text.contains("已保存"),"late matching success can still update confirmation feedback without navigation")
	game.network_session=null;session.game=null;session.free();game.free();await process_frame
	print("NETWORK QUEUED SAVE EXIT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
