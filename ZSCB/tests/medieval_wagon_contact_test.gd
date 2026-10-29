extends SceneTree
## Physical support is checked against the visible PNG wheel ink, not image corners.
var failures:Array[String]=[]
var checks:=0
var maximum_wheel_gap:=0.0
func _init() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error("WAGON CONTACT: "+label)
func visible_wheel_edges(image:Image,left:int,right:int) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for y in range(600,779):
		var first:=-1
		var last:=-1
		for x in range(left,right):
			if image.get_pixel(x,y).a>0.05:
				if first<0:first=x
				last=x
		if first>=0:
			result.append(Vector2(first,y))
			result.append(Vector2(last,y))
	return result
func local_pixel(wagon,pixel:Vector2) -> Vector2:
	var uv:Vector2=(pixel-wagon.source_rect.position)/wagon.source_rect.size
	return Vector2((0.5-uv.x if wagon.facing>0 else uv.x-0.5)*wagon.size.x,(1-uv.y)*wagon.size.y)
func run() -> void:
	var game=load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist=false
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false)
	game.player.freeze=true
	var world=game.medieval_world
	var wagon=world.entity_by_id("wagon-0")
	var horse=world.entity_by_id("horse-0")
	var image:Image=wagon.texture.get_image()
	var wheels:Array=[visible_wheel_edges(image,610,965),visible_wheel_edges(image,1340,1717)]
	for facing in [1,-1]:
		for center in [50.0,53.3,53.7,54.0,54.5,54.8,55.1,60.0,67.5,68.0,68.5]:
			horse.position.x=center+facing*2.3
			horse.home_x=horse.position.x
			horse.facing=facing
			horse.hurt_timer=0
			horse.patrol_turn_cooldown=0.6 # Isolate wheel support from nearby market patrol reversals.
			world.step(1.0/60)
			check(absf(wagon.position.x-center)<0.001 and wagon.facing==facing,"wheel fixture reaches requested bank position and facing")
			for wheel in wheels.size():
				var gap:=INF
				for pixel in wheels[wheel]:
					var point:Vector2=wagon.to_global(local_pixel(wagon,pixel))
					gap=minf(gap,point.y-world.travel_height(point.x))
				maximum_wheel_gap=maxf(maximum_wheel_gap,absf(gap))
				check(absf(gap)<0.015,"visible wheel "+str(wheel)+" contacts ground at x="+str(center)+" facing="+str(facing)+" gap="+str(gap))
		await physics_frame
		var reversal_query:=PhysicsPointQueryParameters2D.new()
		reversal_query.collision_mask=128
		reversal_query.position=wagon.to_global(local_pixel(wagon,Vector2(150,720)))
		check(not game.get_world_2d().direct_space_state.intersect_point(reversal_query).any(func(hit):return hit.collider==wagon),"reversal mirrors the physical empty space below the shaft facing="+str(facing))
		reversal_query.position=wagon.to_global(local_pixel(wagon,Vector2(787,750)))
		check(game.get_world_2d().direct_space_state.intersect_point(reversal_query).any(func(hit):return hit.collider==wagon),"reversal mirrors the actual physical wheel facing="+str(facing))
	# The front shaft is raised; only actual wheels extend down to the ground.
	wagon.facing=1
	wagon.rebuild_geometry()
	check(not wagon.contains_world_point(wagon.to_global(Vector2(1.35,0.06))),"raised shaft does not create an invisible low rectangle")
	check(wagon.contains_world_point(wagon.to_global(Vector2(1.35,0.55))),"actual raised shaft still collides")
	var physics_shape_count:=0
	await physics_frame
	for child in wagon.get_children():
		if child is CollisionShape2D:physics_shape_count+=1
	check(physics_shape_count>=4,"wheels body and raised shaft own real compound physics shapes")
	var query:=PhysicsPointQueryParameters2D.new()
	query.collision_mask=128
	query.position=wagon.to_global(Vector2(1.35,0.06))
	check(not game.get_world_2d().direct_space_state.intersect_point(query).any(func(hit):return hit.collider==wagon),"actual physics also excludes low empty space below the shaft")
	query.position=wagon.to_global(Vector2(1.35,0.55))
	check(game.get_world_2d().direct_space_state.intersect_point(query).any(func(hit):return hit.collider==wagon),"actual physics retains raised shaft contact")

	print("WAGON maximum visible wheel gap m=",maximum_wheel_gap)
	var pose_started:=Time.get_ticks_usec()
	for i in 100:world.terrain.wagon_pose(54.8,wagon.source_rect,wagon.size,1)
	print("WAGON support pose average ms=",(Time.get_ticks_usec()-pose_started)/100000.0)
	world.damage_entity(wagon,1000,wagon.position,Vector2.ZERO)
	var replacement=world._spawn("wagon",50,99)
	check(replacement.polygons.size()==4,"destroyed cart cannot clear the next cart's reusable collider geometry")
	game.queue_free();await process_frame
	print("WAGON CONTACT: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
