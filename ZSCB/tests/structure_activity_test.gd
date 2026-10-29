extends "res://tests/structure_links_test.gd"
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);game.set_physics_process(false);game.player.freeze=true
	game.camera_x=0;game.player.position=Vector2(0,-2.3)
	for i in 24:
		block("chain_"+str(i),Vector2(i*4,-2.6),[Vector2(-2,-.05),Vector2(2,-.05),Vector2(2,.05),Vector2(-2,.05),Vector2(-2,-.05)])
		if i>0:check(game.structure_links.create("chain_"+str(i-1),"chain_"+str(i),Vector2(i*4-2,-2.6),"fixed").ok,"chain link "+str(i)+" is physical")
	game._update_world_chunks()
	check(not game.object_nodes[-1].freeze,"an assembly extending beyond70m remains active as a connected whole")
	check(game.ground_chunks.has(5),"active remote endpoint also has its real ground chunk")
	var last=game.object_nodes[-1];await frames(20)
	check(last.position.is_finite() and last.position.y>game.GROUND_Y-.1,"remote endpoint remains above real ground under gravity")
	game.queue_free();await process_frame
	print("STRUCTURE ACTIVITY: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
