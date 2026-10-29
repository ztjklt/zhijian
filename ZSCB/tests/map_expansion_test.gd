extends SceneTree

var failures: Array[String] = []
var count := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	count += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(amount: int) -> void:
	for i in amount: await physics_frame

func place(game, at: Vector2) -> void:
	game.knowledge_world.checkpoint = at
	game.knowledge_world.respawn()
	await frames(3)

func run() -> void:
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.combat.set_natives(false)
	var world = game.knowledge_world
	await place(game, Vector2(4, 15))
	await frames(65)
	check(absf(game.player.position.y - 14.29) < .14, "sky reading terrace has actual supporting collision above the original six chapters")
	check(game.player.begin_drop_through(), "sky terrace deliberately allows a one-layer drop")
	await frames(45)
	check(game.player.position.y < 13, "drop passes the new sky terrace without disabling the foundation")
	await place(game, Vector2(-.15, -2.4))
	Input.action_press("move_right")
	var reached := false
	for i in 700:
		await physics_frame
		if game.player.position.y > 14.25 and game.player.position.x > .8:
			reached = true
			break
	Input.action_release("move_right")
	check(reached, "holding toward the visible margin spine climbs from ground to the first sky terrace")
	await place(game, Vector2(6.8, 14.4))
	await frames(20)
	Input.action_press("move_right")
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(13)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(28)
	Input.action_release("move_right")
	await frames(75)
	check(game.player.position.x > 9.5 and absf(game.player.position.y - 15.19) < .16, "two real jumps cross the sky gap and land on the next higher terrace")
	var nature_script = load("res://scripts/nature_world.gd") if FileAccess.file_exists("res://scripts/nature_world.gd") else null
	check(nature_script != null, "the optional nature map is available locally")
	if nature_script != null:
		game.remove_child(world)
		world.queue_free()
		game.knowledge_world = nature_script.new()
		world = game.knowledge_world
		world.game = game
		game.add_child(world)
		await frames(3)
		await place(game, Vector2(32, 8))
		await frames(80)
		check(absf(game.player.position.y - 6.29) < .15, "nature mountain summit is visible solid terrain supporting the real player")
		await place(game, Vector2(20, 7))
		await frames(60)
		check(absf(game.player.position.y - 6.49) < .15, "wooden tree route supports the real player above the ground")
		check(game.player.begin_drop_through(), "wooden upper route permits deliberate descent")
		await frames(50)
		check(game.player.position.y < 5.8, "dropping through wood descends toward the lower natural route")
		world.visit(5)
		await frames(50)
		check(game.player.position.x > 130 and game.player.position.y > world.surface_height(game.player.position.x), "nature navigation respawns safely in the far exploration region")
		var hill_contact: Dictionary = game.combat._blade_structure([PackedVector2Array([Vector2(30,5.4),Vector2(30,5.6)])], [PackedVector2Array([Vector2(32,5.4),Vector2(32,5.6)])])
		check(not hill_contact.is_empty() and hill_contact.index == -1, "actual sword sweep is blocked by the visible mountain slope")
		var wood_contact: Dictionary = game.combat._blade_structure([PackedVector2Array([Vector2(19.8,6.8),Vector2(20.2,6.8)])], [PackedVector2Array([Vector2(19.8,5.8),Vector2(20.2,5.8)])])
		check(not wood_contact.is_empty() and wood_contact.index == -1, "actual sword sweep is blocked by the same wooden platform that supports the player")
	game.queue_free()
	await process_frame
	print("MAP EXPANSION: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
