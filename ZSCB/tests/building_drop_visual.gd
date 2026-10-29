extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(file: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	await process_frame
	game.set_draw_mode(3)
	game.set_physics_process(false)
	game.flip_timer = 0
	game.camera_x = 0
	game.player.freeze = true
	game.player.position = Vector2(-6.6, game.GROUND_Y + 0.5)
	var flat := [Vector2(-1, -0.3), Vector2(1, -0.3), Vector2(1, 0.3), Vector2(-1, 0.3), Vector2(-1, -0.3)]
	var sloped := [Vector2(-1, 0.9), Vector2(1, 0.9), Vector2(0.8, -0.9), Vector2(-1, 0.9)]
	var curved: Array = []
	for i in range(33):
		var angle := PI + PI * i / 32.0
		curved.append(Vector2(cos(angle), sin(angle)))
	curved.append(curved[0])
	for index in range(3):
		var object: Dictionary = DrawingRules.building([{"points": [flat, sloped, curved][index]}], "freehand")
		object.x = [-4, 0, 4][index]
		object.y = game.GROUND_Y + 3.4
		object.angle = 0.4 if index == 2 else 0
		game.objects.append(object)
		game.object_nodes.append(game._build_physics_for_object(object))
	var hud := CanvasLayer.new()
	game.add_child(hud)
	var time_label := Label.new()
	time_label.position = Vector2(34, 112)
	time_label.add_theme_font_size_override("font_size", 21)
	time_label.add_theme_color_override("font_color", Color("376f65"))
	hud.add_child(time_label)
	for i in range(3):
		var caption := Label.new()
		caption.text = ["平底 · 稳定支撑", "斜底 · 自然倾倒", "弯底 · 滚动与摆动"][i]
		caption.position = Vector2([270, 565, 865][i], 155)
		caption.add_theme_font_size_override("font_size", 20)
		caption.add_theme_color_override("font_color", Color("303941"))
		hud.add_child(caption)
	var start_frame := Engine.get_physics_frames()
	var sequence: Array = []
	var next_capture := 0
	var milestone := 0
	var milestones := [0, 24, 48, 96, 192]
	DirAccess.make_dir_recursive_absolute("/tmp/paper-building-drop-sequence")
	while Engine.get_physics_frames() - start_frame < 193:
		await physics_frame
		game.sync_objects()
		var frame := Engine.get_physics_frames() - start_frame
		time_label.text = "Godot 2D 刚体实测 · %.2f 秒" % (float(frame) / Engine.physics_ticks_per_second)
		if frame >= next_capture or frame >= 192:
			var file := "/tmp/paper-building-drop-sequence/%03d.png" % sequence.size()
			await capture(file)
			sequence.append({"file": file, "frame": frame})
			next_capture = frame + 3
			if milestone < milestones.size() and frame >= milestones[milestone]:
				DirAccess.copy_absolute(file, "/tmp/paper-building-drop-%03d.png" % milestones[milestone])
				milestone += 1
	var manifest := FileAccess.open("/tmp/paper-building-drop-sequence/frames.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify(sequence))
	manifest.close()
	print("BUILDING DROP VISUAL COMPLETE")
	game.queue_free()
	quit()
