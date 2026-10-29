extends SceneTree
var count:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("PROGRESSIVE DAMAGE: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.onboarding.dismiss()
	game.set_draw_mode(1);game.generator="own"
	var center:Vector2=game.player.position+Vector2(2,1)
	game.draft=[{"points":[center+Vector2(-.5,-.5),center+Vector2(.5,-.5),center+Vector2(.5,.5),center+Vector2(-.5,.5),center+Vector2(-.5,-.5)]}]
	game.generate()
	check(game.objects.size()==1,"real free drawing generates a physical object")
	var obj:Dictionary=game.objects[0]
	var contact:=Vector2(obj.x-.5,obj.y)
	game.combat.damage_building(0,18,contact)
	check(obj.get("health",120)<120,"own free creation actually takes damage")
	check(ResourceLoader.exists("res://scripts/object_damage.gd"),"shared progressive geometry exists")
	if not ResourceLoader.exists("res://scripts/object_damage.gd"):
		game.queue_free();await process_frame
		print("PROGRESSIVE DAMAGE: ",count," checks, ",failures.size()," failures");quit(1);return
	var damage=load("res://scripts/object_damage.gd")
	check(obj.get("damage_cuts",[]).size()==1,"first hit leaves a persistent local chip")
	var cooked:Dictionary=damage.prepare(obj)
	var local:=Vector2(-.48,0)
	check(not cooked.fills.any(func(p):return Geometry2D.is_point_in_polygon(local,p)),"visible fill is removed at actual contact")
	check(not cooked.shapes.any(func(s):return s.has("polygon") and Geometry2D.is_point_in_polygon(local,s.polygon)),"rigid body geometry has the same missing material")
	check(cooked.fills.any(func(p):return Geometry2D.is_point_in_polygon(Vector2(.3,.3),p)),"unstruck material remains solid")
	game.combat.damage_building(0,18,Vector2(obj.x+.5,obj.y+.2))
	check(obj.health==84 and obj.damage_cuts.size()==2,"repeated hits progressively damage rather than instantly erase")
	var blueprint:Dictionary=game.bag.entries.back()
	var blueprint_count:int=game.bag.entries.size()
	check(not blueprint.has("damage_cuts") and blueprint.paths==obj.paths,"blueprint keeps original unbroken drawing")
	check(game.save_game(),"damaged geometry can be saved")
	var saved:=SaveStore.load_game()
	check(saved.error=="" and saved.data.objects[0].damage_cuts.size()==2 and saved.data.objects[0].health==84,"damage round-trips through JSON")
	# Open ink gains a real gap instead of losing the rest of the drawing.
	var open:Dictionary={"role":"building","x":0.0,"y":0.0,"angle":0.0,"dynamic":true,"paths":[{"points":[Vector2(-2,0),Vector2(2,0)],"collision":true}],"damage_cuts":[{"x":0.0,"y":0.0,"r":.2}]}
	var line:Dictionary=damage.prepare(open)
	check(line.paths.size()==2,"open line splits into two intact pieces at damage")
	check(not line.paths.any(func(p):return p.points.any(func(v):return v.length()<.1)),"gap never reconnects through a cut")
	# Hollow shapes retain holes; damage never fills empty space.
	var hollow:Dictionary={"role":"building","x":0.0,"y":0.0,"dynamic":true,"paths":[{"points":[Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1),Vector2(1,1)],"collision":true}],"damage_cuts":[{"x":-1.0,"y":0.0,"r":.2}]}
	check(damage.prepare(hollow).fills.is_empty(),"an open hollow drawing stays hollow")
	for i in 20:game.combat.damage_building(0,5,contact)
	check(game.objects.is_empty() and game.bag.entries.size()==blueprint_count,"eventual destruction removes world object and preserves blueprint")
	game.queue_free();await process_frame
	print("PROGRESSIVE DAMAGE: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
