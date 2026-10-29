extends SceneTree

func _init() -> void: call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 1080)
	var panel := Control.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper := ColorRect.new()
	paper.color = Color("faf7eb")
	paper.size = Vector2(1440,1080)
	panel.add_child(paper)
	var names := ["oak", "house", "market", "wall", "tower", "gate", "pine", "barrel", "crate", "wagon", "villager", "horse", "dragon", "driver"]
	for i in names.size():
		var path: String = "res://assets/medieval/" + names[i] + ".png"
		if not FileAccess.file_exists(path): continue
		var sprite := TextureRect.new()
		sprite.texture = load(path)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.position = Vector2((i % 4) * 360 + 15, (i / 4) * 260 + 30)
		sprite.size = Vector2(330,220)
		panel.add_child(sprite)
		var title := Label.new()
		title.text = names[i]
		title.position = Vector2((i % 4) * 360 + 20, (i / 4) * 260 + 6)
		title.add_theme_color_override("font_color", Color("282826"))
		panel.add_child(title)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "/tmp/paper-medieval-review"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join("art-contact-sheet.png"))
	print("ART CONTACT SHEET CAPTURED")
	quit()
