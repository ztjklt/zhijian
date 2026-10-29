extends SceneTree
class CapturingSession extends PaperNetSession:
	var outgoing:Array=[]
	func _send(message:Dictionary)->void:outgoing.append(message.duplicate(true))
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL SAVE REQUEST: ",label)
func saves(session)->Array:return session.outgoing.filter(func(message):return message.get("op","")=="save")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false
	root.add_child(game);game.set_physics_process(false);game.combat.set_natives(false)
	var session:=CapturingSession.new();root.add_child(session);session.set_process(false)
	session.game=game;game.network_session=session;session.is_owner=true;session.epoch="room-A";session.world_id="world-A"
	session.syncing=true;session.ready_to_play=false
	game.draft=[{"points":[Vector2(1,2),Vector2(2,3)]}]
	var original:Array=game.draft.duplicate(true)
	game.save_game();game.save_game()
	check(saves(session).is_empty(),"save cannot be sent before Ready")
	check(game.toolbar.status_text.contains("保存"),"queued save gives visible save-specific feedback")
	session.syncing=false;session.tick(.1)
	check(saves(session).is_empty(),"snapshot completion alone is not the Ready acknowledgement")
	session._receive({"type":"ready","epoch":"room-A"})
	check(saves(session).size()==1,"pending user save is sent exactly once when Ready arrives")
	game.save_game()
	check(saves(session).size()==1,"repeated clicks while waiting for receipt do not enqueue more saves")
	var first:int=session.seq
	session._result({"op":"save","seq":first,"ok":false,"error":"存储不可写"})
	check(game.draft==original and not session.leaving,"failed save preserves source and current room")
	game.save_game();var second:int=session.seq
	check(saves(session).size()==2 and second>first,"explicit retry starts a new save only after failure")
	session._result({"op":"save","seq":first,"ok":true})
	check(not game.toolbar.status_text.contains("已保存"),"old receipt cannot claim that the newer in-flight save is complete")
	session.tick(3.1)
	check(game.draft==original and not session.leaving and game.toolbar.status_text.contains("确认"),"missing acknowledgement reports uncertainty without clearing source or leaving")
	session._result({"op":"save","seq":second,"ok":true})
	check(game.toolbar.status_text.contains("已保存") and not session.leaving,"matching late acknowledgement can confirm save without delayed navigation")
	session.ready_to_play=false;session.syncing=true;session.outgoing.clear();game.save_game()
	session._receive({"type":"world_changed","epoch":"room-B"})
	session._receive({"type":"ready","epoch":"room-B"})
	check(saves(session).is_empty(),"world replacement cancels old queued save instead of sending into a new epoch")
	session.is_owner=false;session.ready_to_play=true;session.outgoing.clear();game.save_game()
	check(saves(session).is_empty() and game.draft==original,"guest cannot queue an owner-only world save")
	session.is_owner=true;session.ready_to_play=false;session.syncing=true;session.outgoing.clear()
	game.save_game();session.seq=maxi(session.seq,42)
	session.pending[42]={"op":"equip","request":{"type":"command","op":"equip","seq":42,"epoch":session.epoch,"weapon":{}}}
	session.resend_pending=true;session.syncing=false
	session._receive({"type":"ready","epoch":session.epoch})
	var commands:Array=session.outgoing.filter(func(message):return message.get("type","")=="command")
	check(commands.size()==2 and commands[0].op=="equip" and commands[1].op=="save","reconnect replays older pending commands before allocating a newer save sequence")
	check(game.toolbar.status_text.contains("等待服务器确认"),"Ready room status cannot immediately hide in-flight save feedback")
	session._result({"op":"save","seq":session.seq,"ok":false,"error":"fixture reset"});session.pending.clear()
	session.ready_to_play=false;session.syncing=true;session.outgoing.clear();game.save_game();session.tick(10.1)
	check(saves(session).is_empty() and game.toolbar.status_text.contains("超时"),"Ready timeout never sends a save and explains retry")
	session.syncing=false;session._receive({"type":"ready","epoch":session.epoch})
	check(saves(session).is_empty(),"Ready arriving after queue timeout cannot silently save later")
	session.ready_to_play=false;session.syncing=false;session.outgoing.clear();session.token="fixture-reconnect"
	game.save_game();var queued_ticket:int=session.save_request.ticket
	session._disconnected();session._receive({"type":"ready","epoch":session.epoch})
	check(saves(session).size()==1 and session.save_request.ticket==queued_ticket,"unsent save survives a short same-world reconnect and sends once after Ready")
	var sent_seq:int=session.save_request.sequence;session._disconnected()
	check(session.save_request.completed[queued_ticket].unknown and game.draft==original,"disconnect after sending reports unknown outcome without clearing source")
	session._receive({"type":"ready","epoch":session.epoch})
	check(saves(session).size()==1,"reconnect does not automatically replay an already-sent uncertain save")
	session._result({"op":"save","seq":sent_seq,"ok":true})
	session.ready_to_play=false;session.outgoing.clear();game.save_game();session.world_id="different-world";session.tick(.1)
	session._receive({"type":"ready","epoch":session.epoch})
	check(saves(session).is_empty(),"world identity change also cancels queued save even if epoch text is unchanged")
	game.network_session=null;session.game=null;session.free();game.free();await process_frame
	print("NETWORK SAVE REQUEST: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
