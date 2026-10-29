extends "res://tests/first_work_test.gd"
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false)
	var popup=game.toolbar.works.get_popup()
	check(popup.get_item_index(12)>=0,"actual works menu provides a replayable first-work entry")
	if popup.get_item_index(12)<0:game.queue_free();quit(1);return
	game.draft=[{"points":[game.player.position+Vector2(1,2),game.player.position+Vector2(2,2)]}]
	var draft:Array=game.draft.duplicate(true);var objects:int=game.objects.size();var weapon:Dictionary=game.equipped_weapon.duplicate(true)
	popup.id_pressed.emit(12);game.refresh_buttons();await process_frame
	check(game.first_work.visible and game.first_work.stage==1,"real entry recognizes preserved unfinished drawing")
	check(game.draft==draft and game.objects.size()==objects and game.equipped_weapon==weapon,"starting does not clear or generate any user work")
	game.set_draw_mode(2);game.refresh_buttons();game.first_work.action()
	check(game.draw_mode==1 and game.draft==draft,"next action returns to the original tool's complete draft")
	for size in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(2560,1440)]:
		root.size=size
		for i in 8:await process_frame
		var compact:bool=size.x<600 or size.y<500
		var primary=game.toolbar.first_work_action if compact else game.toolbar.guide_action
		var skip=game.toolbar.first_work_skip if compact else game.toolbar.guide_skip
		var viewport:=Rect2(Vector2.ZERO,Vector2(size))
		check(primary.is_visible_in_tree() and viewport.encloses(primary.get_global_rect()),"actual next action reachable at "+str(size))
		check(skip.is_visible_in_tree() and viewport.encloses(skip.get_global_rect()),"actual skip reachable at "+str(size))
		var stick_area:=Rect2(game.touch_controls.stick_center-Vector2.ONE*game.touch_controls.radius,Vector2.ONE*game.touch_controls.radius*2)
		check(not primary.get_global_rect().intersects(stick_area),"lesson button avoids joystick at "+str(size))
	root.size=Vector2i(390,844)
	for i in 6:await process_frame
	game.touch_controls.force_visible=true
	var touch:=InputEventScreenTouch.new();touch.index=4;touch.pressed=true;touch.position=game.toolbar.first_work_skip.get_global_rect().get_center()
	game.touch_controls.handle_touch(touch);touch.pressed=false;game.touch_controls.handle_touch(touch)
	check(not game.first_work.visible and game.draft==draft,"real touch skip retains the full drawing")
	game.queue_free();await process_frame
	print("FIRST WORK UI: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
