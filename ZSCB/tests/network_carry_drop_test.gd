extends "res://tests/network_carry_test.gd"
var room
var owner: Dictionary
var held: RigidBody2D

func fresh(label: String) -> void:
	room = PaperNetRoom.new()
	room.configure("CARRY01", "paper", "fixture-owner", PaperWorldStore.new("user://carry-drop-" + label), "fixture-world")
	root.add_child(room)
	room.set_physics_process(false)
	owner = room.join("", "甲")
	room.ready(owner.player_id)
	var actor = room.actors[owner.player_id]
	actor.player.freeze = true
	actor.player.position = Vector2(0, 2)
	var object := {"id":"wire-drop", "structure_id":"part-drop", "author":owner.player_id, "kind":"freehand", "role":"building", "dynamic":true, "x":2.0, "y":2.0, "angle":0.0, "health":120.0, "max_health":120.0, "version":1, "paths":[{"points":[Vector2(-.3,-.3),Vector2(.3,-.3),Vector2(.3,.3),Vector2(-.3,.3),Vector2(-.3,-.3)],"collision":true}]}
	room.world.objects.append(object)
	held = room.world.build_object_scene.instantiate()
	held.setup(object)
	room.world.object_nodes.append(room.world._attach_body(held,object))
	actor.objects = room.world.objects
	actor.object_nodes = room.world.object_nodes
	check(room.command(owner.player_id,{"op":"carry","action":"pick","id":"wire-drop","version":1,"seq":1}).ok, "authority picks a real body with distinct wire/structure identities")

func wall_at(point: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = point
	var fixture := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1.2,1.2)
	fixture.shape = shape
	wall.add_child(fixture)
	room.world.add_child(wall)
	return wall

func touches(obstacle: CollisionObject2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 1
	query.exclude = [held.get_rid()]
	for fixture in held.get_children():
		if not fixture is CollisionShape2D: continue
		query.shape = fixture.shape
		query.transform = held.transform * fixture.transform
		for hit in room.world.get_world_2d().direct_space_state.intersect_shape(query):
			if hit.collider == obstacle: return true
	return false

func dispose() -> void:
	room.queue_free()
	await process_frame

func run() -> void:
	await fresh("offset")
	var requested := held.position + Vector2(.42,0)
	var wall := wall_at(requested)
	for frame in 3: await physics_frame
	var result: Dictionary = room.command(owner.player_id,{"op":"carry","action":"drop","id":"wire-drop","version":1,"seq":2})
	check(result.ok, "authority accepts a drop with a safe translated destination")
	check(held.position.distance_to(requested) > .8 and not touches(wall), "authority moves the actual body out of the obstruction")
	check(Vector2(room.world.objects[0].x,room.world.objects[0].y).is_equal_approx(held.position), "authority body and stored object agree immediately")
	check(room.actors[owner.player_id].carried_id == "" and not room.locks.has("wire-drop"), "successful authoritative drop clears carry ownership")
	await dispose()
	await fresh("reject")
	var paths: Array = room.world.objects[0].paths.duplicate(true)
	room.world.objects[0].paths = []
	result = room.command(owner.player_id,{"op":"carry","action":"drop","id":"wire-drop","version":1,"seq":2})
	check(not result.ok and room.actors[owner.player_id].carried_id == "wire-drop", "invalid authoritative drop retains carry identity")
	check(held.freeze and held.collision_layer == 0 and room.locks.has("wire-drop"), "invalid authoritative drop retains suppression and lock")
	room.world.objects[0].paths = paths
	await dispose()
	await fresh("disconnect")
	wall = wall_at(held.position)
	for frame in 3: await physics_frame
	room.disconnect_player(owner.player_id)
	check(room.actors[owner.player_id].carried_id == "" and not room.locks.has("wire-drop"), "disconnect releases carry identity and lock")
	check(not touches(wall) and held.collision_layer != 0, "disconnect resolves a safe physical release instead of restoring collision inside a wall")
	await dispose()
	print("NETWORK CARRY DROP: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
