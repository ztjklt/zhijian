extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL PROFILE RECOVERY: ", label)
func run() -> void:
	var first := PaperNetSession.new(); root.add_child(first); first.set_process(false)
	var game = load("res://scenes/main.tscn").instantiate(); game.onboarding.persist = false; root.add_child(game)
	game.set_physics_process(false); game.combat.set_natives(false)
	first.game = game; game.network_session = first
	var added := BlueprintBag.add_entry(game.bag, {"kind": "freehand", "paths": [{"points": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]}]})
	game.bag.entries.back().name = "重开后应保留的图纸"
	var original: Dictionary = game.bag.duplicate(true)
	first._save_profile()
	game.network_session = null; first.game = null; first.free(); game.free()
	var second := PaperNetSession.new(); root.add_child(second); second.set_process(false)
	second.epoch = "restored"
	second.apply_snapshot({"epoch": "restored", "world_kind": "paper", "objects": [], "world": {}, "actors": []})
	second.game.set_physics_process(false)
	check(second.game.bag.entries.size() == original.entries.size(), "new session restores every personal blueprint from its real profile file")
	check(second.game.bag.entries.back().name == "重开后应保留的图纸" and second.game.bag.entries.back().paths == original.entries.back().paths, "profile preserves actual names and typed Vector2 geometry")
	second.game.network_session = null; second.game.free(); second.game = null; second.free()
	await process_frame
	print("NETWORK PROFILE RECOVERY: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
