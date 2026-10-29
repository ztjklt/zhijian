extends SceneTree
## Catches flat support, phantom water floors, unoccluded hits and repeat migration.
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("MEDIEVAL FUSION: "+label)
func finish() -> void:
	print("MEDIEVAL FUSION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func ray(game, x: float, top: float, bottom: float, omit: RID=RID()) -> Dictionary:
	var query:=PhysicsRayQueryParameters2D.create(Vector2(x,top),Vector2(x,bottom),1)
	var excluded:Array[RID]=[game.player.get_rid()]
	for entity in game.medieval_world.entities: excluded.append(entity.get_rid())
	if omit.is_valid(): excluded.append(omit)
	query.exclude=excluded
	return game.get_world_2d().direct_space_state.intersect_ray(query)
func run() -> void:
	check(ResourceLoader.exists("res://scripts/medieval_terrain.gd"),"shared real terrain module exists")
	if not ResourceLoader.exists("res://scripts/medieval_terrain.gd"): finish(); return
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await physics_frame
	game.set_physics_process(false)
	game.player.freeze = true
	var world = game.medieval_world
	var terrain = world.terrain
	# This fixture isolates the original terrain/controller contracts. The full
	# authored population and nine inhabited routes have their own product tests.
	for entity in world.entities.duplicate():
		if entity.kind in ["rabbit","deer","bat"] or (entity.kind!="castle_piece" and int(entity.entity_id.get_slice("-",1))>=100):
			world.entities.erase(entity);world.remove_child(entity);entity.queue_free()
	await process_frame
	await physics_frame
	check(absf(terrain.surface_height(10)-terrain.surface_height(30))>1,"forest hill is real elevation above village")
	check(terrain.surface_height(76)>3,"castle is built on high plateau")
	check(terrain.surface_height(60)<-4,"riverbed lies beneath old flat ground")
	check(game.ground_chunks.is_empty(),"medieval world has no hidden old flat floor chunks")
	var below_deck := ray(game,60,-1.0,-8)
	check(not below_deck.is_empty() and absf(below_deck.position.y+4.3)<0.05,"ray through water reaches riverbed without phantom flat floor")
	var bridge := ray(game,60,4,-1)
	check(not bridge.is_empty() and bridge.position.y>0.9,"physical bridge crosses above water")
	check(absf(game.ground_height_at(60)-bridge.position.y)<0.05,"core spawn ground uses real navigable bridge")
	game.player.freeze=false
	game.player.reset_movement()
	game.player.position=Vector2(14,terrain.support_height(14,.27)+.52)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	game.player.linear_velocity=Vector2.ZERO
	for i in 25: await physics_frame
	var walking_start:Vector2=game.player.position
	Input.action_press("move_left")
	for i in 20:
		game._physics_process(1.0/60)
		await physics_frame
	Input.action_release("move_left")
	check(game.player.position.x<walking_start.x-1 and game.player.position.y>walking_start.y+0.15,"real controller walks uphill on visible forest profile")
	game.player.freeze=true
	var hill_ink:=BuildObject.new()
	hill_ink.setup({"x":11.0,"y":terrain.travel_height(11.0)+2.5,"kind":"freehand","dynamic":true,"paths":[{"points":[Vector2(-0.1,-0.1),Vector2(0.1,-0.1),Vector2(0.1,0.1),Vector2(-0.1,0.1),Vector2(-0.1,-0.1)],"collision":true}]})
	game.add_child(hill_ink)
	for i in 90: await physics_frame
	var ink_ground:=ray(game,hill_ink.position.x,hill_ink.position.y+0.1,-8,hill_ink.get_rid())
	check(not ink_ground.is_empty() and hill_ink.position.y-ink_ground.position.y>0.04 and hill_ink.position.y-ink_ground.position.y<0.4,"real drawn brick settles on hillside rather than historical flat floor")
	hill_ink.queue_free()
	var body := RigidBody2D.new()
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new(); box.size=Vector2(0.3,0.3); collider.shape=box
	body.add_child(collider); body.position=Vector2(60,-2); body.gravity_scale=1
	game.add_child(body)
	body.linear_velocity=Vector2(4,-3)
	terrain.apply_water_body(body,0.1)
	check(body.linear_velocity.x<4 and body.linear_velocity.y>-3,"entering real water adds drag and buoyancy")
	check(not terrain.ripples.is_empty(),"water entry produces bounded ripple feedback")
	body.queue_free()
	for section in world.SECTIONS:
		var spawn: Vector2=world.safe_spawn_position(section.x)
		check(spawn.y>=terrain.travel_height(spawn.x)+0.5,"safe navigation stays above shared surface at "+section.name)
		var shape:=RectangleShape2D.new();shape.size=Vector2(0.5,1.04)
		var query:=PhysicsShapeQueryParameters2D.new()
		query.shape=shape;query.transform=Transform2D(0,spawn+Vector2(0,0.04));query.collision_mask=1;query.margin=0
		check(game.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),"safe navigation avoids real walking surfaces at "+section.name)

	# A real player can enter the river through the timber route; soil never drops.
	game.player.freeze=false
	game.player.reset_movement()
	game.player.position=Vector2(62,terrain.travel_height(62)+0.33)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	game.player.linear_velocity=Vector2.ZERO
	for i in 35: await physics_frame
	check(not game.player.support_bodies().is_empty(),"real hero stands on sloping bridge")
	check(game.player.begin_drop_through(),"bridge can be down-passed without ignoring riverbank soil")
	game.player.linear_velocity=Vector2(0,-3)
	for i in 50:
		game.player.update_drop_through(1.0/60)
		world.step(1.0/60)
		await physics_frame
	check(game.player.position.y<terrain.travel_height(62)-0.7,"hero passes below deck into actual river basin")
	game.player.position=Vector2(60,-2)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	game.player.linear_velocity=Vector2.ZERO
	Input.action_press("move_right")
	game._physics_process(1.0/60)
	Input.action_release("move_right")
	check(game.player.linear_velocity.x<4.59 and game.player.linear_velocity.x>3,"actual movement input retains horizontal water drag")
	game.player.freeze=true
	var walker=world.entity_by_id("villager-4")
	walker.home_x=160.3
	walker.position=Vector2(160.3,terrain.support_height(160.3,walker.size.x*0.335)-0.045)
	walker.linear_velocity=Vector2.ZERO
	walker.facing=1
	PhysicsServer2D.body_set_state(walker.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,walker.position))
	var walker_start:Vector2=walker.position
	var horse=world.entity_by_id("horse-0")
	# Earlier free-running physics checks must not choose this slope fixture's
	# starting patrol phase. Put the real horse on the intended bridge section.
	var horse_pose:Dictionary=terrain.support_pose(60,horse.size.x*.335,.05)
	horse.position=Vector2(60,horse_pose.position_y)
	horse.rotation=horse_pose.rotation
	horse.home_x=60;horse.facing=1;horse.linear_velocity=Vector2.ZERO
	horse.patrol_turn_cooldown=3.0
	PhysicsServer2D.body_set_state(horse.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,horse.global_transform)
	var horse_start:Vector2=horse.position
	for i in 120:
		world.step(1.0/60)
		await physics_frame
	check(walker.position.x>walker_start.x+0.5 and walker.position.y>walker_start.y+0.08,"real villager climbs hillside with tangent movement and ground support")
	check(horse.position.y>horse_start.y+0.12 and horse.rotation>0.2 and absf(horse.to_global(Vector2(horse.size.x*0.335,0.05)).y-terrain.travel_height(horse.to_global(Vector2(horse.size.x*0.335,0.05)).x))<0.1,"horse physically climbs sloping bridge")
	var wagon=world.entity_by_id("wagon-0")
	check(wagon.position.y>0 and wagon.rotation>0.2,"cart inclines visibly with the sloping bridge")
	for wheel in wagon.polygons.slice(0,2):
		var wheel_gap:=INF
		for local in wheel:
			var contact:Vector2=wagon.to_global(local)
			wheel_gap=minf(wheel_gap,contact.y-terrain.travel_height(contact.x))
		check(absf(wheel_gap)<0.015,"actual front and rear cart wheels contact matching ground")
	walker.alive=false;walker.health=0;walker.state="dead"
	walker.position=Vector2(16,terrain.surface_height(16))
	walker.rebuild_geometry()
	check(absf(world.safe_spawn_position(16).x-16)<0.05,"fallen people no longer obstruct safe ground navigation")
	var old:Array=world.save_state().filter(func(record): return record.kind != "castle_piece")
	# Actual pre-fusion records had legacy wall modules, never atlas tile kinds.
	var legacy_wall := MedievalEntity.new()
	legacy_wall.setup("wall",Vector2(82.02,-2.8),"wall-2",-2.8)
	old.append(legacy_wall.save_record())
	legacy_wall.free()
	for record in old:
		record.y=-2.8
		if record.kind=="wall": record.health=220;record.cuts=[{"x":0.0,"y":0.5,"radius":0.3,"side":0}]
		if record.kind=="villager": record.alive=false;record.health=0;record.state="dead"
	check(world.restore_state(old,1),"legacy flat entity records migrate")
	var migrated:Array=world.save_state()
	var dead_retained:=false
	var cut_retained:=false
	for record in migrated:
		if record.kind=="wall": cut_retained=not record.cuts.is_empty() and record.y>3
		if record.kind=="villager": dead_retained=not record.alive and record.health==0
	check(cut_retained and dead_retained,"legacy migration retains cuts and deaths while raising castle")
	check(world.restore_state(migrated,3) and JSON.stringify(migrated)==JSON.stringify(world.save_state()),"current terrain version restores exact positions without another offset")
	var hill_top:=Vector2(10,terrain.surface_height(10)+1)
	var hill_bottom:=Vector2(10,terrain.surface_height(10)-1)
	var contact:Dictionary=world.segment_contact(hill_top,hill_bottom)
	check(contact.get("index",0)==-1,"hill contact is immutable terrain category")
	var hit:Dictionary=game.combat.first_structure(hill_top,hill_bottom)
	check(hit.get("index",0)==-1,"arrow route identifies hill before any target")
	var blade:Dictionary=game.combat._blade_structure([PackedVector2Array([hill_top,hill_top+Vector2(.1,0)])],[PackedVector2Array([hill_bottom,hill_bottom+Vector2(.1,0)])],hill_top)
	check(blade.get("index",0)==-1,"full sword sweep contacts real hillside")
	# Legacy map boundaries migrate authored objects, player and camera together.
	var legacy:Dictionary=game.snapshot()
	legacy.world.terrain_version=1
	legacy.world.entities=old
	legacy.player_position=Vector2(76,-2.26)
	legacy.camera_position=Vector2(76,0)
	legacy.objects=[{"x":76.0,"y":-1.8,"kind":"freehand","dynamic":false,"paths":[{"points":[Vector2(-0.2,0),Vector2(0.2,0)],"collision":true}]}]
	game.select_world("paper")
	game.restore(legacy)
	check(game.player.position.y>=3.94 and game.player.position.y<4.1 and absf(game.camera_y-6.2)<0.001,"legacy player and camera move once with elevated castle")
	check(absf(game.objects[0].y-4.4)<0.001,"legacy authored object rises with matching terrain")
	var current_save:Dictionary=game.snapshot()
	var current_position:Vector2=game.player.position
	game.select_world("paper")
	game.restore(current_save)
	check(game.player.position.is_equal_approx(current_position) and absf(game.objects[0].y-4.4)<0.001 and absf(game.camera_y-6.2)<0.001,"current snapshot roundtrip keeps object player camera unchanged")
	var inactive_world:Dictionary=legacy.world.duplicate(true)
	inactive_world.player_y=-2.26;inactive_world.camera_y=0
	game.select_world("paper")
	game.map_workspaces={"medieval-v1":{"objects":legacy.objects.duplicate(true),"world":inactive_world,"player_x":76.0,"camera_x":76.0}}
	game.change_map("medieval-v1")
	check(game.player.position.y>=3.94 and game.player.position.y<4.1 and absf(game.objects[0].y-4.4)<0.001 and absf(game.camera_y-6.2)<0.001,"inactive legacy workspace migrates player objects camera on entering")
	game.change_map("knowledge-v1")
	game.change_map("medieval-v1")
	check(game.player.position.y>=3.94 and game.player.position.y<4.1 and absf(game.objects[0].y-4.4)<0.001 and game._world_details().terrain_version==3,"workspace reentry preserves upgraded positions without repeated migration")
	game.queue_free();await process_frame
	finish()
