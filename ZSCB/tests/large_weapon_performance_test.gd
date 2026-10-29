extends SceneTree
## Large, wide hand-drawn weapons and direction reversals in the actual maps.
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func run() -> void:
	for scene in ["sandbox", "medieval"]:
		var game = load("res://scenes/" + scene + ".tscn").instantiate()
		game.onboarding.persist = false
		root.add_child(game)
		await process_frame
		game.onboarding.dismiss()
		game.set_physics_process(false)
		game.player.freeze = true
		var strokes: Array = []
		for stroke in 16:
			var points: Array = []
			for i in 72:
				var angle := TAU * float(i) / 71.0
				points.append(Vector2(cos(angle) * 1.35, sin(angle) * 1.25) + Vector2(stroke * 0.01, 0))
			strokes.append({"points": points})
		game.equipped_weapon = PaperWeaponGrip.make_weapon(strokes, strokes[0].points[0])
		var battle = game.combat
		for direction in [Vector2.RIGHT, Vector2.LEFT]:
			for move in 4:
				battle.reset()
				battle.attack(direction)
				battle.motion_index = move
				var worst := 0.0
				var worst_wall := 0.0
				for frame in 23:
					var start := Time.get_ticks_usec()
					battle.step(1.0 / 60.0)
					worst = maxf(worst, (Time.get_ticks_usec() - start) / 1000.0)
					if battle.blade_active():
						start = Time.get_ticks_usec()
						battle._blade_structure(battle.previous_player_paths, battle.player_paths, battle._held_blade_origin())
						worst_wall = maxf(worst_wall, (Time.get_ticks_usec() - start) / 1000.0)
				print("LARGE WEAPON ", scene, " direction=", direction.x, " move=", move, " max_cpu_ms=", snappedf(worst, 0.001), " wall_ms=", snappedf(worst_wall, 0.001))
				if worst > 16.67: failures.append(scene + " direction=" + str(direction.x) + " move=" + str(move) + " exceeds 60 Hz CPU frame budget")
		game.queue_free()
		await process_frame
	print("LARGE WEAPON PERFORMANCE: ", failures.size(), " failures")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
