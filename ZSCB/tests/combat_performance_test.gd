extends SceneTree
## Run only through tests/run_isolated.py: actual sandbox map, rig and combat.
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var battle = game.combat
	var segments := 0
	for path in game.knowledge_world.collision_geometry: segments += path.size() - 1
	print("COMBAT PERF MAP: paths=", game.knowledge_world.collision_geometry.size(), " segments=", segments, " natives=", battle.natives.size())
	var complex: Array = []
	for line in range(3):
		var points: Array = []
		for i in range(33): points.append(Vector2(float(line - 1) * 0.06 + sin(i * 0.6) * 0.04, float(i) / 32.0 * 2.6))
		complex.append({"points": points})
	for fixture in [{"name": "short", "paths": [{"points": [Vector2.ZERO, Vector2(0, 0.8)]}]}, {"name": "complex_long_96_segments", "paths": complex}]:
		game.equipped_weapon = {"paths": fixture.paths, "grip": Vector2.ZERO, "cooldown": 0.4, "damage": 20.0, "reach": 0.8}
		for move in range(4):
			battle.reset()
			battle.attack(Vector2.RIGHT)
			battle.motion_index = move
			var times: Array[float] = []
			var walls: Array[float] = []
			for frame in range(22):
				var start := Time.get_ticks_usec()
				battle.step(1.0 / 60.0)
				times.append(float(Time.get_ticks_usec() - start) / 1000.0)
				if frame in [6, 9, 12]:
					start = Time.get_ticks_usec()
					battle._blade_structure(battle.previous_player_paths, battle.player_paths)
					walls.append(float(Time.get_ticks_usec() - start) / 1000.0)
			times.sort()
			walls.sort()
			print("COMBAT PERF ", fixture.name, " move=", move, " step_max_ms=", snappedf(times[-1], 0.001), " step_p95_ms=", snappedf(times[20], 0.001), " wall_max_ms=", snappedf(walls[-1], 0.001))
			# Removing spatial pruning should exceed this generous CPU-only budget.
			if times[-1] > 16.67:
				failures.append("one combat step exceeds 60 Hz budget: " + fixture.name + " move=" + str(move))
	game.queue_free()
	await process_frame
	print("COMBAT PERFORMANCE TEST: ", failures.size(), " failures")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
