extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("MAP SESSION: " + label)

func frames() -> void:
	for i in range(3): await process_frame

func marker(game, x: float) -> void:
	game.objects.append({"kind":"freehand", "x":x, "y":4.0, "dynamic":false, "paths":[{"points":[Vector2.ZERO,Vector2(1,0)],"collision":true}]})
	game._rebuild_objects()

func run() -> void:
	var retained = load("res://scenes/main.tscn").instantiate()
	retained.onboarding.persist = false
	root.add_child(retained)
	current_scene = retained
	await frames()
	marker(retained, 12)
	retained.change_map("knowledge-v1")
	marker(retained, 20)
	retained.change_map("nature-v1")
	marker(retained, 30)
	retained.change_map("medieval-v1")
	retained.return_to_map_select()
	await frames()
	current_scene.start_map("medieval-v1", false)
	await frames()
	check(is_instance_valid(retained), "new medieval keeps the other cached session alive")
	check(retained.world_kind == "paper" and retained.objects.size() == 1 and retained.objects[0].x == 12, "legacy flat workspace is retained with its real building")
	check(retained.map_workspaces.has("knowledge-v1") and retained.map_workspaces.has("nature-v1"), "resetting one map preserves every other inactive map")
	var fresh = current_scene
	fresh.return_to_map_select()
	await frames()
	check(current_scene._cached_game("knowledge-v1") == retained, "original textbook session remains resumable")
	current_scene.start_map("knowledge-v1", true)
	await frames()
	check(current_scene == retained and retained.objects.size() == 1 and retained.objects[0].x == 20, "textbook building survives new-map reset")
	current_scene.return_to_map_select()
	await frames()
	current_scene.start_map("nature-v1", true)
	await frames()
	check(current_scene == retained and retained.objects.size() == 1 and retained.objects[0].x == 30, "natural building also survives and can be resumed")
	current_scene.free()
	var holder := root.get_node_or_null("MapSessions")
	if holder != null: holder.free()
	print("MAP SESSION PRESERVATION: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
