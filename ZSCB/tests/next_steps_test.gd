extends "res://tests/first_work_test.gd"
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.set_physics_process(false);game.player.freeze=true;game.combat.set_natives(false)
	var panel=game.get("next_steps")
	check(panel!=null,"optional activity panel exists")
	if panel==null:game.queue_free();await process_frame;print("NEXT STEPS: ",checks," checks, ",failures.size()," failures");quit(1);return
	game.first_work.start();draw_piece(Vector2(-2,0));game.first_work.action()
	game.first_work.note_moved(game.objects[0],Vector2.ZERO,Vector2(1,0));check(game.first_work.stage==3,"actual generated body used before save")
	game.object_nodes[0].freeze=true
	check(game.save_game() and game.first_work.stage==4,"real successful save completes first work")
	check(not panel.visible,"completion offers choice without opening a blocking panel automatically")
	var saved=SaveStore.load_game().data.duplicate(true)
	var origin:Vector2=game.player.position
	var objects=game.objects.duplicate(true)
	game.first_work.action();check(panel.visible and not game.first_work.visible,"completed guide action opens next choices")
	check(game.personal_overlay_open(),"activity panel isolates gameplay input")
	var mode:int=game.draw_mode
	var event:=InputEventKey.new();event.keycode=KEY_3;event.physical_keycode=KEY_3;event.pressed=true
	Input.parse_input_event(event);await process_frame;await process_frame
	game._physics_process(.016)
	event.pressed=false;Input.parse_input_event(event);await process_frame
	check(game.draw_mode==mode,"number shortcut cannot alter tools behind panel")
	panel.buttons.free.pressed.emit();check(not panel.visible and not game.personal_overlay_open(),"continue frees controls")
	game.toolbar.works.get_popup().id_pressed.emit(13);check(panel.visible,"works menu reopens optional choices")
	origin=game.player.position
	panel.buttons.trial.pressed.emit()
	check(panel.visible and game.world_kind=="paper" and game.player.position==origin,"wrong-map trial does not change map or teleport")
	check(panel.notice.text.contains("墨线边境"),"wrong-map route names required map")
	check(game.objects==objects and SaveStore.load_game().data==saved,"panel and guarded route preserve actual work/save")
	panel.buttons.structure.pressed.emit();check(not panel.visible and game.draw_mode==4 and game.connection_tool=="fixed","structure choice invokes actual connection tool")
	game.open_next_steps();panel.buttons.weapon.pressed.emit()
	check(not panel.visible and game.lab_open() and not game.weapon_lab.active,"weapon choice opens lab without spawning target")
	game.close_personal_overlay();game.open_next_steps();game.close_personal_overlay();check(not panel.visible,"existing Escape-close path handles panel")
	game.select_world("medieval-v1");game.player.position=Vector2(20,game.medieval_world.surface_height(20)+.6)
	origin=game.player.position;objects=game.objects.duplicate(true)
	game.open_next_steps();panel.buttons.trial.pressed.emit()
	check(not panel.visible and game.toolbar.navigation_open and game.player.position==origin,"trial choice shows existing route without teleport")
	check(game.medieval_world.bridge_trial.phase=="idle" and game.objects==objects,"trial route does not prepare event or modify creations")
	game.queue_free();await process_frame
	print("NEXT STEPS: ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
