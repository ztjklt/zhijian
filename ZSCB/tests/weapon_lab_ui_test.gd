extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL LAB UI: ",label)
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.player.position=Vector2.ZERO;game.combat.set_natives(false)
	var panel=game.get("weapon_lab_panel")
	check(panel!=null,"actual game contains a weapon experiment panel")
	if panel==null:game.queue_free();quit(1);return
	var weapon=PaperWeaponGrip.practice_sword();weapon.weapon_type="hammer";game.equipped_weapon=weapon
	game.set_draw_mode(2);game.toolbar.update_buttons();game.toolbar.lab_button.pressed.emit()
	check(panel.visible,"weapon toolbar button opens the actual panel")
	var old:Dictionary=game.equipped_weapon.duplicate(true)
	game.attack();check(game.combat.swing==0,"open panel blocks attack input")
	panel.buttons["start_1.2"].pressed.emit()
	check(game.weapon_lab.active and not panel.visible,"actual near-target action places target and returns to play")
	game.open_weapon_lab();panel.buttons["copy"].pressed.emit()
	check(not panel.visible and game.draw_mode==2 and game.draft.size()==weapon.paths.size(),"copy action returns complete ink to the real weapon drawing tool")
	check(game.equipped_weapon==old and not game.selecting_weapon_grip,"copy never replaces equipment or selects a grip automatically")
	var copied:Array=game.draft.duplicate(true)
	var delta:Vector2=copied[0].points[0]-weapon.paths[0].points[0]
	var preserved:=true
	for i in copied.size():
		for j in copied[i].points.size():
			if not copied[i].points[j].is_equal_approx(weapon.paths[i].points[j]+delta):preserved=false
	check(preserved,"all strokes share one translation without simplification or rotation")
	game.open_weapon_lab();panel.buttons["copy"].pressed.emit()
	check(panel.visible and game.draft==copied,"existing unfinished weapon draft is not overwritten")
	panel.close();game.generate()
	check(game.selecting_weapon_grip and game.selected_weapon_type=="hammer","copied model still enters grip selection and retains its type default")
	game.select_weapon_grip(game.draft[0].points[0]);game.generate();game.select_weapon_type("hammer");game.generate()
	check(game.equipped_weapon.get("model_fill",false)==old.get("model_fill",false),"copied weapon preserves its existing fill preference after normal re-equipment")
	game.cancel_weapon_grip(false)
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size;game.open_weapon_lab();game.touch_controls.force_visible=true
		for i in 4:await process_frame
		print("LAB UI RECT ",size," panel=",panel.panel.get_global_rect()," scale=",panel.scale," current=",panel.current_label.get_global_rect())
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(panel.panel.get_global_rect()),"whole panel stays in "+str(size))
		for key in ["start_1.2","keep","copy","close"]:
			var button=panel.buttons[key]
			check(button.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),key+" remains reachable at "+str(size))
		var touch:=InputEventScreenTouch.new();touch.index=94;touch.pressed=true;touch.position=panel.buttons["copy"].get_global_rect().get_center()
		game.touch_controls.handle_touch(touch)
		check(game.touch_controls.owners.get(94,"")!="stick" and game.touch_controls.owners.get(94,"")!="attack" and game.active_stroke==null,"modal touch avoids movement/attack/painting at "+str(size))
		touch.pressed=false;touch.canceled=true;game.touch_controls.handle_touch(touch)
		panel.close()
	game.queue_free();await process_frame
	print("WEAPON LAB UI: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
