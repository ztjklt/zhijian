extends SceneTree
## Real renderer evidence for the integrated map selector and terrain clearance.

const FOLDER := "/tmp/paper-playtest-refinement"

func _init() -> void: call_deferred("run")

func shot(name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FOLDER.path_join(name + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	var menu = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(menu)
	await shot("01-map-select")
	menu.queue_free()
	await process_frame
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.feedback.audio_enabled = false
	game.combat.set_natives(false)
	game.set_physics_process(false)
	game.player.freeze = true
	game.knowledge_world.visit(1)
	game.player.position = Vector2(28,2)
	game.camera_x = 29
	game.camera_y = game.camera_target_y()
	game.set_draw_mode(3)
	game.draft = [{"points": [Vector2(29.5,4.35),Vector2(30.5,4.35),Vector2(30.5,5.35),Vector2(29.5,5.35),Vector2(29.5,4.35)]}]
	for i in range(3): await physics_frame
	await shot("02-ink-through-poem")
	game.release_building()
	assert(game.object_nodes.size() == 1, "real building action succeeds across a poem line")
	assert(game.object_nodes[0].get_meta("spawn_adjusted", false))
	game.object_nodes[0].freeze = true
	game.feedback.events.clear()
	await shot("03-building-cleared")
	game.change_map("nature-v1")
	game.player.freeze = true
	game.player.position = Vector2(20,6.49)
	game.camera_x = 20
	game.camera_y = game.camera_target_y()
	await shot("04-natural-alternative")
	game.change_map("knowledge-v1")
	game.player.freeze = true
	game.player.position = Vector2(4,14.29)
	game.camera_x = 4
	game.camera_y = game.camera_target_y()
	await shot("05-sky-route")
	game.queue_free()
	for i in range(3): await process_frame
	print("PLAYTEST REFINEMENT VISUAL: selector, real poem clearance, natural alternative, sky route")
	quit()
