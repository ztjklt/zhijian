extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.title = "纸上城堡 · 界面验收"
	for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = viewport_size
		var game = load("res://scenes/main.tscn").instantiate()
		game.onboarding.persist = false
		game.onboarding.restart(false)
		root.add_child(game)
		await process_frame
		game.toolbar._layout()
		game.backpack_panel._layout()
		await capture("/tmp/paper-castle-ui-%d.png" % viewport_size.x)
		game.toggle_bag()
		await capture("/tmp/paper-castle-bag-%d.png" % viewport_size.x)
		game.queue_free()
		await process_frame
	root.size = Vector2i(1120, 380)
	var backdrop := ColorRect.new()
	backdrop.color = Color("faf7eb")
	backdrop.size = Vector2(1120, 380)
	root.add_child(backdrop)
	var title := Label.new()
	title.text = "纸上城堡 · 小小造城师"
	title.position = Vector2(32, 22)
	title.add_theme_color_override("font_color", Color("303941"))
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)
	var clips := ["idle", "walk", "jump", "fall", "land", "climb", "draw"]
	var captions := ["呼吸待机", "向前走", "起跳", "下落", "落地缓冲", "攀爬", "挥笔创作"]
	for i in clips.size():
		var rig = load("res://scenes/character.tscn").instantiate()
		root.add_child(rig)
		await process_frame
		await process_frame
		rig.position = Vector2(90 + i * 156, 230)
		rig.scale = Vector2(2.3, 2.3)
		var animator: AnimationPlayer = rig.get_node("AnimationPlayer")
		animator.play(clips[i], 0)
		animator.seek(animator.current_animation_length * 0.32, true)
		animator.advance(0)
		animator.pause()
		rig.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/Pencil").visible = clips[i] == "draw"
		var caption := Label.new()
		caption.text = captions[i]
		caption.position = Vector2(30 + i * 156, 306)
		caption.size.x = 120
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_color", Color("66746b"))
		caption.add_theme_font_size_override("font_size", 17)
		root.add_child(caption)
	await capture("/tmp/paper-castle-character-poses.png")
	print("VISUAL SMOKE COMPLETE")
	quit()
