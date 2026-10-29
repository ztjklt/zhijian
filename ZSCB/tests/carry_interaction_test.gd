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
		print("FAIL CARRY: ", label)

func add_object(at: Vector2) -> void:
	var object := {"id": "carry-local", "structure_id": "carry-local", "author": "", "kind": "freehand", "role": "building", "dynamic": true, "x": at.x, "y": at.y, "angle": 0.0, "health": 120.0, "max_health": 120.0, "paths": [{"points": [Vector2(-.4,-.3), Vector2(.4,-.3), Vector2(.4,.3), Vector2(-.4,.3), Vector2(-.4,-.3)], "collision": true}]}
	game.objects.append(object)
	var body = game.build_object_scene.instantiate()
	body.setup(object)
	game.object_nodes.append(game._attach_body(body, object))

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.freeze = true
	game.player.position = Vector2(0, game.GROUND_Y + .54)
	game.set_draw_mode(4)
	add_object(game.player.position + Vector2(.8, -.4))
	game.selected = 0
	var body: RigidBody2D = game.object_nodes[0]
	var old_layer := body.collision_layer
	var old_mask := body.collision_mask
	check(game.toggle_carry(), "selected own object can be picked up")
	check(game.carried_id == "carry-local" and body.freeze and body.collision_layer == 0 and body.collision_mask == 0, "picked object is attached without blocking the player")
	var carried_before := body.position
	game.player.position.x += 2.0
	game.update_carried_object()
	check(body.position != carried_before and body.position == game.carry_position(), "carried object follows the player")
	check(game.toggle_carry(), "carried object can be dropped")
	check(game.carried_id == "" and body.collision_layer == old_layer and body.collision_mask == old_mask and not body.freeze, "drop restores physics and clears carry state")
	var dropped := body.position
	game.player.position.x += 1.0
	game.update_carried_object()
	check(body.position == dropped, "dropped object stays at its safe position")
	game.queue_free()
	await process_frame
	print("CARRY INTERACTION: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
