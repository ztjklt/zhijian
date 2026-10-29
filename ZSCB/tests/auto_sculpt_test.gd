extends SceneTree

var assertions := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		push_error("SCULPT: " + label)

func _init() -> void:
	call_deferred("run")

func arc(center: Vector2, radius: Vector2, start: float, end: float, tilt: float = 0.0) -> Array:
	var points: Array = []
	for i in range(33):
		var t := lerpf(start, end, i / 32.0)
		var jitter := 1.0 + 0.035 * sin(i * 2.7)
		points.append(center + (Vector2(cos(t), sin(t)) * radius * jitter).rotated(tilt))
	return points

func run() -> void:
	check(ResourceLoader.exists("res://scripts/auto_sculpt.gd"), "automatic geometry fitting is available")
	if not ResourceLoader.exists("res://scripts/auto_sculpt.gd"):
		finish()
		return
	var sculpt = load("res://scripts/auto_sculpt.gd")
	var center := Vector2(1.8, 0.3)
	var circle: Dictionary = sculpt.fit([{"points": arc(center, Vector2.ONE, 0, TAU)}])
	check(circle.error == "" and circle.object.kind == "circle", "rough circle becomes a circle")
	if not circle.object.is_empty():
		var object: Dictionary = circle.object
		check(Vector2(object.x, object.y).distance_to(center) < 0.1, "fitting preserves the drawn position")
		for p in object.paths[0].points:
			check(absf(p.length() - 1.0) < 0.08, "every generated point lies on the same fitted circle")
		check(not PaperShapePhysics.prepare(object.paths).fills.is_empty(), "fitted closed shape has a solid collision interior")
	var split: Dictionary = sculpt.fit([{"points": arc(center, Vector2.ONE, PI, TAU)}, {"points": arc(center, Vector2.ONE, 0, PI)}])
	check(split.error == "" and split.object.kind == "circle", "two separately drawn semicircles form one circle")
	var rectangle: Array = []
	var corners := [Vector2(-1.6, -0.7), Vector2(1.6, -0.7), Vector2(1.6, 0.7), Vector2(-1.6, 0.7)]
	for i in range(4):
		rectangle.append({"points": [corners[(i + 1) % 4].rotated(0.4) + center, corners[i].rotated(0.4) + center]})
	var rect: Dictionary = sculpt.fit(rectangle)
	check(rect.error == "" and rect.object.kind == "rectangle", "four reversed separate edges form a rotated rectangle")
	if not rect.object.is_empty():
		var points: Array = rect.object.paths[0].points
		check(points.size() == 5 and points.front() == points.back(), "rectangle is exactly four closed edges")
		check(absf((points[1] - points[0]).dot(points[2] - points[1])) < 0.001, "adjacent rectangle edges are perpendicular")
		check(absf((points[1] - points[0]).normalized().x) > 0.2 and absf((points[1] - points[0]).normalized().y) > 0.2, "rectangle retains its tilt")
	var triangle: Dictionary = sculpt.fit([{"points": [Vector2(-1, 0), Vector2(0.1, 1.7), Vector2(1.4, 0.1), Vector2(-1, 0)]}])
	check(triangle.error == "" and triangle.object.kind == "triangle", "triangle is straightened without becoming a building prefab")
	var ellipse: Dictionary = sculpt.fit([{"points": arc(center, Vector2(1.8, 0.7), 0, TAU, 0.55)}])
	check(ellipse.error == "" and ellipse.object.kind == "ellipse", "elongated tilted ellipse retains its proportions")
	var line: Dictionary = sculpt.fit([{"points": [Vector2(0, 0), Vector2(0.5, 0.27), Vector2(1, 0.48), Vector2(2, 1)]}])
	check(line.error == "" and line.object.kind == "line" and line.object.paths[0].points.size() == 2, "jittered sloped line becomes one straight beam")
	check(not sculpt.fit([]).error.is_empty(), "blank drawing cannot generate geometry")
	check(not sculpt.fit([{"points": [Vector2.ZERO, Vector2(0.01, 0)]}]).error.is_empty(), "tiny scribble cannot generate geometry")
	var half: Dictionary = sculpt.fit([{"points": arc(center, Vector2.ONE, 0, PI)}])
	check(half.object.get("kind", "") == "arc", "an open semicircle becomes an arc without inventing a closing edge")
	if not half.object.is_empty():
		check(PaperShapePhysics.prepare(half.object.paths).fills.is_empty(), "open arcs never become solid half-disks")
	var dense: Array = []
	for part in range(8):
		var points: Array = []
		for i in range(72):
			var t := TAU * (part + i / 71.0) / 8.0
			points.append(center + Vector2(cos(t), sin(t)))
		dense.append({"points": points})
	var started := Time.get_ticks_msec()
	var dense_circle: Dictionary = sculpt.fit(dense)
	var duration := Time.get_ticks_msec() - started
	check(dense_circle.error == "" and dense_circle.object.kind == "circle", "dense eight-stroke circle remains the same shape")
	check(duration < 1000, "dense multi-stroke confirmation completes within one second (%d ms)" % duration)
	var density_kinds: Array = []
	for first_quadrant in [8, 60]:
		var points: Array = []
		for i in range(first_quadrant):
			var t: float = PI * 0.5 * i / first_quadrant
			points.append(Vector2(cos(t) * 1.2, sin(t)) * 2)
		for i in range(12):
			var t := PI * 0.5 + PI * 1.5 * i / 11.0
			points.append(Vector2(cos(t) * 1.2, sin(t)) * 2)
		var fitted: Dictionary = sculpt.fit([{"points": points}])
		density_kinds.append(fitted.object.get("kind", ""))
	check(density_kinds == ["ellipse", "ellipse"], "drawing one quadrant slowly cannot change an ellipse into a circle (%s)" % str(density_kinds))
	await session_checks()
	finish()

