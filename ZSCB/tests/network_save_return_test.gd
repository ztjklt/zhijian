extends SceneTree
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error("SAVE RETURN: "+label)
func frames() -> void:
	for i in range(5): await process_frame
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game); current_scene=game
	game.combat.set_natives(false)
	var session=PaperNetSession.new()
	root.add_child(session)
	session.game=game; game.network_session=session
	session.ready_to_play=true; session.is_owner=true; session.epoch="check"
	game.draft=[{"points":[Vector2(1,2),Vector2(2,3)]}]
	game.save_and_return_to_title()
	# Feed the actual protocol failure; the client must keep the scene after its deadline.
	session._result({"op":"save","seq":session.seq,"ok":false,"error":"存储不可写，原作品保留"})
	await create_timer(3.2).timeout
	check(current_scene==game and is_instance_valid(game),"failed server save never destroys current game")
	if current_scene!=game:
		current_scene.free()
		if is_instance_valid(session):session.free()
		print("SAVE RETURN: ",checks," checks, ",failures.size()," failures");quit(1);return
	check(game.draft.size()==1 and game.toolbar.status_text.contains("存储不可写"),"failed save keeps draft and visible reason")
	check(not session.leaving,"save failure does not close the room")
	# With no acknowledgement, stay and give an explicit timeout, even on repeated clicks.
	game.save_and_return_to_title()
	var first_seq: int=session.seq
	game.save_and_return_to_title()
	check(session.seq==first_seq,"repeated clicks do not enqueue multiple exits")
	await create_timer(3.2).timeout
	check(current_scene==game and game.toolbar.status_text.contains("确认"),"missing save acknowledgement keeps game and explains uncertainty")
	# A saved world still needs a successful leave acknowledgement before navigation.
	game.save_and_return_to_title()
	session._result({"op":"save","seq":session.seq,"ok":true})
	await frames()
	check(session.leaving,"successful save proceeds to real room leave")
	session._result({"op":"leave","seq":session.seq,"ok":false,"error":"关房保存失败"})
	await frames()
	check(current_scene==game and game.draft.size()==1 and game.toolbar.status_text.contains("关房保存失败"),"leave failure stays with draft and reason")
	# Recreate a live connection state, then acknowledge both steps successfully.
	session.ended=false;session.ready_to_play=true;session.leaving=false;session.leave_seq=-1
	game.save_and_return_to_title()
	session._result({"op":"save","seq":session.seq,"ok":true})
	await frames()
	session._result({"op":"leave","seq":session.seq,"ok":true})
	await frames()
	check(current_scene.scene_file_path=="res://scenes/title_menu.tscn","confirmed save and leave reaches cover")
	current_scene.free()
	game=load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game); current_scene=game
	game.combat.set_natives(false)
	session=PaperNetSession.new(); root.add_child(session)
	session.game=game;game.network_session=session
	session.is_owner=false;session.ready_to_play=true;session.epoch="guest"
	game.save_and_return_to_title()
	check(session.leaving,"guest saves personal profile and leaves without owner-only world save")
	session._result({"op":"leave","seq":session.seq,"ok":true})
	await frames()
	check(current_scene.scene_file_path=="res://scenes/title_menu.tscn","guest confirmed leave reaches cover")
	current_scene.free()
	print("SAVE RETURN: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
