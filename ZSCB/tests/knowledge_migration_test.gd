extends SceneTree

var failures: Array[String] = []
var count := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("MAP MIGRATION: " + label)

func run() -> void:
	# Original pre-map saves must survive any number of new-format saves.
	var legacy := "user://paper_castle_v1.json"
	for version in [1, 2]:
		if FileAccess.file_exists(SaveStore.SAVE_PATH): DirAccess.remove_absolute(SaveStore.SAVE_PATH)
		var old := {"version": version, "paper": "draft", "objects": [], "bag": BlueprintBag.new_bag(), "cameraX": 5, "playerX": 5}
		var original := JSON.stringify(old)
		var file := FileAccess.open(legacy, FileAccess.WRITE)
		file.store_string(original)
		file.close()
		var loaded := SaveStore.load_game()
		check(loaded.error == "" and loaded.data.version == version, "existing v%d work is readable before migration" % version)
		var state := {"id": "knowledge-v1", "player_y": 5.0, "camera_y": 3.0, "checkpoint": Vector2(35, -1.26), "bookmarks": [1]}
		check(SaveStore.save_game("draft", [], BlueprintBag.new_bag(), 35, 35, {}, state).ok, "first v%d-to-map save succeeds" % version)
		check(SaveStore.save_game("draft", [], BlueprintBag.new_bag(), 36, 36, {}, state).ok, "second map save succeeds after v%d migration" % version)
		check(FileAccess.get_file_as_string(legacy) == original, "v%d original remains byte-for-byte intact after repeated saves" % version)
		loaded = SaveStore.load_game()
		check(loaded.error == "" and loaded.data.version == 3 and loaded.data.playerX == 36, "loader prefers the newer map work over preserved v%d original" % version)
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.combat.set_natives(false)
	game.player.freeze = true
	for fixture in [{"x": -0.5, "safe_x": 9.0}, {"x": 157.0, "safe_x": 139.0}]:
		game.player.position = Vector2(fixture.x, -2)
		PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, game.player.position))
		game.knowledge_world._process(0.01)
		game.knowledge_world.respawn()
		check(is_equal_approx(game.player.position.x, fixture.safe_x), "walking beyond edge %.1f keeps respawn on the nearest real chapter" % fixture.x)
	game.queue_free()
	await process_frame
	print("MAP MIGRATION: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
