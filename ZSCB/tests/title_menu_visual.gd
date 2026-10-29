extends SceneTree
const OUT := "/Users/jitian/Documents/ChatGPT/纸上城堡/logs/cover-ui-2026-10-24/"
func _init() -> void: call_deferred("run")
func frames() -> void:
	for i in range(8): await process_frame
func shot(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var menu=load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(menu); current_scene=menu
	for dimensions in [Vector2i(1280,720),Vector2i(960,540),Vector2i(844,390),Vector2i(390,844)]:
		root.size=dimensions
		await shot("cover-%dx%d" % [dimensions.x,dimensions.y])
		menu.buttons.settings.pressed.emit()
		await shot("settings-%dx%d" % [dimensions.x,dimensions.y])
		menu.settings_panel.close_button.pressed.emit()
	menu.buttons.practice.pressed.emit()
	await frames()
	for dimensions in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
		root.size=dimensions
		await shot("maps-%dx%d" % [dimensions.x,dimensions.y])
	root.size=Vector2i(1280,720)
	current_scene.start_map("medieval-v1")
	await frames()
	current_scene.onboarding.persist=false; current_scene.onboarding.dismiss()
	await shot("game-medieval")
	current_scene.toolbar.works.show_popup()
	await shot("game-works-menu")
	current_scene.toolbar.works.get_popup().hide()
	current_scene.return_to_map_select("res://scenes/title_menu.tscn")
	await frames()
	current_scene.buttons.multiplayer.pressed.emit()
	await frames()
	for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
		root.size=dimensions
		await shot("lobby-%dx%d" % [dimensions.x,dimensions.y])
	current_scene._return_to_title()
	await frames()
	current_scene.free()
	var holder=root.get_node_or_null("MapSessions")
	if holder!=null: holder.free()
	print("COVER UI VISUAL: screenshots saved ",OUT)
	quit()
