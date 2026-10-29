extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func place(body,at:Vector2)->void:
	body.position=at
	body.linear_velocity=Vector2.ZERO
	PhysicsServer2D.body_set_state(body.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,at))
func run()->void:
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	await physics_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	var world=game.medieval_world
	var starts:Array=[2.0,21.0,42.0,73.0,94.0,109.0,128.0,149.0,165.0]
	var walkers:Array=[]
	for index in starts.size():
		var walker=world.entity_by_id("villager-"+str(100+index)) if index<7 else world.entity_by_id("knight-100" if index==7 else "general-100")
		var x:float=starts[index]
		walker.home_x=x+4
		walker.patrol_half_width=6
		walker.facing=1
		place(walker,Vector2(x,world.terrain.support_height(x,walker.size.x*0.335)-0.045))
		walkers.append({"body":walker,"start":x})
	for x:float in starts:
		game.player.freeze=false
		game.player.reset_movement()
		place(game.player,Vector2(x,world.terrain.support_height(x,0.27)+0.52))
		for i in 10:await physics_frame
		var before:Vector2=game.player.position
		Input.action_press("move_right")
		for i in 75:
			game._physics_process(1.0/60)
			await physics_frame
		Input.action_release("move_right")
		print("Hero ",x," ",before," -> ",game.player.position," vel ",game.player.linear_velocity)
		check(game.player.position.x>before.x+3.8,"real player passes district facades/actors at "+str(x))
		check(game.player.position.y>world.terrain.travel_height(game.player.position.x)-0.2,"real player stays above road at "+str(x))
	# Real controller traverses both directions on the raised mountain ends.
	for route in [[14.0,-1.0],[3.0,1.0],[160.0,1.0],[166.0,-1.0]]:
		game.player.reset_movement()
		var x:float=route[0];var direction:float=route[1]
		place(game.player,Vector2(x,world.terrain.support_height(x,.27)+.52))
		for i in 10:await physics_frame
		var before:Vector2=game.player.position
		var action:="move_right" if direction>0 else "move_left"
		Input.action_press(action)
		for i in 75:
			game._physics_process(1.0/60)
			await physics_frame
		Input.action_release(action)
		print("Mountain route ",route," ",before," -> ",game.player.position)
		check((game.player.position.x-before.x)*direction>3.8,"real controller crosses mountain in direction "+str(route))
		check(game.player.position.y>world.travel_height(game.player.position.x)-.2,"mountain route remains above solid ground "+str(route))
	for item in walkers:
		print("Walker ",item.start," -> ",item.body.position," velocity ",item.body.linear_velocity," facing ",item.body.facing)
		check(item.body.position.x>item.start+2.0,"real NPC traverses district at "+str(item.start))
		check(item.body.position.y>world.terrain.travel_height(item.body.position.x)-0.35,"NPC feet retain road support at "+str(item.start))
	# Both carriages keep the original wheel meshes, and no driver crosses IDs.
	for suffix in [0,100]:
		var horse=world.entity_by_id("horse-"+str(suffix))
		var horse_pose:Dictionary=world.terrain.support_pose(horse.position.x,horse.size.x*0.335,0.05)
		check(absf(horse.position.y-horse_pose.position_y)<0.09,"horse stays on intended road beneath scene props "+str(suffix))
		check(horse.position.x>(63.5 if suffix==0 else 122.0),"horse autonomously advances with its carriage "+str(suffix))
		var wagon=world.entity_by_id("wagon-"+str(suffix))
		var driver=world.entity_by_id("driver-"+str(suffix))
		check(wagon.companion_id=="horse-"+str(suffix) and driver.companion_id==wagon.entity_id,"carriage associations unique "+str(suffix))
		for wheel in wagon.polygons.slice(0,2):
			var gap:=INF
			for local in wheel:
				var point:Vector2=wagon.to_global(local)
				gap=minf(gap,point.y-world.terrain.travel_height(point.x))
			check(absf(gap)<0.02,"measured carriage wheel contacts road "+str(suffix))
	# Regression: enter the final-art forge/bench/fence cluster from normal
	# ground height, independently of the elevated district teleport fixture.
	game.player.reset_movement()
	place(game.player,Vector2(108,world.travel_height(108)+.31))
	for i in 8:await physics_frame
	var ground_start:Vector2=game.player.position
	var highest_gap:=0.0
	Input.action_press("move_right")
	for i in 105:
		game._physics_process(1.0/60)
		await physics_frame
		var gap:float=game.player.position.y-world.travel_height(game.player.position.x)
		if gap>highest_gap and gap>.43:
			print("GROUND RISE ",game.player.position," gap ",gap," vel ",game.player.linear_velocity," climb ",game.climbing)
			for support in game.player.support_bodies():print("RISE SUPPORT ",support.get_meta("medieval_owner",support))
		highest_gap=maxf(highest_gap,gap)
	Input.action_release("move_right")
	check(game.player.position.x>ground_start.x+6.0,"normal ground approach passes low forge/bench/fence corners")
	check(highest_gap<.43,"owned low ledges do not hoist a ground walker into their undersides")
	game.player.reset_movement()
	place(game.player,Vector2(109,world.travel_height(109)+.31))
	for i in 8:await physics_frame
	var false_support:=false
	for body in game.player.support_bodies():
		if body.has_meta("medieval_owner"):false_support=true
	check(not false_support,"support rays agree with ghosted low platforms")
	var false_contact:=false
	for body in game.player.foot_bodies:
		if is_instance_valid(body) and body.has_meta("medieval_owner"):false_contact=true
	check(not false_contact,"foot sensor does not ground the hero on an ignored underside")
	game.queue_free();await process_frame
	print("MEDIEVAL PRODUCT ROUTES: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
