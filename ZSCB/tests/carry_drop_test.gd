extends "res://tests/carry_activity_test.gd"

func fresh(at: Vector2) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.player.position = at
	game.camera_x = at.x
	game.set_draw_mode(3)
	draw_block(at + Vector2(2, 0))
	game.set_draw_mode(4)
	game.selected = 0
	check(game.toggle_carry(), "real local drawing can be picked up for drop checks")

func wall_at(point: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = point
	var fixture := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1.2, 1.2)
	fixture.shape = shape
	wall.add_child(fixture)
	game.add_child(wall)
	return wall

func touches(body: RigidBody2D, obstacle: CollisionObject2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 1 | 2 | 8 | 16 | 64 | 128
	query.exclude = [body.get_rid()]
	for fixture in body.get_children():
		if not fixture is CollisionShape2D: continue
		query.shape = fixture.shape
		query.transform = body.transform * fixture.transform
		for hit in game.get_world_2d().direct_space_state.intersect_shape(query):
			if hit.collider == obstacle: return true
	return false

func dispose() -> void:
	game.queue_free()
	await process_frame

func run() -> void:
	await fresh(Vector2(0, 2))
	var held: RigidBody2D = game.object_nodes[0]
	var requested := held.position + Vector2(game.CARRY_DROP_OFFSET, 0)
	var wall := wall_at(requested)
	for frame in 3: await physics_frame
	check(game.drop_carried(), "obstructed drop can use the nearest legal translation")
	check(held.position.distance_to(requested) > .8, "successful drop uses the actual safe displacement")
	check(not touches(held, wall), "successfully dropped body does not overlap the real wall")
	check(Vector2(game.objects[0].x, game.objects[0].y).is_equal_approx(held.position), "drop data and physical body use the same safe coordinates")
	await dispose()

	await fresh(Vector2(0, -2.26))
	held = game.object_nodes[0]
	check(game.drop_carried(), "ground-level drop resolves a legal position")
	check(held.position.y >= game.GROUND_Y + .29, "safe ground correction is applied before restoring collision")
	await dispose()

	await fresh(Vector2(0, 2))
	held = game.object_nodes[0]
	var key: String = game.carried_id
	var position := held.position
	var paths: Array = game.objects[0].paths.duplicate(true)
	game.objects[0].paths = []
	check(not game.drop_carried(), "invalid drop geometry is rejected")
	check(game.carried_id == key and held.position == position and held.freeze, "rejected drop keeps identity, position and frozen state")
	check(held.collision_layer == 0 and held.collision_mask == 0, "rejected drop keeps the held body nonblocking")
	game.objects[0].paths = paths
	check(game.drop_carried(), "a rejected drop can be retried after geometry is valid")
	await finish()
