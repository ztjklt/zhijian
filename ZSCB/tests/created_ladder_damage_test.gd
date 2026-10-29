extends SceneTree
var failures:Array[String]=[]
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("CREATED LADDER: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.onboarding.dismiss();game.set_draw_mode(1);game.generator="own"
	var center:Vector2=game.player.position+Vector2(2,1)
	game.draft=[{"points":[center+Vector2(-.3,-.9),center+Vector2(-.3,.9)]},{"points":[center+Vector2(.3,-.9),center+Vector2(.3,.9)]},{"points":[center+Vector2(-.3,-.3),center+Vector2(.3,-.3)]},{"points":[center+Vector2(-.3,.3),center+Vector2(.3,.3)]}]
	game.generate()
	check(game.objects.size()==1,"real tool1 ladder is created")
	var obj:Dictionary=game.objects.back()
	check(obj.kind=="ladder" and game.object_nodes.back().get_child_count()>0,"actual ladder has physical rods despite original false collision markers")
	game.combat.damage_building(0,18,Vector2(obj.x-.3,obj.y))
	check(obj.get("health",120)==102 and obj.get("damage_cuts",[]).size()==1,"own recognized ladder is destructible like other physical creations")
	var old:Dictionary={"kind":"ladder","x":0.0,"y":0.0,"dynamic":true,"paths":obj.paths.duplicate(true)}
	var body:=BuildObject.new();body.setup(old)
	check(old.get("role","")=="building" and old.get("health",0)==120,"old ladder data gains damage identity when its physical body is restored")
	body.free()
	game.ink.amount=300
	game.pending_match=[{"id":"ladder","label":"梯子"}];game.candidate_index=0
	game.preview_x=center.x+2;game.preview_y=center.y
	game.preview_paths=ShapeMatcher.make_prefab("ladder",{"width":.8,"height":2.2})
	game.confirm_candidate()
	check(game.objects.size()==2,"real library confirmation creates physical ladder")
	var prefab:Dictionary=game.objects.back()
	game.combat.damage_building(1,18,Vector2(prefab.x-.4,prefab.y))
	check(prefab.get("health",120)==102 and prefab.get("damage_cuts",[]).size()==1,"confirmed library ladder also takes progressive damage")
	game.queue_free();await process_frame
	print("CREATED LADDER: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
