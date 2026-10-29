extends SceneTree
## Renderer observation; --visual required. Timing includes vsync and scheduling,
## so these numbers are observations, not portable GPU-budget assertions.
func _init() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use run_isolated.py --visual for the render observation")
		quit(1)
		return
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var points: Array = []
	for i in range(97): points.append(Vector2(sin(i * 0.6) * 0.06, float(i) / 96 * 2.6))
	game.equipped_weapon = {"paths": [{"points": points}], "grip": Vector2.ZERO, "cooldown": 0.4}
	for warmup in range(20):
		game.combat.step(1.0 / 60.0)
		await process_frame
	for move in range(-1, 4):
		game.combat.cooldown = 0
		game.combat.recoil = 0
		if move >= 0:
			game.combat.attack(Vector2.RIGHT)
			game.combat.motion_index = move
		var intervals: Array[float] = []
		var steps: Array[float] = []
		var calls := 0
		var last := Time.get_ticks_usec()
		for frame in range(30):
			var start := Time.get_ticks_usec()
			game.combat.step(1.0 / 60.0)
			steps.append(float(Time.get_ticks_usec() - start) / 1000.0)
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append(float(now - last) / 1000.0)
			last = now
			calls = maxi(calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		intervals.sort()
		steps.sort()
		print("COMBAT RENDER move=", move, " interval_p95_ms=", snappedf(intervals[28], 0.001), " interval_max_ms=", snappedf(intervals[-1], 0.001), " cpu_step_max_ms=", snappedf(steps[-1], 0.001), " max_draw_calls=", calls)
	game.queue_free()
	await process_frame
	quit(0)
