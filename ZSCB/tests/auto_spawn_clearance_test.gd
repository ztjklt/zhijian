extends SceneTree
const Clearance := preload("res://scripts/spawn_clearance.gd")
var checks:=0
var failures:Array[String]=[]
var timings:Array[float]=[]
class FixtureWorld extends Node2D:
	var knowledge_world = null
	var medieval_world = null
	var player:RigidBody2D
	const GROUND_Y := -20.0
	func object_bounds(object:Dictionary)->Rect2:
		var points:Array=[]
		for path in object.paths:
			for p in path.points:points.append(Vector2(object.x,object.y)+p.rotated(object.get("angle",0.0)))
		var bounds:=Rect2(points[0],Vector2.ZERO)
		for p in points:bounds=bounds.expand(p)
		return bounds
var game
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)
func square(at:Vector2,size:Vector2=Vector2.ONE,angle:float=0)->BuildObject:
	var h:=size*.5
	var points:=[Vector2(-h.x,-h.y),Vector2(h.x,-h.y),Vector2(h.x,h.y),Vector2(-h.x,h.y),Vector2(-h.x,-h.y)]
	return ink(points,at,angle)
func ink(points:Array,at:Vector2,angle:float=0)->BuildObject:
	var node:=BuildObject.new()
	node.setup({"x":at.x,"y":at.y,"angle":angle,"kind":"freehand","paths":[{"points":points}],"dynamic":true})
	return node
func obstacle(at:Vector2,size:Vector2,layer:int=1,angle:float=0)->StaticBody2D:
	var node:=StaticBody2D.new();node.position=at;node.rotation=angle;node.collision_layer=layer
	var fixture:=CollisionShape2D.new();var shape:=RectangleShape2D.new();shape.size=size;fixture.shape=shape;node.add_child(fixture);game.add_child(node)
	return node
func evaluate(node:BuildObject,label:String)->Dictionary:
	var original:Dictionary=node.data.duplicate(true)
	var pose:=node.transform
	var started:=Time.get_ticks_usec()
	var result:=Clearance.resolve(game,node,node.data)
	timings.append(float(Time.get_ticks_usec()-started)/1000.0)
	print("SEARCH ",label," ",timings.back(),"ms ",result)
	check(result.valid,label+" finds a safe position")
	check(node.data==original and node.transform==pose,label+" resolver leaves input strokes and angle untouched")
	if result.valid:check(Clearance._contacts(game,node,result.offset).is_empty(),label+" actual compound fixtures are clear")
	node.free()
	return result
func reset()->void:
	for child in game.get_children():
		if child!=game.player:child.queue_free()
	await physics_frame;await physics_frame
