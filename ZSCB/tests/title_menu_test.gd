extends SceneTree
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("TITLE UI: " + label)
func frames() -> void:
	for i in range(5): await process_frame
func button(node: Node, text: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if child.text == text: return child
	return null
func run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/title_menu.tscn", "normal launch opens the approved cover")
	if not ResourceLoader.exists("res://scenes/title_menu.tscn"):
		check(false, "approved cover is integrated as a real scene")
		print("TITLE UI: ", checks, " checks, ", failures.size(), " failures"); quit(1); return
	var menu = load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(menu); current_scene = menu
	await frames()
	for window_size in [Vector2i(1280,720),Vector2i(960,540),Vector2i(844,390),Vector2i(390,844)]:
		root.size = window_size
		await frames()
		for key in ["practice","multiplayer","settings"]:
			var action: BaseButton = menu.buttons[key]
			check(Rect2(Vector2.ZERO,Vector2(window_size)).encloses(action.get_global_rect()), key+" fits "+str(window_size))
			check(action.pressed.get_connections().size()>0, key+" has an action")
	menu.buttons.settings.pressed.emit()
	await frames()
	check(menu.settings_panel.visible,"settings opens from cover")
	var settings = menu.settings_panel
	settings.volume.value = 37
	settings.antialias.button_pressed = false
	settings.sharpen.button_pressed = false
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.37)),"volume actually changes audio bus")
	check(root.msaa_2d == Viewport.MSAA_DISABLED,"antialias control changes viewport")
	check(FileAccess.file_exists("user://preferences.cfg"),"preferences persist independently of works")
	settings.close_button.pressed.emit()
	menu.buttons.practice.pressed.emit()
	await frames()
	check(current_scene.scene_file_path == "res://scenes/map_select.tscn","single player opens real map selector")
	var back := button(current_scene,"返回封面")
	check(back!=null,"selector has return to cover")
	if back != null: back.pressed.emit(); await frames()
	check(current_scene.scene_file_path == "res://scenes/title_menu.tscn","map selector returns to cover")
	current_scene.buttons.settings.pressed.emit(); await frames()
	check(current_scene.settings_panel.volume.value == 37 and not current_scene.settings_panel.antialias.button_pressed,"settings survive scene changes")
	current_scene.settings_panel.close_button.pressed.emit()
	current_scene.buttons.multiplayer.pressed.emit(); await frames()
	check(current_scene.scene_file_path == "res://scenes/network_lobby.tscn","multiplayer opens actual lobby")
	back = button(current_scene,"返回封面")
	check(back != null,"online lobby has a cover return")
	if back != null: back.pressed.emit(); await frames()
	check(current_scene.scene_file_path == "res://scenes/title_menu.tscn","lobby returns to cover")
	check(auto_accept_quit,"leaving lobby releases close-request ownership")
	current_scene.buttons.practice.pressed.emit(); await frames()
	current_scene.start_map("knowledge-v1"); await frames()
	var game = current_scene
	game.onboarding.persist = false
	game.combat.set_natives(false)
	check(not game.get_node("VisualQuality").visible and root.msaa_2d == Viewport.MSAA_DISABLED,"saved settings apply inside the actual game")
	game.return_to_map_select("res://scenes/title_menu.tscn"); await frames()
	current_scene.buttons.settings.pressed.emit(); await frames()
	current_scene.settings_panel.sharpen.button_pressed = true
	check(not game.get_node("VisualQuality").visible,"settings never re-enable a dormant world's shader over cover")
	current_scene.settings_panel.close_button.pressed.emit()
	current_scene.buttons.practice.pressed.emit(); await frames()
	current_scene.continue_buttons["knowledge-v1"].pressed.emit(); await frames()
	check(current_scene == game and game.get_node("VisualQuality").visible,"resuming reapplies the changed sharpening preference")
	current_scene.free()
	var holder := root.get_node_or_null("MapSessions")
	if holder != null: holder.free()
	print("TITLE UI: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
