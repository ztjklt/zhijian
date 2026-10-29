extends SceneTree
class CapturingSession extends PaperNetSession:
	var creations: Array = []
	func _send(message: Dictionary) -> void:
		if message.get("op", "") in ["spawn", "equip"]: creations.append(message.duplicate(true))
var checks := 0
var failed := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1; print("FAIL RESTART: ", label)
func run() -> void:
	var stage := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="): stage = arg.trim_prefix("--stage=")
	var session := CapturingSession.new(); root.add_child(session); session.set_process(false)
	var game
	var paths: Array = [{"points": [Vector2(-.5, 0), Vector2(.5, 0)], "collision": true}]
	if stage == "write":
		game = load("res://scenes/main.tscn").instantiate(); game.onboarding.persist = false; root.add_child(game)
		game.set_physics_process(false); game.combat.set_natives(false); game.network_session = session; session.game = game
		session.ready_to_play = true; session.epoch = "old"; session.world_id = "old-world"
		game.draw_mode = 3; game.draft = [{"points": [Vector2(-.5, 1), Vector2(.5, 1)]}]
		var object := {"source": "own", "kind": "freehand", "x": 0, "y": 1, "paths": paths}
		session.spawn_candidate(object)
		while game.bag.entries.size() < 128: BlueprintBag.add_entry(game.bag, PaperWeaponGrip.practice_sword())
		session._result({"seq": session.seq, "op": "spawn", "ok": true, "object": object})
		check(session.creation_receipts.waiting.size() == 1 and session.profile_error == "", "confirmed pending blueprint persisted before full process exit")
		check(game.bag.entries.size() == 128 and session.creations.size() == 1, "writer neither expands bag nor resends creation")
	else:
		session.epoch = "new"; session.world_id = "new-world"
		session.apply_snapshot({"epoch": "new", "world_kind": "paper", "objects": [], "world": {}, "actors": []})
		game = session.game; game.set_physics_process(false)
		session.ready_to_play = true
		check(game.bag.entries.size() == 128, "actual new process restores the full personal bag")
		if stage == "close":
			DirAccess.make_dir_recursive_absolute(PaperNetSession.PROFILE + ".tmp")
			var object := {"source": "own", "kind": "freehand", "x": 0, "y": 1, "paths": paths}
			BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id)
			session.spawn_candidate(object)
			BlueprintBag.add_entry(game.bag, PaperWeaponGrip.practice_sword())
			session._result({"seq": session.seq, "op": "spawn", "ok": true, "object": object})
			check(session.creation_receipts.waiting.size() == 1 and session.profile_error != "", "close fixture has unsaved confirmed personal data")
			await session._close_application()
			for i in 3: await process_frame
			check(is_instance_valid(game) and not session.ended and not session.window_closing, "window close refuses to destroy unsaved personal data")
			print("PROFILE_CLOSE_PRESERVED")
			DirAccess.remove_absolute(PaperNetSession.PROFILE + ".tmp")
		elif stage == "read":
			check(session.creation_receipts.waiting.size() == 1, "pending survived process exit")
			var ink: Array = [{"points": [Vector2(7, 3), Vector2(8, 3)]}]; game.draft = ink.duplicate(true)
			game.feedback.events.clear()
			BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(.1)
			check(game.bag.entries.size() == 128 and game.bag.entries.back().paths == paths and session.creation_receipts.waiting.is_empty(), "free slot commits restored blueprint and removes pending together")
			check(game.draft == ink and game.equipped_weapon.is_empty() and session.creations.is_empty(), "restore preserves new work and never sends a world command")
			check(not game.feedback.events.any(func(event): return event.kind == "create"), "restored blueprint cannot replay old creation effects")
		else:
			check(stage == "recheck", "known probe stage")
			check(session.creation_receipts.waiting.is_empty() and game.bag.entries.back().paths == paths, "another process sees only the committed blueprint")
			BlueprintBag.remove_entry(game.bag, game.bag.entries.back().id); session.tick(.1)
			check(game.bag.entries.size() == 127 and session.creations.is_empty(), "later free capacity cannot duplicate a completed recovery")
	game.network_session = null; session.game = null; game.queue_free(); session.queue_free()
	for i in 4: await process_frame
	print("PROFILE RESTART ", stage, ": ", checks, " checks, ", failed, " failures")
	quit(0 if failed == 0 else 1)
