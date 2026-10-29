extends SceneTree

var checks := 0
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL CARRY ACTIVITY: ", label)

func draw_block(at: Vector2) -> void:
	game.draft = [{"points": [at + Vector2(-.3, -.3), at + Vector2(.3, -.3), at + Vector2(.3, .3), at + Vector2(-.3, .3), at + Vector2(-.3, -.3)]}]
	game.release_building()

func finish() -> void:
	game.queue_free()
	await process_frame
	print("CARRY ACTIVITY: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.freeze = true
	# Leave unobstructed space below the carried object for the drop/gravity check.
	game.player.position = Vector2(0, 2)
	game.camera_x = 0
	game.set_draw_mode(3)
	draw_block(Vector2(2, 0))
	draw_block(Vector2(-2, 0))
	check(game.objects.size() == 2, "normal drawing creates two physical objects")
	if game.objects.size() != 2:
		await finish()
		return
	check(not game.objects[0].has("id") and not game.objects[1].has("id"), "single-player creation needs no network identity")
	check(game.carried_index() == -1, "empty carry state never selects an id-less drawing")
	game._update_world_chunks()
	var held: RigidBody2D = game.object_nodes[0]
	var other: RigidBody2D = game.object_nodes[1]
	check(not held.freeze and not other.freeze, "ordinary local drawings remain dynamic after chunk activity updates")
	# Stop on the original empty-identity failure, before attempting a pickup.
	if not failures.is_empty():
		await finish()
		return
	check(not game.drop_carried(), "dropping with empty hands cannot move an ordinary drawing")
	var initial_y := other.position.y
	for frame in 12:
		await physics_frame
	check(other.position.y < initial_y - .02, "uncarried drawing really falls under gravity")
	game.sync_objects()
	game.set_draw_mode(4)
	game.selected = 0
	var layer := held.collision_layer
	var mask := held.collision_mask
	check(game.toggle_carry(), "a real single-player drawing can be picked up without a network id")
	check(game.carried_id != "" and game.carried_index() == 0, "pickup resolves exactly the selected local drawing")
	game._update_world_chunks()
	check(held.freeze and held.collision_layer == 0 and held.collision_mask == 0 and not other.freeze, "only the carried drawing is frozen by activity updates")
	game.player.position.x += 1
	game.update_carried_object()
	check(held.position.is_equal_approx(game.carry_position()), "local identity follows the same carried drawing while moving")
	check(game.toggle_carry(), "local drawing can be safely put down")
	game._update_world_chunks()
	check(game.carried_index() == -1 and not held.freeze and held.collision_layer == layer and held.collision_mask == mask, "drop restores collision and dynamic activity")
	var drop_y := held.position.y
	for frame in 12:
		await physics_frame
	check(held.position.y < drop_y - .02, "dropped drawing really resumes gravity")
	# Far-away pieces still sleep; fixing carry must retain normal world culling.
	game.camera_x = 160
	game._update_world_chunks()
	check(held.freeze and other.freeze, "unconnected pieces outside the active region still freeze")
	game.camera_x = 0
	game._update_world_chunks()
	check(not held.freeze and not other.freeze, "returning to the region reactivates local drawings")
	await finish()
