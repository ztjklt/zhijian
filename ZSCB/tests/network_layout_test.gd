extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/sandbox.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false); game.combat.set_natives(false)
	var world=game.knowledge_world
	if not world.has_method("apply_network_layout"):
		print("FAIL: 服务器课本地形尚未传到客户端"); quit(1); return
	var layout={"paths":[{"points":[Vector2(1,8),Vector2(4,8)],"one_way":true}],"rows":[{"text":"纸上城堡","p":Vector2(1,7),"w":3.0,"h":1.0,"size":28,"role":"body","color":Color.BLACK,"fit":false}],"raised":[{"position":Vector2(1,6),"size":Vector2(3,2)}],"sky":[]}
	layout=PaperNetCodec.decode(PaperNetCodec.encode(layout))
	world.apply_network_layout(layout)
	if world.text_rows[0].w!=3 or not world.text_rows[0].fit or world.paths[0].points[-1]!=Vector2(4,8) or world.raised_tiers[0].size!=Vector2(3,2):
		print("FAIL: 客户端未采用服务端文字/碰撞尺寸"); quit(1); return
	game.queue_free(); await process_frame
	print("NETWORK_LAYOUT_TEST: PASS")
	quit()