func run()->void:
	game=FixtureWorld.new();root.add_child(game)
	game.player=RigidBody2D.new();game.player.freeze=true;game.player.position=Vector2(0,-10);game.add_child(game.player)
	await physics_frame
	for layer in [1,2,8,16,64,128]:
		obstacle(Vector2.ZERO,Vector2(2,2),layer)
		await physics_frame
		var result:=evaluate(square(Vector2.ZERO),"overlap layer "+str(layer))
		if result.valid:check(result.offset.length()>=1.49 and result.offset.length()<1.54,"layer "+str(layer)+" chooses nearest face, not arbitrary jump")
		await reset()
	obstacle(Vector2.ZERO,Vector2(8,2));obstacle(Vector2.ZERO,Vector2(2,8))
	await physics_frame
	var diagonal:=evaluate(square(Vector2.ZERO,Vector2(.5,.5)),"crossed barriers")
	if diagonal.valid:check(absf(absf(diagonal.offset.x)-1.25)<.04 and absf(diagonal.offset.y-1.25)<.04,"nearest diagonal exit beats either distant axis exit")
	await reset()
	obstacle(Vector2.ZERO,Vector2(4,.2),1,PI/4)
	await physics_frame
	var slope:=evaluate(square(Vector2.ZERO,Vector2(.4,.4),.17),"rotated sloped obstacle")
	if slope.valid:check(slope.offset.length()<.42 and absf(slope.offset.x)>.2,"slope resolves along actual face normal")
	await reset()
	obstacle(Vector2.ZERO,Vector2(30,30))
	await physics_frame
	var far:=evaluate(square(Vector2.ZERO),"large enclosing facade")
	if far.valid:check(far.offset.length()>15.49 and far.offset.length()<15.54 and far.offset.y>0,"nearest automatic exit may exceed old6m and12m limits")
	await reset()
	obstacle(Vector2(-2.65,0),Vector2(4.7,4));obstacle(Vector2(2.65,0),Vector2(4.7,4))
	await physics_frame
	var narrow:=evaluate(square(Vector2(.2,0),Vector2(.4,.4)),"narrow gap")
	if narrow.valid:check(narrow.offset.x<-.099 and narrow.offset.length()<.14,"a narrow nearby hole wins over moving above whole obstacle")
	await reset()
	var u:=ink([Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(.7,1),Vector2(.7,-.7),Vector2(-.7,-.7),Vector2(-.7,1),Vector2(-1,1)],Vector2.ZERO)
	u.freeze=true;game.add_child(u);await physics_frame
	var hole:=evaluate(square(Vector2.ZERO,Vector2(.4,.4)),"existing compound hole")
	if hole.valid:check(hole.offset==Vector2.ZERO,"already safe compound hole stays exactly at requested position")
	await reset()
	for i in 80:obstacle(Vector2(0,(float(i)-39.5)*.05),Vector2(12,.03))
	await physics_frame
	var dense:=evaluate(square(Vector2.ZERO,Vector2(1,6)),"more than64 overlapping fixtures")
	if dense.valid:check(absf(dense.offset.y-4.99)<.04 and absf(dense.offset.x)<.01,"full query batches still find nearest clear outer face")
	await reset()
	obstacle(Vector2.ZERO,Vector2(8,8));await physics_frame
	var strokes:Array=[]
	for row in 16:
		for column in 8:
			var at:=Vector2((column-3.5)*.18,(row-7.5)*.08)
			strokes.append({"points":[at-Vector2(.2,0),at+Vector2(0,.03),at+Vector2(.2,0)]})
	var many:=BuildObject.new();many.setup({"x":0.0,"y":0.0,"angle":.23,"kind":"freehand","paths":strokes,"dynamic":true})
	var compound:=evaluate(many,"256-fixture rotated drawing")
	if compound.valid:check(compound.offset.length()<5,"complex compound chooses a nearby exit")
	await reset()
	var capsule_body:=StaticBody2D.new();capsule_body.collision_layer=1
	var capsule_fixture:=CollisionShape2D.new();var capsule:=CapsuleShape2D.new();capsule.radius=2;capsule.height=20
	capsule_fixture.shape=capsule;capsule_body.add_child(capsule_fixture);game.add_child(capsule_body);await physics_frame
	var rod:=evaluate(square(Vector2(0,7),Vector2(.4,.4)),"long capsule straight side")
	if rod.valid:check(rod.offset.length()<2.24 and absf(rod.offset.x)>2.19,"capsule envelope preserves nearest side exit instead of overshooting its tip")
	await reset()
	var invalid:=BuildObject.new();invalid.data={"x":0.0,"y":0.0,"paths":[]}
	check(not Clearance.resolve(game,invalid,invalid.data).valid,"empty invalid collision remains rejected")
	invalid.free()
	game.queue_free();await process_frame
	game=load("res://scenes/medieval.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await physics_frame;game.onboarding.dismiss();game.set_physics_process(false);game.player.freeze=true
	var facade:=evaluate(square(Vector2(78,7),Vector2(3,3),.18),"real castle facade")
	if facade.valid:check(facade.offset.length()<12,"castle escapes via nearby silhouette boundary")
	var edge:=evaluate(square(Vector2(184,30),Vector2(8,2)),"wide body at map edge")
	if edge.valid:check(184+edge.offset.x+4<=185.001 and 184+edge.offset.x-4>=-5,"whole rotated footprint remains within finite world")
	if edge.valid:check(edge.offset.distance_to(Vector2(-3,0))<.02,"finite-world constraint selects exact nearest lateral translation")
	var buried:=evaluate(square(Vector2(179,-12),Vector2(2,2)),"buried near finite terrain bottom")
	if buried.valid:check(-12+buried.offset.y-1>=2.39,"escape never chooses false empty space under terrain")
	game.queue_free();await process_frame
	game=load("res://scenes/main.tscn").instantiate();game.world_kind="nature-v1";game.onboarding.persist=false;root.add_child(game)
	await physics_frame;game.onboarding.dismiss();game.set_physics_process(false);game.player.freeze=true
	var hill_y:float=game.knowledge_world.surface_height(132)
	check(not game.knowledge_world.chunks.has(8),"nature fixture exercises an unloaded destination chunk")
	var hill:=evaluate(square(Vector2(132,hill_y),Vector2(.8,.8)),"unloaded nature slope")
	if hill.valid:check(hill.offset.x<-.1 and hill.offset.y>.3 and hill.offset.length()<.6,"continuous nature soil finds nearest uphill face normal")
	game.queue_free();await process_frame
	game=load("res://scenes/sandbox.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await physics_frame;game.onboarding.dismiss();game.set_physics_process(false);game.player.freeze=true
	var letter_at:=Vector2.ZERO
	for path in game.knowledge_world.paths:
		if path.points.size()<2:continue
		var midpoint:Vector2=(path.points[0]+path.points[1])*.5
		if midpoint.x>100 and midpoint.y>2:letter_at=midpoint;break
	check(letter_at!=Vector2.ZERO,"fixture locates a real distant textbook stroke")
	var letter:=evaluate(square(letter_at,Vector2(.2,.2)),"unloaded textbook stroke")
	if letter.valid:
		check(letter.offset.length()>.02,"unloaded letter still triggers automatic clearance")
		var final_at:Vector2=letter_at+letter.offset
		game.player.position=final_at+Vector2(0,4);game.knowledge_world._update_chunks()
		await physics_frame
		var probe:=square(final_at,Vector2(.2,.2))
		check(Clearance._contacts(game,probe,Vector2.ZERO).is_empty(),"automatic destination remains clear when its actual chapter loads")
		probe.free()
	game.queue_free();await process_frame
	var max_ms:=0.0
	for value in timings:max_ms=maxf(max_ms,value)
	check(max_ms<100,"each automatic search stays below100ms UI stall budget")
	print("AUTO SPAWN: ",checks," checks, ",failures.size()," failures; worst search ",max_ms," ms")
	quit(0 if failures.is_empty() else 1)
