extends "res://tests/structure_links_test.gd"
class RecordingSession extends PaperNetSession:
	var sent:Array=[]
	func _send(message:Dictionary)->void:sent.append(message.duplicate(true))
func click(point:Vector2)->void:
	game.pointer_down(game.world_to_screen(point));game.pointer_up(game.world_to_screen(point))
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false)
	block("one",Vector2.ZERO,[Vector2(-1,0),Vector2(0,0)],false)
	block("two",Vector2.ZERO,[Vector2(.1,0),Vector2(1,0)],true)
	var session:=RecordingSession.new();root.add_child(session);session.set_process(false)
	session.game=game;session.player_id="author";game.network_session=session
	for i in game.objects.size():game.objects[i].id=str(i+1);game.objects[i].version=1;game.objects[i].author="author"
	game.set_draw_mode(4);game.set_connection_tool("fixed")
	session.ready_to_play=true;click(Vector2(-.12,0))
	var anchor:Dictionary=game.connection_source.duplicate(true)
	check(not anchor.is_empty(),"first actual pointer chooses material anchor while ready")
	session.ready_to_play=false;click(Vector2(.15,0))
	check(session.sent.is_empty() and session.seq==0,"resync never sends a connection")
	check(game.connection_source==anchor,"resync click retains the unsent first anchor")
	check(game.toolbar.status_text.contains("同步") and not game.toolbar.status_text.contains("等待服务器确认连接"),"rejected click explains synchronization instead of inventing a pending request")
	session.ready_to_play=true
	check(session.sent.is_empty(),"Ready alone does not automatically replay an old connection")
	click(Vector2(.15,0))
	check(session.sent.size()==1 and session.sent[0].op=="structure_link","explicit retry after Ready sends exactly one real connection intent")
	check(game.connection_source.is_empty() and game.structure_links.records.is_empty(),"accepted intent clears anchors but creates no local authoritative joint")
	# Direct callers must preserve the rejection too, including unlink actions.
	session.ready_to_play=false;game.connection_action({"action":"unlink","id":"known-link"})
	check(session.sent.size()==1 and game.toolbar.status_text.contains("同步"),"direct unlink rejection retains the readiness feedback")
	var sync_rules=load("res://tests/cooperation_bot.gd")
	check(sync_rules.has_method("undo_visible"),"cooperation fixture checks actual undo visibility instead of a fixed sleep")
	if sync_rules.has_method("undo_visible"):
		session.ready_to_play=true;session.syncing=false
		var body:RigidBody2D=game.object_nodes[0]
		session.targets["1"]={"position":body.position,"angle":body.rotation}
		var expected:Dictionary={"id":"1","version":3}
		check(not sync_rules.undo_visible(session,expected),"old Ready with a stale object version cannot start the next shared operation")
		game.objects[0].version=3;session.syncing=true
		check(not sync_rules.undo_visible(session,expected),"received undo body still waits for completed resync")
		session.syncing=false;body.position+=Vector2(.4,0)
		check(not sync_rules.undo_visible(session,expected),"interpolating moved replica cannot masquerade as restored material")
		body.position=session.targets["1"].position
		check(sync_rules.undo_visible(session,expected),"current version, Ready and actual settled replica permit the next explicit operation")
	game.network_session=null;session.game=null;session.free();game.free();await process_frame
	print("CONNECTION READINESS: ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
