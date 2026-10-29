extends "res://tests/network_creation_receipt_test.gd"

func restart_with_profile() -> void:
	cleanup()
	session = CapturingSession.new(); root.add_child(session); session.set_process(false)
	session.epoch = "fresh-epoch"; session.world_id = "fresh-world"
	session.apply_snapshot({"epoch": session.epoch, "world_kind": "paper", "objects": [], "world": {}, "actors": []})
	game = session.game; game.set_physics_process(false)

func run() -> void:
	setup()
	var spawn := draw_building(); full_bag(); reply(spawn)
	var confirmed: Dictionary = spawn.object.duplicate(true)
	restart_with_profile()
	session.ready_to_play = true
	check(game.bag.entries.size() == 128, "restart preserves full personal bag instead of replacing it with defaults")
	var ink: Array = [{"points": [Vector2(8, 4), Vector2(9, 4)]}]; game.draft = ink.duplicate(true)
	game.feedback.events.clear()
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(.01)
	check(game.bag.entries.size() == 128 and game.bag.entries.back().paths == confirmed.paths, "restarted pending confirmed object archives when one slot becomes free")
	check(game.draft == ink and game.equipped_weapon.is_empty(), "recovery cannot consume new-session ink or equip an old object")
	check(commands("spawn").is_empty() and commands("equip").is_empty(), "recovery never sends world creation/equipment commands")
	check(not game.feedback.events.any(func(event): return event.kind == "create"), "recovery never replays creation effects")
	restart_with_profile()
	session.ready_to_play = true
	check(game.bag.entries.size() == 128 and game.bag.entries.back().paths == confirmed.paths, "archive and pending removal survive together in the real profile")
	BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(.01)
	check(game.bag.entries.size() == 127, "another restart cannot archive the same confirmed object twice")
	cleanup(); await process_frame
	print("NETWORK PENDING RECOVERY: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
