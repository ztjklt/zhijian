extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(stage: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/paper-wall-climb-"+stage+".png")

func run() -> void:
	root.size = Vector2i(1280,720)
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	await process_frame
	game.player.position = Vector2(-0.65,game.GROUND_Y+0.4)
	var data := {"kind":"rectangle","source":"sculpt","role":"building","dynamic":true,"health":120.0,"max_health":120.0,"x":1.5,"y":game.GROUND_Y+1.04,
		"paths":[{"points":[Vector2(-1.5,-1),Vector2(1.5,-1),Vector2(1.5,1),Vector2(-1.5,1),Vector2(-1.5,-1)],"collision":true}]}
	game.objects.append(data)
	var body: RigidBody2D = game._build_physics_for_object(data)
	body.freeze = true
	game.object_nodes.append(body)
	for i in 15: await physics_frame
	await capture("start")
	Input.action_press("move_right")
	for i in 25: await physics_frame
	await capture("climbing")
	var reached := false
	for i in 140:
		await physics_frame
		if game.player.position.x > 0.4 and game.player.position.y > game.GROUND_Y+2.27:
			reached = true
			break
	Input.action_release("move_right")
	await capture("top")
	print("WALL VISUAL: reached top=",reached)
	quit(0 if reached else 1)
