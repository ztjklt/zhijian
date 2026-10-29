extends SceneTree

var failures: Array[String] = []
var assertions := 0
var game

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		printerr("MOVEMENT: " + label)

func frames(count: int) -> void:
	for frame in range(count): await physics_frame

func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# Test fixtures are attached directly; expose their paths to the normal paper renderer.
	var objects_before: Array = game.objects.duplicate()
	for child in game.get_children():
		if child is BuildObject and not child.is_queued_for_deletion(): game.objects.append(child.data)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/paper-movement-" + stage + ".png")
	game.objects = objects_before

func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(2)

func stand_on(y: float) -> void:
	game.player.position = Vector2(-5.6, y + 0.65)
	game.player.linear_velocity = Vector2.ZERO
	await frames(45)

func platform(y: float, thickness: float = 0.06) -> RigidBody2D:
	var data := {"kind": "freehand", "dynamic": false, "x": -5.6, "y": y,
		"paths": [{"points": [Vector2(-2, 0), Vector2(2, 0)]}]}
	var body: RigidBody2D = game._build_physics_for_object(data)
	# Thick fixture represents a solid floating island; actual collision geometry is used.
	if thickness > 0.06:
		var shape: CollisionShape2D = body.get_child(0)
		shape.shape.size.y = thickness
	return body

