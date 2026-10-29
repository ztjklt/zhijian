extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://scripts/net/session.gd"):
		print("FAIL: 电脑客户端尚未接入网络状态")
		quit(1)
		return
	var session = load("res://scripts/net/session.gd").new()
	root.add_child(session)
	session.player_id = "self"
	session.epoch = "test"
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	session.game = game
	game.network_session = session
	game.combat.set_natives(false)
	var object := {"id":"1","author":"friend","version":1,"health":120.0,"kind":"freehand","x":2.0,"y":0.0,"dynamic":true,"paths":[{"points":[Vector2.ZERO,Vector2(1,0)],"collision":true}]}
	game.active_stroke={"points":[Vector2(1,1),Vector2(2,1)]}
	session.apply_snapshot({"epoch":"test","revision":1,"world_kind":"paper","objects":[object],"world":{},"actors":[]})
	session.apply_frame({"epoch":"test","tick":1,"revision":1,"bodies":[{"id":"1","position":Vector2(3,1),"angle":.2,"health":120,"version":1}],"actors":[{"id":"self","name":"我","position":Vector2(-2,-2),"velocity":Vector2.ZERO,"facing":1,"pose":"idle","weapon":{},"health":100,"connected":true},{"id":"friend","name":"朋友","position":Vector2(5,-2),"velocity":Vector2.ZERO,"facing":-1,"pose":"idle","weapon":{},"health":80,"connected":true}],"entities":[]})
	if game.active_stroke==null:
		print("FAIL: 朋友同步丢弃了当前未松手笔画"); quit(1); return
	if game.objects.size()!=1 or not game.object_nodes[0].freeze or not session.remotes.has("friend"):
		print("FAIL: 同一实体与远端玩家显示错误"); quit(1); return
	session.apply_frame({"epoch":"wrong","tick":200,"revision":1,"bodies":[],"actors":[],"entities":[]})
	if game.objects.size()!=1: print("FAIL: 旧世界消息污染当前世界"); quit(1); return
	game.queue_free(); session.queue_free()
	await process_frame
	print("NETWORK_CLIENT_TEST: PASS")
	quit()
