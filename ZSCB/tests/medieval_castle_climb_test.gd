extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	await physics_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.reset_movement()
	game.player.position=Vector2(70.5,4.0)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	game.player.linear_velocity=Vector2.ZERO
	for i in 35:await physics_frame
	var start:float=game.player.position.y
	check(start<4.0,"player starts on real ground inside the castle facade")
	var previous:=start
	for tier in 4:
		for frame in 100:
			game.step_locomotion(1.0/60,{"jump_pressed":frame in [0,23]})
			game.player.update_drop_through(1.0/60)
			await physics_frame
		var current:float=game.player.position.y
		print("CLIMB tier ",tier," ",previous," -> ",current)
		check(current>=previous-.1,"successive jumps land on castle sill/battlement rather than falling through")
		previous=current
	check(game.player.position.y>11.8,"actual unchanged double-jump controller climbs from ground to tower crown")
	check(game.player.position.y-start>8.0,"climb gains over eight metres without teleporting between tiers")
	check(not game.player.support_bodies().is_empty(),"tower crown has a real final support")
	game.queue_free();await process_frame
	print("CASTLE CLIMB: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
