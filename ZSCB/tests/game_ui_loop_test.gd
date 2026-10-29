extends SceneTree
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("UI LOOP: " + label)
func frames() -> void:
	for i in range(4): await process_frame
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new(); move.position=point
	Input.parse_input_event(move)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position=point; press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true
	Input.parse_input_event(press)
	await process_frame
	press=press.duplicate(); press.pressed=false
	Input.parse_input_event(press)
	await frames()
func run() -> void:
	root.size=Vector2i(1280,720)
	if not ResourceLoader.exists("res://scenes/title_menu.tscn"):
		check(false,"cover scene exists"); quit(1); return
	var menu=load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(menu); current_scene=menu
	await frames()
	await click(menu.buttons.practice)
	check(current_scene.scene_file_path=="res://scenes/map_select.tscn","real mouse click enters solo maps")
	var selector=current_scene
	var start: Button=selector.cards.get_child(1).find_children("*","Button",true,false)[0]
	await click(start)
	var game=current_scene
	check(game is PaperCastleMain and game.world_kind=="knowledge-v1","real map button starts current game")
	game.onboarding.persist=false; game.onboarding.dismiss(); game.combat.set_natives(false)
	game.set_physics_process(false); game.player.freeze=true
	await click(game.toolbar.mode_buttons[1])
	check(game.draw_mode==3,"building toolbar click activates building")
	var p: Vector2=game.player.position+Vector2(2,2)
	game.pointer_down(game.world_to_screen(p))
	game.pointer_move(game.world_to_screen(p+Vector2(1,0)))
	game.pointer_up(game.world_to_screen(p+Vector2(1,0)))
	await frames()
	await click(game.toolbar.generate_button)
	check(game.objects.size()==1 and game.draft.is_empty(),"confirm button creates actual object")
	await click(game.toolbar.undo_button)
	check(game.objects.is_empty(),"undo removes created object")
	await click(game.toolbar.redo_button)
	check(game.objects.size()==1,"redo restores created object")
	await click(game.toolbar.bag_button)
	check(game.bag_open,"blueprints opens by mouse")
	game.toggle_bag()
	game.experience.open()
	var sword: Button
	for child in game.experience.actions.get_children():
		if child.text.contains("试用短剑"): sword=child
	await frames()
	game.experience.scroll.ensure_control_visible(sword)
	await frames()
	await click(sword)
	check(not game.experience.visible and not game.equipped_weapon.is_empty(),"trial button equips real sword and closes panel")
	game.combat.attack(Vector2.RIGHT)
	check(game.combat.swing>0,"equipped sword actually attacks")
	# A real file-open failure must keep the player in the game.
	DirAccess.make_dir_absolute(SaveStore.SAVE_PATH + ".tmp")
	game.save_and_return_to_title()
	await frames()
	check(current_scene==game and game.toolbar.status_text.contains("无法打开"),"save failure stays in game and reports failure")
	DirAccess.remove_absolute(SaveStore.SAVE_PATH + ".tmp")
	game.draft=[{"points":[p,p+Vector2(1,1)]}]
	game.mode_drafts[3]=game.draft
	var popup: PopupMenu=game.toolbar.works.get_popup()
	check(popup.get_item_index(9)>=0,"works menu offers save and return")
	if popup.get_item_index(9)<0:
		game.free(); quit(1); return
	popup.id_pressed.emit(9)
	await frames()
	check(current_scene.scene_file_path=="res://scenes/title_menu.tscn","save and return reaches cover")
	check(SaveStore.load_game().error.is_empty(),"save and return writes a valid world")
	check(is_instance_valid(game) and game.draft.size()==1 and not game.is_processing(),"return preserves unfinished draft in dormant session")
	check(not game.get_node("VisualQuality").visible,"dormant world's shader stays hidden on cover")
	await click(current_scene.buttons.practice)
	await click(current_scene.continue_buttons["knowledge-v1"])
	check(current_scene==game and game.objects.size()==1 and game.draft.size()==1,"continue restores exact world and draft")
	check(game.get_node("VisualQuality").visible,"continue reapplies saved world quality")
	game.toolbar.works.get_popup().id_pressed.emit(8)
	await frames()
	check(current_scene.scene_file_path=="res://scenes/title_menu.tscn","plain return also reaches cover")
	# Simulate a fresh process by releasing dormant memory, then read from disk.
	root.get_node("MapSessions").free()
	await click(current_scene.buttons.practice)
	await click(current_scene.continue_buttons["knowledge-v1"])
	game=current_scene
	check(game is PaperCastleMain and game.objects.size()==1 and not game.equipped_weapon.is_empty(),"disk reload restores building and equipped weapon")
	game.free()
	print("GAME UI LOOP: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
