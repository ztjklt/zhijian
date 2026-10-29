extends SceneTree
var failures:Array[String]=[]
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failures.append(label);push_error("WEAPON TRACE: "+label)
func _init()->void:call_deferred("run")
func run()->void:
	var source:=FileAccess.get_file_as_string("res://scripts/creation_feedback.gd")
	check(not source.contains("func _draw_swing("),"generic reach-based attack arcs are removed")
	check(ResourceLoader.exists("res://scripts/weapon_trace.gd"),"model contour trace exists")
	if not ResourceLoader.exists("res://scripts/weapon_trace.gd"):
		print("WEAPON TRACE: ",count," checks, ",failures.size()," failures");quit(1);return
	var trace=load("res://scripts/weapon_trace.gd").new()
	var paths:Array=[PackedVector2Array([Vector2(10,2),Vector2(10,4),Vector2(11,4)]),PackedVector2Array([Vector2(9.7,2.2),Vector2(10.3,2.2)])]
	trace.advance(.016,paths,true)
	check(trace.snapshots.size()==1 and trace.snapshots[0].paths==paths,"echo uses every actual path point without fabricated curves")
	paths[0][0]=Vector2(20,20)
	check(trace.snapshots[0].paths[0][0]==Vector2(10,2),"captured ink is immutable world geometry")
	for i in 30:trace.advance(.016,paths,true)
	check(trace.snapshots.size()<=trace.MAX_SNAPSHOTS,"history is bounded")
	trace.advance(.2,[],false)
	check(trace.snapshots.is_empty(),"echoes expire by elapsed time after attack")
	var huge:=PackedVector2Array();huge.resize(trace.MAX_VERTICES+1)
	trace.advance(.016,[huge],true)
	check(trace.snapshots.is_empty(),"complexity guard skips expensive echoes without changing real weapon geometry")
	trace.advance(.016,paths,true);trace.clear()
	check(trace.snapshots.is_empty(),"cancellation can remove every old echo")
	var game=load("res://scenes/main.tscn").instantiate();game.onboarding.persist=false;root.add_child(game)
	await process_frame
	game.set_physics_process(false);game.combat.set_natives(false);game.feedback.audio_enabled=false
	game.equipped_weapon=PaperWeaponGrip.practice_sword()
	game.combat.attack(Vector2.RIGHT);game.combat.swing=.2
	var held=game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	game.character_visual.sample_weapon();held._process(.016)
	check(held.trace.snapshots.is_empty(),"headless authority never allocates optional render echoes")
	var collision_before:Array=held.world_paths().duplicate(true)
	held.trace.clear()
	check(held.world_paths()==collision_before,"visual history never changes sampled hit geometry")
	game.equipped_weapon=PaperWeaponGrip.practice_sword();game.equipped_weapon.weapon_type="bow"
	held._process(.016)
	check(held.trace.snapshots.is_empty(),"equipping a bow clears old melee contours")
	var saved_objects:Array=game.objects
	game.objects=[{"role":"building","kind":"freehand","x":-2.0,"y":-1.0,"health":120.0}]
	game.feedback.events.clear()
	var contact_api:=false
	for method in game.combat.get_method_list():
		if method.name=="damage_building":contact_api=method.args.size()>=3
	if contact_api:game.combat.damage_building(0,10,Vector2(2.5,.3))
	else:game.combat.damage_building(0,10)
	check(game.feedback.events.back().world==Vector2(2.5,.3),"off-center building impact uses actual contact rather than object origin")
	game.objects=saved_objects
	game.player.position=Vector2.ZERO
	game.feedback.events.clear()
	game.combat.hurt_player(10,Vector2.RIGHT,Vector2(.1,.35))
	check(game.feedback.events.back().world==Vector2(.1,.35),"impact feedback uses actual collision contact rather than body center")
	game.queue_free();await process_frame
	print("WEAPON TRACE: ",count," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
