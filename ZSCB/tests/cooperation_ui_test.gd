extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL COOP UI: ",label)
func run()->void:
	root.content_scale_size=Vector2i.ZERO
	for scene in ["sandbox","medieval"]:
		var game=load("res://scenes/"+scene+".tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
		game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false)
		var panel=game.get("cooperation_panel")
		check(panel!=null,"actual core creates a cooperation panel")
		if panel==null:game.queue_free();quit(1);return
		var ink=[{"points":[Vector2(1,2),Vector2(2,3)]}];game.draft=ink.duplicate(true)
		game.toolbar.works.get_popup().id_pressed.emit(11);await process_frame
		check(panel.visible and game.personal_overlay_open(),"actual works entry opens protected modal")
		check(panel.notice_label.text.contains("双人房间") and panel.share_button.disabled,"single player clearly explains online use")
		check(panel.list.get_theme_color("font_color").is_equal_approx(PaperTheme.INK),"piece list uses readable ink on the paper theme")
		var previous:Vector2=game.player.position
		for value in [KEY_M,KEY_HOME,KEY_TAB,KEY_3]:
			var event:=InputEventKey.new();event.keycode=value;event.physical_keycode=value;event.pressed=true;Input.parse_input_event(event);await process_frame;await process_frame
			event.pressed=false;Input.parse_input_event(event);await process_frame
			check(panel.visible and game.player.position.is_equal_approx(previous),"modal isolates actual map and tool key "+str(value))
		check(game.draft==ink and game.active_stroke==null,"opening and keys retain original full draft")
		if scene=="sandbox":check(not game.knowledge_world.overview,"modal blocks map overview")
		for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
			root.size=size
			for i in 8:await process_frame
			var viewport:=Rect2(Vector2.ZERO,Vector2(size))
			for button in [panel.close_button,panel.share_button,panel.build_button]:
				check(viewport.encloses(button.get_global_rect()) and button.size.y>=34,"actual button reachable at "+str(size))
		panel.build_button.pressed.emit();await process_frame
		check(not panel.visible and game.draw_mode==4 and game.mode_drafts.get(1,[])==ink,"return to actual4tool preserves earlier drawing")
		game.open_cooperation();await process_frame
		game.touch_controls.force_visible=true
		var touch:=InputEventScreenTouch.new();touch.index=3;touch.pressed=true;touch.position=panel.close_button.get_global_rect().get_center()
		game.touch_controls.handle_touch(touch);touch.pressed=false;game.touch_controls.handle_touch(touch)
		check(not panel.visible and game.touch_controls.stick==Vector2.ZERO,"real touch closes panel without joystick or ink")
		game.queue_free();await process_frame
	print("COOP UI: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
