extends "res://tests/first_work_test.gd"
func frames(count:int)->void:
	for i in count:await physics_frame
func run()->void:
	root.size=Vector2i(1280,800)
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);await process_frame
	game.combat.set_natives(false);game.first_work.start()
	draw_piece(Vector2(-3.6,-1.8));game.generate()
	check(game.first_work.stage==2,"real hand-drawn platform reaches actual-use step")
	var body=game.first_work.target()
	if body==null:game.queue_free();quit(1);return
	await frames(50)
	check(game.first_work.stage==2,"falling and resting alone never completes use")
	game.player.clear_foot_contacts();game.player.position=Vector2(body.position.x,game.object_bounds(body.data).end.y+1.1);game.player.linear_velocity=Vector2.ZERO
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	await frames(4);check(game.first_work.stage==2,"being above the platform is not standing on it")
	await frames(100)
	check(game.on_ground and game.player.support_bodies().has(body),"physical avatar actually lands on its own creation")
	check(game.first_work.stage==3,"actual stable support advances use, without a pretend completion action")
	var old_bag:Dictionary=game.bag.duplicate(true)
	game.bag.hotbar=[]
	check(not game.save_game() and game.first_work.stage==3,"actual invalid save fails and retains retry step")
	check(not FileAccess.file_exists(SaveStore.SAVE_PATH),"failed first save cannot create a false success file")
	game.bag=old_bag
	check(game.save_game() and game.first_work.stage==4,"retry writes a real valid world and completes")
	game.first_work.start();draw_piece(Vector2(-1,0));game.generate()
	check(game.first_work.stage==2,"replay tracks a new actual creation")
	game.load_game()
	check(game.first_work.stage==0 and game.first_work.target_key=="","loading an older world cannot complete a new lesson")
	game.first_work.start();game.world_kind="different-test-map";game.first_work.step(.1)
	check(game.first_work.stage==0 and game.first_work.map=="different-test-map","changing map resets only lesson state")
	game.queue_free();await process_frame
	print("FIRST WORK USE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
