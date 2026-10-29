extends "res://tests/structure_links_test.gd"
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);game.set_physics_process(false);game.player.freeze=true
	var control=game.toolbar.get("connection_button")
	check(control!=null,"move tool exposes an actual connection control")
	if control==null:game.queue_free();quit(1);return
	block("one",Vector2(0,0),[Vector2(-1,0),Vector2(0,0)],false)
	block("two",Vector2.ZERO,[Vector2(.1,0),Vector2(1,0)],true)
	game.set_draw_mode(4);game.toolbar.update_buttons()
	check(game.connection_tool=="move","existing editing stays default")
	control.pressed.emit()
	check(game.connection_tool=="fixed","actual button chooses fixed connection")
	game.pointer_down(game.world_to_screen(Vector2(-.12,0)));game.pointer_up(game.world_to_screen(Vector2(-.12,0)))
	check(not game.connection_source.is_empty() and game.drag==null and game.active_stroke==null,"first click chooses a material anchor without dragging or painting")
	game.pointer_down(game.world_to_screen(Vector2(.15,0)));game.pointer_up(game.world_to_screen(Vector2(.15,0)))
	check(game.structure_links.records.size()==1 and game.structure_links.records[0].kind=="fixed","second nearby real click creates fixed constraint")
	game.undo();check(game.structure_links.records.is_empty(),"connection action participates in normal undo")
	control.pressed.emit()
	check(game.connection_tool=="hinge","next choice is a free hinge")
	game.pointer_down(game.world_to_screen(Vector2(-.12,0)));game.pointer_up(game.world_to_screen(Vector2(-.12,0)))
	game.pointer_down(game.world_to_screen(Vector2(.15,0)));game.pointer_up(game.world_to_screen(Vector2(.15,0)))
	check(game.structure_links.records.size()==1 and game.structure_links.records[0].kind=="hinge","actual pointer workflow creates a hinge")
	control.pressed.emit();var marker:Vector2=game.structure_links.marker(game.structure_links.records[0])
	game.pointer_down(game.world_to_screen(marker));game.pointer_up(game.world_to_screen(marker))
	check(game.structure_links.records.is_empty(),"unlink click removes the marker and joint")
	game.draft=[{"points":[Vector2(1,1),Vector2(2,1)]}];game.set_connection_tool("fixed")
	game.pointer_down(game.world_to_screen(Vector2(-.12,0)));game.pointer_up(game.world_to_screen(Vector2(-.12,0)))
	game.set_draw_mode(1)
	check(game.connection_source.is_empty() and game.mode_drafts[4].size()==1,"leaving connections cancels point selection and preserves draft")
	game.set_draw_mode(4)
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size;game.touch_controls.force_visible=true
		for i in 4:await process_frame
		game.toolbar.update_buttons()
		check(control.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect()),"connection button reachable at "+str(size))
		var touch:=InputEventScreenTouch.new();touch.index=92;touch.pressed=true;touch.position=control.get_global_rect().get_center()
		game.touch_controls.handle_touch(touch)
		check(game.touch_controls.owners.get(92,"")=="ui","connection touch is owned by UI at "+str(size))
		touch.pressed=false;game.touch_controls.handle_touch(touch)
		check(game.active_stroke==null and game.drag==null,"connection button does not paint or drag at "+str(size))
	game.queue_free();await process_frame
	print("STRUCTURE UI: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
