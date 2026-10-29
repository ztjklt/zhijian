extends SceneTree
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);print("FAIL: ",label)
func run()->void:
	var world:=MedievalWorld.new();root.add_child(world);await physics_frame
	var walkers:Array=[]
	for index in 2:
		var walker=world.entity_by_id("villager-"+str(index))
		var x:=5.7 if index==0 else 96.7
		walker.home_x=x+1;walker.patrol_half_width=3
		walker.position=Vector2(x,world.terrain.support_height(x,walker.size.x*.335)-.045)
		walker.linear_velocity=Vector2.ZERO;walker.facing=1
		PhysicsServer2D.body_set_state(walker.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,walker.position))
		walkers.append(walker)
	for i in 180:
		world.step(1.0/60)
		await physics_frame
	check(walkers[0].position.x>6.4,"villager physically crosses forest gradient seam")
	check(walkers[1].position.x>97.4,"villager physically crosses ridge gradient seam")
	var actor=walkers[0]
	actor.hurt_timer=.5;actor.linear_velocity=Vector2(2,4)
	var before:Vector2=actor.position
	world._follow_slope(actor,1.0/60)
	check(actor.position==before and actor.linear_velocity==Vector2(2,4),"slope correction preserves real knockback")
	actor.hurt_timer=0;actor.position.y+=3;actor.linear_velocity=Vector2(1,-2)
	before=actor.position
	world._follow_slope(actor,1.0/60)
	check(actor.position==before and actor.linear_velocity==Vector2(1,-2),"airborne actors retain physics")
	world.queue_free();await process_frame
	print("MEDIEVAL PRODUCT SEAMS: 4 checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
