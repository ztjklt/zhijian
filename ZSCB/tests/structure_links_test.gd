extends SceneTree
var checks:=0
var failures:Array[String]=[]
var game
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL STRUCTURE: ",label)
func block(key:String,at:Vector2,points:Array,dynamic:bool=true):
	var object={"structure_id":key,"x":at.x,"y":at.y,"angle":0.0,"dynamic":dynamic,"kind":"freehand","role":"building","health":120.0,"max_health":120.0,"paths":[{"points":points,"collision":true}]}
	game.objects.append(object)
	var body=game.build_object_scene.instantiate();body.setup(object);game.object_nodes.append(game._attach_body(body,object))
	return body
func frames(n:int)->void:
	for i in n:await physics_frame
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game);game.set_physics_process(false);game.player.freeze=true
	var links=game.get("structure_links")
	check(links!=null,"core owns a real structure connection module")
	if links==null:game.queue_free();quit(1);return
	var square=[Vector2(-.3,-.3),Vector2(.3,-.3),Vector2(.3,.3),Vector2(-.3,.3),Vector2(-.3,-.3)]
	var bar=[Vector2(-1,-.06),Vector2(1,-.06),Vector2(1,.06),Vector2(-1,.06),Vector2(-1,-.06)]
	var base=block("base",Vector2(0,0),square,false)
	var beam=block("beam",Vector2(1,0),bar)
	check(links.snapshot().is_empty(),"old and new objects gain no automatic connections")
	var fixed=links.create("base","beam",Vector2(.3,0),"fixed")
	print("STRUCTURE DIAG fixed=",fixed," bodies=",links.body("base")," / ",links.body("beam")," beam=",beam.position)
	check(fixed.ok and links.get_child_count()==1,"explicit fixed link creates a physics constraint")
	if not fixed.ok:game.queue_free();quit(1);return
	check(not links.create("base","beam",Vector2(.3,0),"hinge").ok,"same pair cannot receive duplicate links")
	await frames(90);game.sync_objects()
	print("STRUCTURE DIAG fixed motion=",beam.position," angle=",beam.rotation," anchor=",beam.to_global(Vector2(-.7,0)))
	check(absf(beam.rotation)<.08 and absf(beam.position.y)<.12,"fixed connection supports real gravity without path positioning")
	var id:String=links.snapshot()[0].id
	check(links.remove(id).ok and links.snapshot().is_empty(),"explicit unlink removes only the joint")
	check(not beam.get_collision_exceptions().has(base) and not base.get_collision_exceptions().has(beam),"unlink restores both bodies' collision relationship")
	beam.position=Vector2(1,0);beam.rotation=0;beam.linear_velocity=Vector2.ZERO;beam.angular_velocity=0
	PhysicsServer2D.body_set_state(beam.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,beam.transform)
	var hinge=links.create("base","beam",Vector2(.3,0),"hinge")
	check(hinge.ok,"same pieces can use a free hinge")
	await frames(45)
	check(absf(beam.rotation)>.25,"hinge actually rotates under weight")
	var anchor:Vector2=beam.to_global(Vector2(-.7,0))
	check(anchor.distance_to(Vector2(.3,0))<.15,"hinge keeps the physical attachment point together")
	check(not links.create("base","beam",Vector2(8,8),"fixed").ok,"distant material cannot be joined")
	links.remove(links.snapshot()[0].id)
	var u=block("open",Vector2(4,0),[Vector2.ZERO,Vector2(0,2),Vector2(2,2)])
	block("other",Vector2(5,1),square,false)
	check(not links.create("open","other",Vector2(5,1),"fixed").ok,"empty space in a contour bounding box is not material")
	u.freeze=true
	beam.position=Vector2(1,0);beam.rotation=0;beam.linear_velocity=Vector2.ZERO;beam.angular_velocity=0
	PhysicsServer2D.body_set_state(beam.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,beam.transform)
	check(links.create("base","beam",Vector2(.3,0),"fixed").ok,"a removed link can be rebuilt explicitly")
	beam.sync_to_data()
	PaperObjectDamage.add_cut(beam.data,Vector2(.3,0),40);beam.rebuild_damage()
	links.step()
	check(links.snapshot().is_empty(),"cutting away attachment material severs the connection")
	check(game.objects.size()==4 and is_instance_valid(beam),"severing a link preserves all source creations")
	check(not links.create("base","base",Vector2(.3,0),"fixed").ok,"self connection is refused")
	check(not links.create("base","missing",Vector2(.3,0),"fixed").ok,"missing object is refused")
	var first=block("falling_one",Vector2(-4,3),square)
	var second=block("falling_two",Vector2(-3,3),bar)
	check(links.create("falling_one","falling_two",Vector2(-3.7,3),"fixed").ok,"two dynamic bodies may form a moving assembly")
	second.apply_central_impulse(Vector2(.6,.2))
	await frames(30)
	check(first.position.is_finite() and second.position.is_finite() and first.position.y<2,"assembly remains finite and falls under normal gravity")
	check(first.to_global(Vector2(.3,0)).distance_to(second.to_global(Vector2(-.7,0)))<.12 and absf(angle_difference(first.rotation,second.rotation))<.08,"fixed assembly preserves anchors and relative angle under impulse")
	var saved:Array=links.snapshot();saved[0].bx=100
	check(not links.restore(saved) and links.records.size()==1,"invalid restore does not erase an existing joint")
	game.queue_free();await process_frame
	print("STRUCTURE LINKS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
