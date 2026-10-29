extends "res://tests/first_work_test.gd"
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false)
	var panel=game.get("next_steps")
	check(panel!=null,"optional panel exists for layout verification")
	if panel==null:game.queue_free();await process_frame;quit(1);return
	root.min_size=Vector2i.ZERO
	for dimensions in [Vector2i(390,844),Vector2i(844,390),Vector2i(1280,800),Vector2i(2560,1440)]:
		root.size=dimensions;await process_frame;await process_frame
		game.open_next_steps();await process_frame;await process_frame
		var screen:=Rect2(Vector2.ZERO,Vector2(root.size))
		check(panel.buttons.free.get_theme_color("font_focus_color")==PaperTheme.INK,"focused continue remains readable")
		check(screen.encloses(panel.panel.get_global_rect()),"panel fits "+str(dimensions))
		check(screen.encloses(panel.buttons.free.get_global_rect()),"continue remains visible "+str(dimensions))
		for button in panel.buttons.values():check(button.size.y>=44,"touch target remains usable "+str(dimensions))
		var draft=game.draft.duplicate(true)
		game.pointer_down(Vector2(8,root.size.y*.5));game.pointer_move(Vector2(80,root.size.y*.5));game.pointer_up(Vector2(80,root.size.y*.5))
		check(game.draft==draft,"outside click never draws through panel "+str(dimensions))
		if DisplayServer.get_name()!="headless" and OS.get_environment("PAPER_UI_EVIDENCE")!="":
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(OS.get_environment("PAPER_UI_EVIDENCE")+"/next-steps-%dx%d.png"%[dimensions.x,dimensions.y])
		panel.buttons.free.pressed.emit()
	game.queue_free();await process_frame
	print("NEXT STEPS LAYOUT: ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
