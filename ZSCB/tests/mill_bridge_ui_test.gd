extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL MILL UI: ",label)
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	var game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	game.set_physics_process(false);game.player.freeze=true
	var controls=game.map_controls
	var button=controls.get("trial_button")
	check(button!=null,"map controls expose a real optional-event action")
	if button!=null:
		game.draft=[{"points":[Vector2(1,2),Vector2(2,3)]}]
		game.toolbar.navigation_open=true;controls._process(0)
		controls.trial_entry.pressed.emit()
		check(absf(game.player.position.x-134)<2 and game.draft.size()==1,"actual event entry moves to mill and retains unfinished drawing")
		for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
			root.size=size
			game.touch_controls.force_visible=true
			for i in 4:await process_frame
			controls._process(0)
			if size==Vector2i(844,390):print("MILL UI RECT panel=",controls.panel.get_global_rect()," tools=",game.toolbar.bottom.get_global_rect())
			check(button.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),"trial action remains reachable at "+str(size))
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(controls.panel.get_global_rect()),"whole event panel stays inside "+str(size))
			var overlaps_tool:=false
			for tool in game.toolbar.bottom.find_children("*","BaseButton",true,false):
				if tool.is_visible_in_tree() and controls.panel.get_global_rect().intersects(tool.get_global_rect()):overlaps_tool=true
			check(not overlaps_tool,"event panel does not overlap any actual tool button at "+str(size))
			if size==Vector2i(844,390):
				game.camera_x=133.5;game.camera_y=game.camera_target_y()
				var bridge_point:Vector2=game.world_to_screen(Vector2(133.5,5.2))
				var bridge_hidden:=false
				for tool in game.toolbar.bottom.find_children("*","BaseButton",true,false):
					if tool.is_visible_in_tree() and tool.get_global_rect().grow(4).has_point(bridge_point):bridge_hidden=true
				check(not bridge_hidden and Rect2(Vector2.ZERO,Vector2(size)).has_point(bridge_point),"narrow framing leaves the bridge itself visible below the tools")
			for target in [controls.trial_entry,button]:
				var owned:=InputEventScreenTouch.new();owned.index=72;owned.pressed=true;owned.position=target.get_global_rect().get_center()
				game.touch_controls.handle_touch(owned)
				check(game.touch_controls.owners.get(72,"")=="ui","event button touch avoids movement/attack ownership at "+str(size))
				owned.pressed=false;owned.canceled=true;game.touch_controls.handle_touch(owned)
			game.toolbar.navigation_open=true
			for i in 4:await process_frame
			controls._process(0)
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(controls.panel.get_global_rect()),"expanded navigation stays inside "+str(size))
			var nav_press:=InputEventScreenTouch.new();nav_press.index=73;nav_press.pressed=true;nav_press.position=button.get_global_rect().get_center()
			game.touch_controls.handle_touch(nav_press)
			check(game.touch_controls.owners.get(73,"")=="ui","expanded event action avoids movement ownership at "+str(size))
			nav_press.pressed=false;nav_press.canceled=true;game.touch_controls.handle_touch(nav_press)
			game.toolbar.navigation_open=false
		root.size=Vector2i(1280,800)
		for i in 4:await process_frame
		var touch=game.touch_controls;touch.force_visible=true;controls._process(0)
		var press:=InputEventScreenTouch.new();press.index=57;press.pressed=true;press.position=button.get_global_rect().get_center()
		touch.handle_touch(press)
		check(touch.owners.get(57,"")=="ui" and game.active_stroke==null,"touch on event action is owned by UI rather than painting")
		var release:=InputEventScreenTouch.new();release.index=57;release.position=press.position;touch.handle_touch(release)
		check(game.medieval_world.bridge_trial.phase=="ready" and game.draft.size()==1,"touch release prepares event through the actual button without losing draft")
		controls._process(0);button.pressed.emit()
		check(game.medieval_world.bridge_trial.phase=="running","same action proceeds from preparation to real cargo")
		controls._process(0)
		check(button.disabled,"running cargo cannot be spammed by the action button")
	game.queue_free();await process_frame
	print("MILL BRIDGE UI: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
