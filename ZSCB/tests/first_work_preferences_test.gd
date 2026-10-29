extends "res://tests/first_work_test.gd"
func make_game(scene:String="main"):
	var instance=load("res://scenes/"+scene+".tscn").instantiate();root.add_child(instance);await process_frame
	instance.set_physics_process(false);instance.player.freeze=true;instance.combat.set_natives(false)
	return instance
func run()->void:
	root.size=Vector2i(1280,800)
	var config:=ConfigFile.new();config.set_value("video","sentinel",71);config.set_value("guide","seen",false);config.save(PaperOnboarding.PREFERENCES)
	game=await make_game("medieval")
	check(game.first_work.visible and game.first_work.stage==0,"first-ever medieval player gets same actual first-work goal")
	game.first_work.persist=false;var before:String=FileAccess.get_file_as_string(PaperOnboarding.PREFERENCES);game.first_work.dismiss()
	check(FileAccess.get_file_as_string(PaperOnboarding.PREFERENCES)==before,"nonpersistent goal never writes preference file")
	game.first_work.persist=true;game.first_work.start();game.first_work.dismiss()
	config.load(PaperOnboarding.PREFERENCES)
	check(config.get_value("guide","seen",false) and config.get_value("video","sentinel",0)==71,"explicit skip preserves old seen format and unrelated settings")
	check(not config.get_value("first_work","completed",false),"skipping is not recorded as actual completion")
	game.queue_free();await process_frame
	game=await make_game()
	check(not game.first_work.visible,"old seen preference prevents a repeated automatic tutorial")
	game.first_work.start();check(game.first_work.visible,"experienced player can deliberately replay")
	draw_piece(Vector2(-2,0));game.first_work.action()
	game.set_draw_mode(4);var object:Dictionary=game.objects[0];var point:=Vector2(object.x,object.y)
	game.pointer_down(game.world_to_screen(point));game.pointer_move(game.world_to_screen(point+Vector2(.4,0)));game.pointer_up(game.world_to_screen(point+Vector2(.4,0)))
	check(game.save_game() and game.first_work.stage==4,"real completed flow saves lesson memory")
	config.load(PaperOnboarding.PREFERENCES)
	check(config.get_value("first_work","completed",false) and config.get_value("guide","seen",false) and config.get_value("video","sentinel",0)==71,"completion stores only personal seen/completed values")
	game.queue_free();await process_frame
	var room:=PaperNetRoom.new();room.configure("FIRST1","paper","owner",PaperWorldStore.new("user://first-work-room"),"room");root.add_child(room);room.set_physics_process(false)
	var owner:Dictionary=room.join("","甲");room.ready(owner.player_id)
	check(room.world.first_work==null,"headless authority never creates a first-work course")
	var session:=PaperNetSession.new();root.add_child(session);session.player_id=owner.player_id;session.epoch=room.epoch;session.apply_snapshot(room.snapshot())
	check(not session.game.first_work.visible and not session.game.first_work.start(),"actual network client cannot run the solo lesson")
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("FIRST WORK PREFERENCES: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