func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	if game.combat.has_method("set_natives"): game.combat.set_natives(false)
	await frames(50)
	check(game.on_ground, "player starts on bottom ground")
	await tap("jump")
	check(game.player.linear_velocity.y > 6, "first jump launches upward")
	await frames(10)
	await tap("jump")
	check(game.player.linear_velocity.y > 6, "second press restores upward speed in midair")
	await capture("double-jump")
	var before_third: float = game.player.linear_velocity.y
	await tap("jump")
	check(game.player.linear_velocity.y < before_third - 0.5, "third press cannot create a third jump")
	await frames(120)
	check(game.on_ground, "double jump lands on bottom ground")
	await tap("move_up")
	await frames(12)
	await tap("move_up")
	check(game.player.linear_velocity.y > 6, "landing restores both jumps and W can double jump")
	await frames(120)
	Input.action_press("jump")
	await frames(55)
	check(game.player.linear_velocity.y < 0, "holding jump does not automatically use second jump")
	Input.action_release("jump")
	await frames(100)
	await tap("move_down")
	await tap("move_down")
	await frames(50)
	check(absf(game.player.position.y - (game.GROUND_Y + 0.29)) < 0.06, "double down never passes through bottom ground")
	check(game.player.collision_mask == 9, "dropping preserves the ground and structure collision layers")

	var lower := platform(-1.0)
	var upper := platform(1.0)
	await stand_on(1.0)
	check(game.on_ground and game.player.position.y > 1.25, "player stands on upper floating platform")
	await capture("upper-platform")
	await tap("move_down")
	await frames(25)
	check(game.player.position.y > 1.25, "one down press only crouches")
	await tap("move_down")
	await frames(35)
	check(game.player.position.y > 1.25, "slow separate down presses do not trigger a drop")
	Input.action_press("move_down")
	await frames(40)
	Input.action_release("move_down")
	check(game.player.position.y > 1.25, "holding down does not count as two taps")
	await frames(25)
	await tap("move_down")
	await tap("move_down")
	await frames(40)
	check(game.player.position.y < 0 and game.player.position.y > -0.8, "double down drops through only the current platform and lands on next")
	await capture("lower-platform")
	check(not game.player.get_collision_exceptions().has(upper), "platform collision returns after the body clears it")
	await tap("move_down")
	await tap("move_down")
	await frames(50)
	check(absf(game.player.position.y - (game.GROUND_Y + 0.29)) < 0.06, "dropping from lowest floating platform stops at bottom ground")
	await capture("bottom-ground")
	upper.queue_free()
	lower.queue_free()
	await frames(3)

	var island := platform(0.7, 1.8)
	await stand_on(1.6)
	await tap("move_down")
	await tap("move_down")
	await frames(80)
	check(absf(game.player.position.y - (game.GROUND_Y + 0.29)) < 0.06, "double down fully clears a thick solid island")
	check(not game.player.get_collision_exceptions().has(island), "thick island collision is restored after passing underneath")
	await stand_on(1.6)
	check(game.player.position.y > 1.8, "the same island supports the character again after a drop")
	await tap("move_down")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await tap("move_down")
	await frames(25)
	check(game.player.position.y > 1.8, "focus loss clears the pending first down tap")
	game.toggle_bag()
	game.backpack_panel.name_field.grab_focus()
	await tap("move_down")
	await tap("move_down")
	check(game.player.position.y > 1.8, "typing in a field cannot make the player drop")
	game.backpack_panel.name_field.release_focus()
	game.toggle_bag()
	await tap("move_down")
	await frames(25)
	check(game.player.position.y > 1.8, "down taps while bag is open do not arm a drop after closing")
	await frames(25)
	await tap("move_down")
	await tap("move_down")
	check(game.player.get_collision_exceptions().has(island), "thick island stays ignored while the player is still inside")
	check(game.save_game(), "isolated world save succeeds during a drop")
	game.load_game()
	check(not game.player.get_collision_exceptions().has(island), "loading restores temporary platform collision before relocating the player")
	island.queue_free()
	await frames(3)
	await stand_on(game.GROUND_Y)
	# Adjacent supports must both be bypassed, without globally disabling collisions.
	var left := platform(1.0)
	var right := platform(1.0)
	left.position.x -= 2.0
	right.position.x += 2.0
	await stand_on(1.0)
	await tap("move_down")
	await tap("move_down")
	await frames(60)
	check(game.player.position.y < -2.4, "double down also passes through the seam between two platforms")
	left.queue_free()
	right.queue_free()
	await frames(3)
	# Legacy one-way platforms and dynamic freehand bodies use the same drop behavior.
	var one_way: Dictionary = {"kind": "platform", "dynamic": false, "x": -5.6, "y": 0.7,
		"paths": [{"points": [Vector2(-2, 0), Vector2(2, 0)]}]}
	var legacy: RigidBody2D = game._build_physics_for_object(one_way)
	await stand_on(0.7)
	await tap("move_down")
	await tap("move_down")
	await frames(60)
	check(game.player.position.y < -2.4, "legacy one-way platform supports double down")
	legacy.queue_free()
	await frames(3)
	var dynamic: Dictionary = {"kind": "freehand", "dynamic": true, "x": -5.6, "y": 0.7,
		"paths": [{"points": [Vector2(-2, -0.4), Vector2(2, -0.4), Vector2(2, 0.4), Vector2(-2, 0.4), Vector2(-2, -0.4)]}]}
	var floating: RigidBody2D = game._build_physics_for_object(dynamic)
	floating.gravity_scale = 0
	floating.lock_rotation = true
	floating.mass = 10000
	await stand_on(1.1)
	await tap("move_down")
	await tap("move_down")
	await frames(60)
	check(game.player.position.y < -2.4, "double down works on a floating dynamic freehand island")
	floating.queue_free()
	await frames(3)
	var gate_data := {"kind": "gate", "dynamic": false, "x": -5.6, "y": 1.0,
		"paths": [{"points": [Vector2(-2, 0), Vector2(2, 0)]}]}
	var gate: RigidBody2D = game._build_physics_for_object(gate_data)
	game.jumps_used = 2
	await stand_on(1.0)
	check(game.on_ground, "landing on a gate roof is grounded even though gates use a different layer")
	await tap("jump")
	check(game.player.linear_velocity.y > 6, "landing on a gate roof restores the jump budget")
	await frames(120)
	await tap("move_down")
	await tap("move_down")
	await frames(60)
	check(game.player.position.y < -2.4, "double down works on a gate roof")
	gate.queue_free()
	await frames(3)
	game.queue_free()
	await process_frame
	print("MOVEMENT: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
