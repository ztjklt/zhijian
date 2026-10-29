extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		push_error("LIBRARY: " + label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(ResourceLoader.exists("res://scripts/sculpt_library.gd"), "sculpting has an expandable shape library")
	if not ResourceLoader.exists("res://scripts/sculpt_library.gd"):
		finish()
		return
	var library = load("res://scripts/sculpt_library.gd")
	var entries: Array = library.entries()
	check(entries.size() >= 35, "library adds at least 35 distinct shapes beyond the initial five")
	# Independent drawings catch mismatched template IDs and geometry distortion.
	var fixtures := {
		"trapezoid": [Vector2(-1, -1), Vector2(1, -1), Vector2(0.6, 1), Vector2(-0.6, 1), Vector2(-1, -1)],
		"parallelogram": [Vector2(-1, -0.7), Vector2(0.6, -0.7), Vector2(1, 0.7), Vector2(-0.6, 0.7), Vector2(-1, -0.7)],
		"house": [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 0.25), Vector2(0, 1), Vector2(-1, 0.25), Vector2(-1, -1)],
		"arrow": [Vector2(-1, -0.3), Vector2(0.2, -0.3), Vector2(0.2, -0.75), Vector2(1, 0), Vector2(0.2, 0.75), Vector2(0.2, 0.3), Vector2(-1, 0.3), Vector2(-1, -0.3)],
		"elbow": [Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)],
	}
	for kind in fixtures:
		var strokes := [{"points": fixtures[kind]}]
		var result := AutoSculpt.fit(strokes)
		check(result.error == "" and result.object.get("kind", "") == kind, "independent %s drawing is recognized (%s)" % [kind, result.object.get("kind", "rejected")])
		if not result.object.is_empty():
			var physical := PaperShapePhysics.prepare(result.object.paths)
			check(not physical.shapes.is_empty(), "%s has real collision" % kind)
	var arrow_parts: Array = []
	for index in [3,6,1,4,0,5,2]:
		var a: Vector2 = fixtures.arrow[index]
		var b: Vector2 = fixtures.arrow[index+1]
		arrow_parts.append({"points":[b,a] if index%2 == 0 else [a,b]})
	check(AutoSculpt.fit(arrow_parts).object.get("kind", "") == "arrow", "unordered and reversed strokes form one arrow")
	var noisy_arrow: Array = []
	for i in fixtures.arrow.size():
		var p: Vector2 = fixtures.arrow[i]
		noisy_arrow.append((p+Vector2(sin(i*2.1),cos(i*1.7))*0.018).rotated(-0.4)+Vector2(1,2))
	noisy_arrow[noisy_arrow.size()-1] = noisy_arrow[0]
	check(AutoSculpt.fit([{"points":noisy_arrow}]).object.get("kind", "") == "arrow", "rough tilted arrow retains its intended shape")
	var all_objects: Array = []
	var all_bag := BlueprintBag.new_bag()
	var mid_square := [Vector2(-0.06,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(-0.06,-1)]
	check(AutoSculpt.fit([{"points":mid_square}]).object.get("kind", "") == "square", "a square can start halfway along an edge")
	# Every declared template must be reachable through the real auto-recognition entry point.
	for entry in entries:
		if entry.kind in ["trapezoid","right_trapezoid","shield","tee","ell"]:
			for factor in [Vector2(1.5,0.8),Vector2(2,0.6),Vector2(-1,1)]:
				var stretched: Array = []
				for p in entry.points: stretched.append((p*factor).rotated(0.35)+Vector2(2,1))
				var aspect_result := AutoSculpt.fit([{"points":stretched}])
				check(aspect_result.object.get("kind", "") == entry.kind, "%s retains its corners with scale %s (%s)"%[entry.kind,str(factor),aspect_result.object.get("kind", "rejected")])
		var points: Array = entry.points.duplicate()
		var strokes := [{"points": points}]
		var result := AutoSculpt.fit(strokes)
		check(result.error == "" and result.object.get("kind", "") == entry.kind, "%s is actually recognizable (%s)" % [entry.kind, result.object.get("kind", "rejected")])
		if result.object.is_empty(): continue
		all_objects.append(result.object)
		BlueprintBag.add_entry(all_bag,result.object)
		check(not PaperShapePhysics.prepare(result.object.paths).shapes.is_empty(), "%s produces usable physics" % entry.kind)
		var bag := BlueprintBag.new_bag()
		var added := BlueprintBag.add_entry(bag, result.object)
		check(added.error == "" and added.entry.name.begins_with(entry.label), "%s has its own blueprint name" % entry.kind)
		if entry.kind in ["star5", "arrow", "trapezoid", "hexagon", "arc", "heart"]:
			points.reverse()
			for i in points.size(): points[i] = points[i].rotated(0.63) * 1.3 + Vector2(2.0, 0.4)
			var changed := AutoSculpt.fit([{"points": points}])
			check(changed.object.get("kind", "") == entry.kind, "%s tolerates rotation, reversal and translation" % entry.kind)
		if entry.kind in ["arch","c_shape"]:
			var solid := false
			for polygon in PaperShapePhysics.prepare(result.object.paths).fills:
				if Geometry2D.is_point_in_polygon(Vector2(0,0.25) - Vector2(result.object.x,result.object.y),polygon): solid = true
			check(not solid, "%s preserves its hollow opening" % entry.kind)
	check(SaveStore.save_game("draft",all_objects,all_bag,0,0).ok, "the expanded library can be saved")
	var loaded := SaveStore.load_game()
	check(loaded.error == "" and loaded.data.objects.size() == entries.size(), "all new types survive validated save/load")
	if loaded.error == "":
		for i in all_objects.size():
			check(loaded.data.objects[i].kind == all_objects[i].kind and loaded.data.objects[i].paths == all_objects[i].paths, "saved %s retains its exact geometry" % all_objects[i].kind)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	await process_frame
	game.toggle_sculpt()
	var placed_arrow: Array = []
	for p in fixtures.arrow: placed_arrow.append(p+Vector2(0,2))
	game.draft = [{"points":placed_arrow}]
	game.generate()
	check(game.objects.size() == 1 and game.objects[0].kind == "arrow", "5 generates a new library shape through the real game")
	check(game.bag.entries.back().name.begins_with("箭头"), "real 5 confirmation saves the correct new shape name")
	game.undo()
	check(game.objects.is_empty() and game.draw_mode == 5 and game.draft.size() == 1, "undo restores the raw arrow drawing")
	game.redo()
	check(game.objects.size() == 1 and game.objects[0].kind == "arrow", "redo restores the sculpted arrow")
	game.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("SCULPT LIBRARY: %d checks, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
