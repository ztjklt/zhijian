extends SceneTree

var failures: Array[String] = []
var count := 0
class Fixture extends Node2D:
	const GROUND_Y := -2.8
	var object_nodes: Array = []
	var feedback = null
	var PIXELS_PER_UNIT := 78.0
	func world_to_screen(p: Vector2) -> Vector2: return Vector2(p.x * 78, 400 - p.y * 78)

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("MEDIEVAL WORLD: " + label)
func ticks(world, count_ticks: int) -> void:
	for i in count_ticks:
		world.step(1.0 / 60)
		await physics_frame
func first_kind(world, kind: String):
	for entity in world.entities:
		if entity.kind == kind: return entity
	return null
func run() -> void:
	var path := "res://scripts/medieval_world.gd"
	check(ResourceLoader.exists(path), "independent medieval world implementation exists")
	if not ResourceLoader.exists(path): finish(); return
	var fixture := Fixture.new()
	root.add_child(fixture)
	var world = load(path).new()
	world.game = fixture
	fixture.add_child(world)
	await process_frame
	check(world.entities.size() > 20, "separate map contains an inhabited village and assembled castle")
	for kind in ["oak", "pine", "house", "market", "castle_piece", "barrel", "crate", "villager", "horse", "wagon", "dragon", "driver"]:
		check(first_kind(world, kind) != null, "map contains attackable " + kind)
	for sample in [{"kind":"market","point":Vector2(0,1.5)},{"kind":"house","point":Vector2(2.0,3.1)},{"kind":"oak","point":Vector2(1.5,1.15)}]:
		var subject = first_kind(world,sample.kind)
		var visual = subject.get("render_polygons")
		var covered := false
		if visual is Array:
			for polygon in visual:
				if Geometry2D.is_point_in_polygon(sample.point,polygon): covered = true
		check(not subject.contains_world_point(subject.position+sample.point) and covered, "original "+sample.kind+" art remains visible outside simplified physical silhouette")
	var wagon_art = first_kind(world,"wagon")
	var wagon_right := false
	if wagon_art.has_method("texture_uv"):
		wagon_art.facing = 1
		wagon_right = wagon_art.texture_uv(Vector2(1,0)).x < wagon_art.texture_uv(Vector2(-1,0)).x
	check(wagon_right, "wagon source left shafts flip toward a right walking horse")
	for section in world.SECTIONS:
		var spawn:Vector2=world.safe_spawn_position(section.x)
		var shape:=RectangleShape2D.new();shape.size=Vector2(0.44,1.02)
		var query:=PhysicsShapeQueryParameters2D.new()
		query.shape=shape;query.transform=Transform2D(0,spawn+Vector2(0,0.03));query.collision_mask=1;query.margin=0
		check(root.world_2d.direct_space_state.intersect_shape(query).is_empty(),"navigation to "+section.name+" starts clear of actual walking colliders")
	for actor in world.entities:
		if actor.kind not in ["villager","horse"]:continue
		var minimum:=INF
		for polygon in actor.world_polygons():
			for point in polygon:minimum=minf(minimum,point.y-world.terrain.travel_height(point.x))
		check(minimum>=-0.08 and (actor.collision_mask & (64|128))==0,"initial "+actor.entity_id+" uses ground support without facade/actor blocking")
	var seated = first_kind(world,"driver")
	check(seated.collision_layer != 0,"seated driver remains a real target for falling drawn rigid bodies")
	var patrol_horse=first_kind(world,"horse")
	var original_home:float=patrol_horse.home_x
	var original_width:float=patrol_horse.patrol_half_width
	var horse_start:float=patrol_horse.position.x
	patrol_horse.home_x=horse_start;patrol_horse.patrol_half_width=0.45;patrol_horse.facing=1
	var turned:=false
	for i in 180:
		await ticks(world,1)
		if patrol_horse.facing<0:turned=true;break
	check(turned and patrol_horse.position.x>horse_start+0.3,"horse traverses road and reverses at its authored patrol endpoint")
	var patrol_cart=first_kind(world,"wagon")
	world.step(1.0/60)
	check(absf(patrol_cart.position.x-(patrol_horse.position.x-patrol_horse.facing*2.3))<0.1,"wagon follows its horse after patrol reversal")
	patrol_horse.home_x=original_home;patrol_horse.patrol_half_width=original_width
	# Retain legacy module damage/restore coverage apart from the new atlas castle.
	var wall = world._spawn("wall",95.0,9000,20.0)
	var a: Vector2 = wall.position + Vector2(-1.6, 0.65)
	var b: Vector2 = wall.position + Vector2(1.6, 0.65)
	var before: Dictionary = world.segment_contact(a, b)
	check(before.get("entity") == wall, "projectile contacts the nearest wall part")
	fixture.feedback = PaperCreationFeedback.new()
	fixture.feedback.audio_enabled = false
	fixture.add_child(fixture.feedback)
	fixture.feedback.set_process(false) # This fixture verifies event dispatch, with no camera/player renderer attached.
	var wall_health: float = wall.health
	world.damage_entity(wall, 22, wall.position + Vector2(-wall.size.x * 0.5, 0.65), Vector2.RIGHT * 4)
	check(wall.health < wall_health and not wall.cuts.is_empty(), "partial wall hit records a local cut")
	check(not fixture.feedback.events.is_empty() and fixture.feedback.events.back().kind == "hit", "medieval damage emits existing hit feedback")
	var cut_probe: Vector2 = wall.position + Vector2(-wall.size.x * 0.5 + 0.08, 0.65)
	check(not wall.contains_world_point(cut_probe), "visible notch removes contact geometry")
	var cut_visible := false
	if wall.get("render_polygons") is Array:
		for polygon in wall.render_polygons:
			if Geometry2D.is_point_in_polygon(wall.to_local(cut_probe),polygon): cut_visible = true
	check(not cut_visible,"same damage polygon removes the original texture and physical wall")
	var space := root.world_2d.direct_space_state
	await physics_frame
	var params := PhysicsPointQueryParameters2D.new()
	params.position = cut_probe
	params.collision_mask = 128
	var still_solid := false
	for hit in space.intersect_point(params):
		if hit.collider == wall: still_solid = true
	check(not still_solid, "actual physics also excludes the visible local notch")
	check(wall.contains_world_point(wall.position + Vector2(0.6, 0.9)), "unhit wall geometry remains intact")
	var sweep: Dictionary = world.blade_contact([PackedVector2Array([a, a + Vector2(0, 0.15)])], [PackedVector2Array([b, b + Vector2(0, 0.15)])])
	check(sweep.get("entity") == wall, "full blade sweeps contact surviving geometry")
	var villager = first_kind(world, "villager")
	world.damage_entity(villager, 10, villager.position + Vector2(0, 0.5), Vector2(-6, 3))
	check(villager.linear_velocity.x < 0 and villager.linear_velocity.y > 0 and villager.state == "hurt", "actor damage causes directional physical knockback and hurt state")
	world.damage_entity(villager, 100, villager.position, Vector2(4, 2))
	check(fixture.feedback.events.any(func(e):return e.kind=="break") and fixture.feedback.events.back().kind=="voice", "slain medieval actor retains break feedback and adds its death voice")
	await ticks(world, 110)
	check(not villager.alive and villager.state == "dead" and villager.frame_index() == 6, "slain actor settles into generated prone death frame without respawning")
	var driver = first_kind(world, "driver")
	var wagon_for_driver = first_kind(world, "wagon")
	if driver != null:
		await ticks(world, 2)
		check(absf(driver.position.x-wagon_for_driver.position.x) < 1.0, "living coachman rides the actual moving wagon")
		# Isolate the mounted body mode transition from village scenery collisions.
		var impact_horse = first_kind(world,"horse")
		var village_entities: Array = world.entities
		world.entities = [impact_horse,wagon_for_driver,driver]
		impact_horse.position=Vector2(30.0,world.terrain.support_pose(30.0,impact_horse.size.x*0.335,0.05).position_y)
		impact_horse.home_x=30.0;impact_horse.patrol_half_width=0.2
		impact_horse.linear_velocity=Vector2.ZERO
		PhysicsServer2D.body_set_state(impact_horse.get_rid(),PhysicsServer2D.BODY_STATE_TRANSFORM,Transform2D(0,impact_horse.position))
		impact_horse.facing = 1
		world.step(1.0/60)
		await physics_frame
		var driver_health: float = driver.health
		var striker := BuildObject.new()
		var from: Vector2 = driver.position+Vector2(driver.facing*0.65,1.0)
		check(world.segment_contact(from,driver.position+Vector2(0,1.0)).get("entity")==driver,"mounted-driver impact approaches actual exposed silhouette")
		striker.setup({"x":from.x,"y":from.y,"dynamic":true,"kind":"freehand","paths":[{"points":[Vector2(-0.13,-0.13),Vector2(0.13,-0.13),Vector2(0.13,0.13),Vector2(-0.13,0.13),Vector2(-0.13,-0.13)],"collision":true}]})
		fixture.add_child(striker)
		# Exclude village scenery so the small impact fixture tests the mounted body.
		for other in village_entities:
			if other!=driver: striker.add_collision_exception_with(other)
		striker.linear_velocity = Vector2(-driver.facing*8,0)
		fixture.object_nodes.append(striker)
		await ticks(world,8)
		check(driver.health < driver_health and driver.companion_id == "" and not driver.freeze,"actual drawn impact detaches the mounted driver without unsafe query mutation")
		world.entities = village_entities
		fixture.object_nodes.erase(striker)
		striker.queue_free()
		await process_frame
		driver.linear_velocity = Vector2.ZERO
		world.damage_entity(driver, 8, driver.position+Vector2(0,0.3), Vector2(-3,2))
		check(driver.companion_id == "" and driver.linear_velocity.x < 0, "struck coachman separates physically from wagon")
	var horse = first_kind(world, "horse")
	var wagon = first_kind(world, "wagon")
	world.damage_entity(horse, 1000, horse.position, Vector2(-2, 3))
	var wagon_x: float = wagon.position.x
	await ticks(world, 60)
	check(not horse.alive and absf(wagon.position.x - wagon_x) < 0.1, "wagon stops following when its horse is slain")
	# An actual BuildObject falls onto the otherwise undamaged castle wall.
	var impact_wall = world._spawn("wall",98.0,9001,20.0)
	var ink := BuildObject.new()
	ink.setup({"x": impact_wall.position.x, "y": impact_wall.position.y+4.3, "kind": "freehand", "dynamic": true, "paths": [{"points": [Vector2(-0.35,-0.25),Vector2(0.35,-0.25),Vector2(0.35,0.25),Vector2(-0.35,0.25),Vector2(-0.35,-0.25)], "collision": true}]})
	fixture.add_child(ink)
	fixture.object_nodes.append(ink)
	var initial_hp: float = impact_wall.health
	await ticks(world, 95)
	check(impact_wall.health < initial_hp, "real falling drawn rigid body damages contacted medieval structure")
	ink.freeze = true
	ink.linear_velocity = Vector2.ZERO
	var resting_hp: float = impact_wall.health
	await ticks(world, 45)
	check(is_equal_approx(impact_wall.health, resting_hp), "resting drawn object does not repeat damage each frame")
	var dragon = first_kind(world, "dragon")
	world.damage_entity(dragon, 1000, dragon.position, Vector2(1,-2))
	await ticks(world, 90)
	var dragon_frame: int = dragon.frame_index()
	await ticks(world, 10)
	check(not dragon.alive and dragon.state == "dead" and dragon.frame_index() == dragon_frame, "dead dragon stops its flight loop and retains a fallen final pose")
	var saved: Array = world.save_state()
	check(world.validate_state(saved), "live damaged/dead map serializes to validated portable state")
	var encoded: Array = JSON.parse_string(JSON.stringify(saved))
	check(world.restore_state(encoded), "JSON roundtrip restores complete map state")
	check(not first_kind(world, "villager").alive and world.entities.any(func(e): return e.kind=="wall" and not e.cuts.is_empty()), "death and exact cut geometry survive restoration")
	check(first_kind(world,"driver").gravity_scale == 1 and first_kind(world,"driver").collision_mask == 9 and not first_kind(world,"driver").freeze,"detached living driver restores ordinary gravity and ground collision")
	var dead_records := encoded.duplicate(true)
	for record in dead_records:
		if record.kind == "driver": record.health = 0; record.alive = false; record.state = "dead"
	check(world.restore_state(dead_records) and first_kind(world,"driver").gravity_scale == 1 and first_kind(world,"driver").collision_mask == 9 and not first_kind(world,"driver").freeze,"dead driver also restores gravity and ground collision")
	var good: String = JSON.stringify(world.save_state())
	var bad := encoded.duplicate(true)
	bad.append(bad[0].duplicate(true))
	check(not world.restore_state(bad) and JSON.stringify(world.save_state()) == good, "duplicate IDs reject transactionally without replacing healthy state")
	bad = encoded.duplicate(true)
	bad[0].x = NAN
	check(not world.restore_state(bad), "nonfinite coordinates cannot enter physics through map saves")
	bad = encoded.duplicate(true)
	bad[0].cuts = [{"x": 1000, "y": 0, "radius": 100, "side": 0}]
	check(not world.restore_state(bad), "out of bounds or oversized damage cut is rejected")
	fixture.queue_free()
	await process_frame
	finish()
func finish() -> void:
	print("MEDIEVAL WORLD: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
