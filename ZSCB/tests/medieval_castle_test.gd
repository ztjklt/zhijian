extends SceneTree
## Real map fixtures and hand-drawn rigid-body impact, never the user's save.
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("MEDIEVAL CASTLE: "+label)
func ticks(world,count: int) -> void:
	for i in count:
		world.step(1.0/60.0)
		await physics_frame
func run() -> void:
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await physics_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var world = game.medieval_world
	var castle: Array = world.entities.filter(func(entity):return entity.kind == "castle_piece")
	var ids := {}
	var roof = null
	var top := -INF
	var base := INF
	for part in castle:
		ids[part.entity_id] = true
		base = minf(base,part.position.y)
		for polygon in part.world_polygons():
			for point in polygon:
				if point.y > top:
					top = point.y
					roof = part
	check(castle.size() == MedievalCastleLayout.records().size(),"fresh castle instantiates every occupied atlas tile")
	check(castle.size() >= 20,"grand castle contains at least 20 separately destructible modules")
	check(top-base >= 10.0,"grand castle rises at least ten metres above its footing")
	check(world.entities.size() <= 384,"castle stays within the validated world entity budget")
	if roof == null:
		game.queue_free()
		await process_frame
		print("MEDIEVAL CASTLE TESTS: ",checks," checks, ",failures.size()," failures")
		quit(1)
		return
	var entry := MedievalCastleLayout.entry_position()
	var space := root.world_2d.direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var body := RectangleShape2D.new()
	body.size = Vector2(0.46,1.08)
	query.shape = body
	query.transform = Transform2D(0,entry+Vector2(0,0.6))
	query.collision_mask = 1
	var clear_lane := false
	for offset in [0.0,-0.64,0.64]:
		query.transform = Transform2D(0,entry+Vector2(offset,0.6))
		if space.intersect_shape(query).is_empty(): clear_lane = true
	check(clear_lane,"the central gate fits an actual player beside its living guard")
	# Use the actual building confirmation flow, including its twelve-metre limit.
	# Climbing onto the wing walk brings a hand-drawn brick above the keep in reach.
	var balcony: Dictionary = MedievalCastleLayout.role_positions()[0]
	game.player.position = Vector2(balcony.x+0.8,balcony.y+0.56)
	PhysicsServer2D.body_set_state(game.player.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,game.player.position))
	var center := Vector2(roof.position.x,top+4.0)
	check(center.distance_to(game.player.position)<DrawingRules.BUILD_RANGE,"a giant brick above the keep is within drawing reach from the wall walk")
	game.set_draw_mode(3)
	game.build_kind = "freehand"
	game.draft = [{"points":[center+Vector2(-2.4,-0.65),center+Vector2(2.4,-0.65),center+Vector2(2.4,0.65),center+Vector2(-2.4,0.65),center+Vector2(-2.4,-0.65)]}]
	game.generate()
	check(game.object_nodes.size()==1 and game.draft.is_empty(),"normal building confirmation creates the giant brick and clears its successful draft")
	if game.object_nodes.is_empty():
		game.queue_free(); await process_frame
		quit(1); return
	var brick: RigidBody2D = game.object_nodes[0]
	check(is_equal_approx(game.object_bounds(game.objects[0]).size.x,4.8),"normal generation preserves the drawn brick width")
	var health: float = roof.health
	await ticks(world,135)
	check(roof.health < health,"a real giant drawn brick damages the exposed castle roof")
	check(not roof.cuts.is_empty(),"giant brick impact creates a local visible and physical roof notch")
	check(castle.filter(func(part):return part.alive).size() > 15,"smashing one roof leaves the surrounding castle intact")
	brick.freeze = true
	brick.linear_velocity = Vector2.ZERO
	var resting_health: float = roof.health
	await ticks(world,40)
	check(is_equal_approx(roof.health,resting_health),"a resting giant brick cannot damage the roof every frame")
	game.object_nodes.erase(brick)
	game.objects.clear()
	brick.queue_free()
	await physics_frame
	# Verify the exposed notch against the same target's original texture mask,
	# real shape and surviving sword-contact geometry, away from adjacent tiers.
	var wall = world.entity_by_id("castle-piece-25")
	var hit_at: Vector2 = wall.position+Vector2(-wall.size.x*0.5,wall.size.y*0.5)
	world.damage_entity(wall,35,hit_at,Vector2.RIGHT)
	var gap: Vector2 = hit_at+Vector2(0.06,0)
	check(not wall.contains_world_point(gap),"wall notch excludes actual sword contact geometry")
	var visible := false
	for polygon in wall.render_polygons:
		if Geometry2D.is_point_in_polygon(wall.to_local(gap),polygon): visible = true
	check(not visible,"the same notch reveals paper through the original GPT wall art")
	await physics_frame
	var point := PhysicsPointQueryParameters2D.new()
	point.position = gap
	point.collision_mask = 1
	check(not space.intersect_point(point).any(func(hit):return hit.collider == wall),"the visible notch also removes the real wall fixture")
	var surviving: Vector2 = wall.position+Vector2(0.55,wall.size.y*0.72)
	check(wall.contains_world_point(surviving),"unhit castle geometry remains solid after a local breach")
	var short_blade: Array = [PackedVector2Array([gap+Vector2(0,-0.03),gap+Vector2(0,0.03)])]
	check(world.blade_contact(short_blade,short_blade,gap).is_empty(),"actual sword geometry passes through the same exposed local notch")
	var survivor_count: int = castle.filter(func(part):return part.alive).size()
	world.damage_entity(wall,1000,surviving,Vector2.RIGHT)
	check(not wall.alive and castle.filter(func(part):return part.alive).size() == survivor_count-1,"destroying one atlas tile removes exactly one castle part")
	var saved: Array = world.save_state()
	check(world.validate_state(saved),"variable castle tile sizes and cuts produce valid saved records")
	var invalid: Array = saved.duplicate(true)
	for record in invalid:
		if record.kind == "castle_piece": record.id = "castle-piece-999"; break
	check(not world.validate_state(invalid),"unknown castle tile identities are rejected before creating physics")
	var roof_id: String = roof.entity_id
	var roof_health: float = roof.health
	check(world.restore_state(JSON.parse_string(JSON.stringify(saved))),"castle damage survives a complete JSON save and restore")
	var restored_roof = world.entity_by_id(roof_id)
	var restored_wall = world.entity_by_id("castle-piece-25")
	check(restored_roof != null and is_equal_approx(restored_roof.health,roof_health) and not restored_roof.cuts.is_empty(),"the exact roof identity retains giant-brick damage after restoration")
	check(restored_wall != null and not restored_wall.alive and not restored_wall.cuts.is_empty(),"destroyed atlas tile and its local notch stay destroyed after restoration")
	game.queue_free()
	await process_frame
	print("MEDIEVAL CASTLE TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
