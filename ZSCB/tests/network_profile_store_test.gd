extends "res://tests/network_creation_receipt_test.gd"
const PATH := PaperNetSession.PROFILE
func raw(text: String, path: String = PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(text); file.close()
func reset_files() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(PATH + suffix)
func load_real() -> void:
	session = CapturingSession.new(); root.add_child(session); session.set_process(false); session.epoch = "read"
	session.apply_snapshot({"epoch": "read", "world_kind": "paper", "objects": [], "world": {}, "actors": []})
	game = session.game; game.set_physics_process(false)
func run() -> void:
	reset_files(); setup()
	BlueprintBag.add_entry(game.bag, {"kind": "freehand", "paths": [{"points": [Vector2.ZERO, Vector2.ONE]}]})
	game.bag.entries.back().name = "有效旧版"
	session._save_profile()
	var good := FileAccess.get_file_as_string(PATH)
	game.bag.entries.back().name = "有效新版"; session._save_profile()
	check(FileAccess.file_exists(PATH + ".bak"), "replacing personal profile retains a valid previous version")
	check(FileAccess.file_exists(PATH + ".bak") and FileAccess.get_file_as_string(PATH + ".bak") == good, "backup is the exact prior complete profile")
	cleanup(); raw("{broken"); load_real()
	check(game.bag.entries.size() == 7 and game.bag.entries.back().name == "有效旧版", "corrupt primary falls back to a real complete backup")
	var before := FileAccess.get_file_as_string(PATH + ".bak") if FileAccess.file_exists(PATH + ".bak") else ""
	session._save_profile()
	check(FileAccess.get_file_as_string(PATH + ".bak") == before, "repair never rotates corrupt primary over a good backup")
	cleanup(); reset_files(); raw("{both-bad"); raw("{also-bad", PATH + ".bak"); load_real()
	session._save_profile()
	check(FileAccess.get_file_as_string(PATH) == "{both-bad" and FileAccess.get_file_as_string(PATH + ".bak") == "{also-bad", "unrecoverable profile cannot be silently replaced by defaults")
	cleanup(); reset_files(); raw('{"profile_version":99,"name":"future"}'); load_real()
	session._save_profile()
	check(FileAccess.get_file_as_string(PATH) == '{"profile_version":99,"name":"future"}', "unknown future profile remains untouched")
	cleanup(); reset_files(); setup(); session._save_profile(); good = FileAccess.get_file_as_string(PATH)
	DirAccess.make_dir_recursive_absolute(PATH + ".tmp")
	session._save_profile()
	check(FileAccess.get_file_as_string(PATH) == good, "blocked temporary path preserves the previous profile")
	check(game.toolbar.status_text.contains("失败"), "personal profile write failure is visible to the player")
	cleanup(); reset_files(); await process_frame
	print("NETWORK PROFILE STORE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
