extends SceneTree
## Reproduce a user-provided saved weapon in isolated user data only.
## PAPER_CASTLE_WEAPON_FIXTURE points to a backup, never the live save location.
func _init() -> void: call_deferred("run")

func run() -> void:
	var fixture := OS.get_environment("PAPER_CASTLE_WEAPON_FIXTURE")
	if fixture.is_empty() or DirAccess.copy_absolute(fixture,SaveStore.MEDIEVAL_SAVE_PATH) != OK:
		push_error("Set PAPER_CASTLE_WEAPON_FIXTURE to a backed-up medieval save")
		quit(1)
		return
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.load_game()
	game.set_physics_process(false)
	game.player.freeze = true
	var points := 0
	for path in game.equipped_weapon.get("paths",[]): points += path.points.size()
	if points < 2:
		push_error("Fixture did not restore an equipped weapon")
		quit(1)
		return
	print("SAVED WEAPON paths=",game.equipped_weapon.paths.size()," points=",points)
	var failure := false
	var rendered := DisplayServer.get_name() != "headless"
	for direction in [Vector2.RIGHT,Vector2.LEFT]:
		for move in 4:
			var battle = game.combat
			battle.reset()
			battle.attack(direction)
			battle.motion_index = move
			var times: Array[float] = []
			var intervals: Array[float] = []
			for frame in 24:
				var start := Time.get_ticks_usec()
				battle.step(1.0/60.0)
				times.append((Time.get_ticks_usec()-start)/1000.0)
				if rendered:
					await process_frame
					intervals.append((Time.get_ticks_usec()-start)/1000.0)
			times.sort()
			intervals.sort()
			print("SAVED WEAPON direction=",direction.x," move=",move," cpu_max_ms=",snappedf(times[-1],0.001)," render_interval_p95_ms=",snappedf(intervals[22],0.001) if rendered else 0)
			if times[-1] > 16.67: failure = true
	game.queue_free()
	await process_frame
	print("SAVED WEAPON PERFORMANCE: ",1 if failure else 0," failures")
	quit(1 if failure else 0)