func press(action: String) -> void:
	await process_frame
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame
	await physics_frame

func draw(game, points: Array) -> void:
	game.pointer_down(game.world_to_screen(points[0]))
	for p in points.slice(1): game.pointer_move(game.world_to_screen(p))
	game.pointer_up(game.world_to_screen(points.back()))

func session_checks() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	game.onboarding.visible = false
	root.add_child(game)
	await process_frame
	check(game.has_method("toggle_sculpt"), "5 drawing session exists")
	if not game.has_method("toggle_sculpt"):
		game.queue_free()
		await process_frame
		return
	check(InputMap.has_action("hotbar_5"), "5 has a separate input action")
	check(InputMap.action_get_events("hotbar_5")[0].keycode == KEY_5, "the primary sculpt input is bound to digit 5")
	game.set_draw_mode(4)
	await press("hotbar_5")
	check(game.draw_mode == 5 and game.tool == "draw", "first 5 enters drawing from editing")
	var count: int = game.objects.size()
	await press("hotbar_5")
	check(game.draw_mode == 5 and game.objects.size() == count, "blank confirmation stays in drawing without creating an object")
	draw(game, arc(Vector2(0, 0.6), Vector2.ONE * 0.7, 0, PI))
	Input.action_press("move_right")
	var old_x: float = game.player.position.x
	for i in range(65): await physics_frame
	Input.action_release("move_right")
	check(game.objects.size() == count and game.draft.size() == 1, "pen-up and a long pause never submit a sculpt draft")
	check(game.player.position.x > old_x + 1.0, "movement remains available while accumulating strokes")
	draw(game, arc(Vector2(0, 0.6), Vector2.ONE * 0.7, TAU, PI))
	await press("hotbar_5")
	check(game.objects.size() == count + 1 and game.draw_mode == 4, "second 5 creates exactly one body and returns to the preceding mode")
	check(game.draft.is_empty(), "successful confirmation clears the sculpt draft")
	if game.objects.size() == count + 1:
		check(game.objects.back().kind == "circle" and game.objects.back().paths.size() == 1, "two strokes create one regular circle")
		check(not game.object_nodes.back().freeze and not game.object_nodes.back().fill_contours.is_empty(), "circle uses real solid falling physics")
		check(game.bag.entries.back().name.begins_with("圆形"), "blueprint has a recognizable geometry name")
		var copy := BlueprintBag.make_object(game.bag.entries.back(), 4, 1)
		check(copy.kind == "circle" and copy.paths == game.objects.back().paths, "reused blueprint retains the exact regular geometry")
		game.undo()
		check(game.objects.size() == count and game.draw_mode == 5 and game.draft.size() == 2, "undo restores both raw strokes and the open sculpt session")
		game.redo()
		check(game.objects.size() == count + 1 and game.draw_mode == 4, "redo restores the single generated body")
		check(game.save_game(), "sculpted object can be saved")
		var loaded := SaveStore.load_game()
		check(loaded.error == "" and loaded.data.objects.back().kind == "circle", "save validation and loading preserve sculpted shapes")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	game.set_draw_mode(1)
	game.draft = [{"points": [Vector2(-2, 1), Vector2(-1, 1)]}]
	await press("hotbar_5")
	check(game.draft.is_empty(), "other mode's draft never leaks into sculpting")
	draw(game, [Vector2(0, 2), Vector2(1, 2.3)])
	await press("cancel")
	check(game.draw_mode == 1 and game.draft.size() == 1, "Esc returns to the prior mode and restores its own draft")
	await press("hotbar_5")
	check(game.draft.size() == 1, "returning to sculpt mode preserves completed strokes")
	game.toggle_bag()
	await press("hotbar_5")
	check(game.draw_mode == 5 and game.draft.size() == 1, "5 cannot confirm through the blueprint panel")
	game.toggle_bag()
	game.toolbar.update_buttons()
	check(game.toolbar.mode_buttons.size() == 5 and game.toolbar.generate_button.text == "5 确认塑形", "toolbar exposes sculpt entry and numeric confirmation hint")
	var field := LineEdit.new()
	game.toolbar.add_child(field)
	field.grab_focus()
	await process_frame
	count = game.objects.size()
	await press("hotbar_5")
	check(game.draw_mode == 5 and game.draft.size() == 1 and game.objects.size() == count, "typing focus prevents an accidental 5 confirmation")
	field.release_focus()
	field.queue_free()
	await process_frame
	var original_bag: Dictionary = game.bag.duplicate(true)
	var filler := {"kind": "line", "paths": [{"points": [Vector2.ZERO, Vector2.ONE]}]}
	while game.bag.entries.size() < BlueprintBag.MAX_ENTRIES: BlueprintBag.add_entry(game.bag, filler)
	await press("hotbar_5")
	check(game.draw_mode == 5 and game.draft.size() == 1 and game.objects.size() == count, "a full blueprint bag preserves the drawing and session")
	game.bag = original_bag
	game.backpack_ui.refresh()
	game.draft = [{"points": [Vector2(30, 2), Vector2(31, 2)]}]
	count = game.objects.size()
	await press("hotbar_5")
	check(game.draw_mode == 5 and game.draft.size() == 1 and game.objects.size() == count, "too-far generation preserves the drawing and session")
	game.draft = [{"points": arc(game.player.position, Vector2.ONE * 0.6, 0, TAU)}]
	await press("hotbar_5")
	check(game.draw_mode == 1 and game.mode_drafts[5].is_empty() and game.objects.size() == count + 1, "player overlap automatically places the sculpt and finishes its confirmation session")
	if game.objects.size() == count + 1:
		check(game.object_nodes.back().get_meta("spawn_adjusted", false), "player overlap translates the sculpt to a safe position")
	game.set_draw_mode(5)
	count = game.objects.size()
	game.draft = []
	var smooth: Array = []
	for i in range(601):
		var t := TAU * i / 600.0
		smooth.append(Vector2(-2, 2) + Vector2(cos(t), sin(t)))
	draw(game, smooth)
	check(game.draft.size() == 1 and game.draft[0].points.front().distance_to(game.draft[0].points.back()) < 0.15, "a slowly drawn full circle keeps its closing endpoint")
	check(not AutoSculpt.fit(game.draft).object.is_empty(), "real pointer capture of a one-meter circle can be sculpted")
	game.draft = []
	game.pointer_down(game.world_to_screen(Vector2(1.5, 2)))
	game.pointer_move(game.world_to_screen(Vector2(2.5, 2.5)))
	await press("hotbar_5")
	check(game.objects.size() == count + 1 and game.active_stroke == null, "confirmation while holding the pen finishes one valid active stroke")
	game.queue_free()
	await process_frame

func finish() -> void:
	print("SCULPT CHECKS: %d assertions; %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
