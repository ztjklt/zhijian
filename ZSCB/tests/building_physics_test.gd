extends SceneTree

var assertions := 0
var failures: Array[String] = []
var game

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		push_error("PHYSICS: " + label)

func _init() -> void:
	call_deferred("run")

func body(points: Array, at: Vector2, angle: float = 0.0) -> RigidBody2D:
	var data := {"x": at.x, "y": at.y, "angle": angle, "kind": "freehand", "source": "own", "role": "building", "paths": [{"points": points, "collision": true}], "dynamic": true, "health": 120.0, "max_health": 120.0}
	var result: RigidBody2D = load("res://scenes/build_object.tscn").instantiate()
	result.setup(data)
	game.add_child(result)
	return result

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_draw_mode(3)
	check(game.build_kind == "freehand", "buildings default to the actual hand-drawn contour")
	var triangle := [Vector2(-1, 0.9), Vector2(1, 0.9), Vector2(0.8, -0.9), Vector2(-1, 0.9)]
	var outline := DrawingRules.building([{"points": triangle}], "freehand")
	check(outline.dynamic, "new building factory produces a falling body")
	check((outline.paths[0].points[1] - outline.paths[0].points[0]).is_equal_approx(Vector2(2, 0)), "raw shape edges are preserved")
	var ghost := body([Vector2(-0.5, 0), Vector2(0.5, 0)], Vector2(20, -10))
	ghost.gravity_scale = 0
	for i in range(4): await physics_frame
	check(ghost.position.y < -9, "without contact the body is never teleported to the paper baseline")
	ghost.queue_free()
	var old_ladder: RigidBody2D = load("res://scenes/build_object.tscn").instantiate()
	old_ladder.setup({"x": 25.0, "y": 1.0, "kind": "ladder", "dynamic": true, "paths": ShapeMatcher.make_prefab("ladder", {"width": 0.8, "height": 2.2})})
	check(old_ladder.get_child_count() > 0, "legacy dynamic ladders still have physical support after removing the fake bottom circle")
	old_ladder.free()
	var tip := body(triangle, Vector2(5, game.GROUND_Y + 2.8))
	var flat := body([Vector2(-1, -0.3), Vector2(1, -0.3), Vector2(1, 0.3), Vector2(-1, 0.3), Vector2(-1, -0.3)], Vector2(10, game.GROUND_Y + 2.8))
	check(tip.center_of_mass_mode == RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM and tip.center_of_mass.distance_to(Vector2(0.2666667, 0.3)) < 0.025, "triangle uses its area centroid instead of an artificial bottom support")
	check(tip.continuous_cd != RigidBody2D.CCD_MODE_DISABLED, "falling ink uses continuous collision detection")
	for i in range(180): await physics_frame
	check(absf(tip.rotation) > 0.15, "off-center sloped base naturally tips under gravity")
	check(absf(flat.rotation) < 0.10, "symmetric flat base settles almost level")
	check(absf(flat.position.y - (game.GROUND_Y + 0.3)) < 0.10, "flat object rests on physical ground without a height clamp")
	tip.sync_to_data()
	var restored: RigidBody2D = game._build_physics_for_object(tip.data.duplicate(true))
	check(restored.position.distance_to(tip.position) < 0.05, "rebuilding a rotated resting body does not lift it using unrotated bounds")
	restored.queue_free()
	var stacked := body([Vector2(-0.65, -0.25), Vector2(0.65, -0.25), Vector2(0.65, 0.25), Vector2(-0.65, 0.25), Vector2(-0.65, -0.25)], Vector2(10, game.GROUND_Y + 2.2))
	for i in range(130): await physics_frame
	check(stacked.position.y > flat.position.y + 0.40, "falling bodies physically stack on other drawn bodies")
	var flat_shape_count := flat.get_child_count()
	check(flat_shape_count <= 3, "closed rectangles use solid polygon fixtures rather than a hidden bottom circle")
	# A U must retain its opening; a bounding rectangle or convex hull would fail.
	var cup := body([Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0.55, 1), Vector2(0.55, -0.55), Vector2(-0.55, -0.55), Vector2(-0.55, 1), Vector2(-1, 1)], Vector2(15, 1))
	cup.freeze = true
	await physics_frame
	var probe := PhysicsPointQueryParameters2D.new()
	probe.position = cup.to_global(Vector2(0, 0.5))
	probe.collision_mask = 1
	check(game.get_world_2d().direct_space_state.intersect_point(probe).is_empty(), "concave opening is not filled by an incorrect convex hull")
	probe.position = cup.to_global(Vector2(0.8, 0))
	check(not game.get_world_2d().direct_space_state.intersect_point(probe).is_empty(), "concave side has real solid collision")
	var round_points: Array = []
	for i in range(25):
		var angle := PI + PI * i / 24.0
		round_points.append(Vector2(cos(angle), sin(angle)))
	round_points.append(round_points[0])
	var rounded := body(round_points, Vector2(20, game.GROUND_Y + 3), 0.45)
	var moved := false
	for i in range(200):
		await physics_frame
		if absf(rounded.angular_velocity) > 0.2: moved = true
	check(moved and absf(rounded.rotation - 0.45) > 0.12, "a curved underside rocks or rolls according to contacts")
	# Draw while running, then stop the pen while movement continues.
	game.player.position = Vector2(-5.6, game.GROUND_Y + 0.54)
	game.draft = []
	var start: Vector2 = game.world_to_screen(Vector2(-1, game.GROUND_Y + 3))
	Input.action_press("move_right")
	game.pointer_down(start)
	game.pointer_move(start + Vector2(130, 0))
	for i in range(8): await physics_frame
	game.pointer_up(start + Vector2(130, 0))
	var after_first: int = game.objects.size()
	for i in range(5): await physics_frame
	game.pointer_down(start + Vector2(130, 0))
	game.pointer_move(start + Vector2(130, -70))
	game.pointer_up(start + Vector2(130, -70))
	check(game.objects.size() == after_first, "brief pause allows another stroke in the same building")
	for i in range(90): await physics_frame
	Input.action_release("move_right")
	check(game.player.position.x > -5, "WASD movement continues while drawing and dropping a building")
	check(game.objects.size() == after_first and game.draft.size() == 2, "pen-up keeps all strokes until explicit confirmation")
	game.generate()
	check(game.objects.size() == after_first + 1 and game.draft.is_empty(), "confirmation creates exactly one multi-stroke building")
	if game.objects.size() > after_first:
		check(game.objects.back().paths.size() == 2 and game.objects.back().dynamic, "both strokes belong to one native dynamic body")
		var node: RigidBody2D = game.object_nodes.back()
		check(not node.freeze and not node.lock_rotation, "dropped building can fall and rotate freely")
		var last: Dictionary = game.objects.back()
		last.angle = 0.4
		check(game.save_game(), "dynamic building can be saved")
		var loaded := SaveStore.load_game()
		check(loaded.error == "" and loaded.data.objects.back().dynamic, "validated save retains dynamic building state")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	# Manual finish, cancellation and grouping must never duplicate or unexpectedly submit ink.
	game.set_draw_mode(3)
	var count: int = game.objects.size()
	var pen_at: Vector2 = game.world_to_screen(Vector2(game.camera_x + 1, game.GROUND_Y + 2))
	game.pointer_down(pen_at)
	game.pointer_move(pen_at + Vector2(80, -20))
	game.generate()
	for i in range(80): await physics_frame
	check(game.objects.size() == count + 1, "F while drawing finishes exactly once without a later automatic duplicate")
	count = game.objects.size()
	game.pointer_down(pen_at)
	game.pointer_up(pen_at + Vector2(3, 0))
	for i in range(80): await physics_frame
	check(game.objects.size() == count and game.draft.is_empty(), "a tiny accidental tap never creates a falling body")
	game.pointer_down(pen_at)
	game.pointer_up(pen_at + Vector2(80, 0))
	game.set_draw_mode(2)
	for i in range(80): await physics_frame
	check(game.objects.size() == count, "changing mode never submits a pending drawing")
	game.set_draw_mode(3)
	check(game.draft.size() == 1, "mode switching preserves the building draft")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	for i in range(80): await physics_frame
	check(game.objects.size() == count, "losing focus never leaves a queued auto-build")
	game.pointer_down(pen_at)
	game.pointer_up(pen_at + Vector2(80, -30))
	game.toggle_bag()
	for i in range(80): await physics_frame
	check(game.objects.size() == count, "opening the bag keeps the pending multi-round drawing")
	game.toggle_bag()
	game.generate()
	check(game.objects.size() == count + 1, "paused multi-stroke building can still be finished manually")
	game.set_draw_mode(4)
	game.sync_objects()
	var selected_data: Dictionary = game.objects.back()
	var center: Vector2 = game.object_bounds(selected_data).get_center()
	var at: Vector2 = game.world_to_screen(center)
	game.pointer_down(at)
	game.pointer_move(at - Vector2(0, 150))
	var held: RigidBody2D = game.object_nodes[game.selected]
	var held_y := held.position.y
	for i in range(6): await physics_frame
	check(held.freeze and is_equal_approx(held.position.y, held_y), "a dragged dynamic building remains frozen in the hand")
	game.pointer_up(at - Vector2(0, 150))
	for i in range(8): await physics_frame
	check(not held.freeze and held.position.y < held_y - 0.02, "releasing an edited building returns it to gravity")
	# Compound placement protects players by translating overlaps, preserving real openings.
	game.objects.clear()
	game._rebuild_objects()
	await physics_frame
	await physics_frame
	game.player.position = Vector2(0, game.GROUND_Y + 0.30)
	game.player.linear_velocity = Vector2.ZERO
	# The overlap query reads the physics server, so let the teleported fixture synchronize.
	await physics_frame
	await physics_frame
	game.set_draw_mode(3)
	var unsafe_paths := [{"points": [Vector2(-1, -2.8), Vector2(1, -2.8), Vector2(1, -0.8), Vector2(-1, -0.8), Vector2(-1, -2.8)]}]
	game.draft = unsafe_paths.duplicate(true)
	var bag_count: int = game.bag.entries.size()
	game.release_building()
	check(game.objects.size() == 1 and game.draft.is_empty() and game.bag.entries.size() == bag_count+1, "overlap automatically creates one safe translated body and consumes the draft once")
	if not game.object_nodes.is_empty():
		check(PaperSpawnClearance._contacts(game,game.object_nodes.back(),Vector2.ZERO).is_empty(), "actual generated compound is clear immediately after automatic placement")
	for i in range(12): await physics_frame
	check(game.player.position.y > game.GROUND_Y, "automatically separated creation does not push the player through the floor")
	var overlap_entry := BlueprintBag.add_entry(game.bag, DrawingRules.building(unsafe_paths, "freehand"))
	game.placing_blueprint_id = overlap_entry.entry.id
	game.place_blueprint(0, game.GROUND_Y + 1.04)
	check(game.objects.size() == 2 and game.placing_blueprint_id == -1, "dynamic blueprint overlap uses the same successful automatic placement")
	game.objects.clear()
	game._rebuild_objects()
	await physics_frame
	game.placing_blueprint_id = -1
	game.player.position = Vector2(0, game.GROUND_Y + 0.54)
	game.player.linear_velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	var u_shape := [Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0.7, 1), Vector2(0.7, -0.9), Vector2(-0.7, -0.9), Vector2(-0.7, 1), Vector2(-1, 1)]
	game.draft = [{"points": u_shape.map(func(p: Vector2) -> Vector2: return p + Vector2(0, game.GROUND_Y + 1.04))}]
	game.release_building()
	check(game.objects.size() == 1, "a player inside a real concave opening is not rejected by a bounding-box test")
	game.objects.clear()
	game._rebuild_objects()
	var tilted: Dictionary = DrawingRules.building([{"points": [Vector2.ZERO, Vector2(0.8, 4)]}], "ladder")
	tilted.x = -2
	tilted.y = 1
	tilted.angle = PI / 4
	game.objects.append(tilted)
	game.object_nodes.append(game._build_physics_for_object(tilted))
	game.object_nodes.back().freeze = true
	game.set_draw_mode(2)
	game.player.position = Vector2(tilted.x, tilted.y) + Vector2(0, 1.5).rotated(tilted.angle)
	game.player.linear_velocity = Vector2.ZERO
	check(not game._find_ladder().is_empty(), "upper rail of a tilted ladder is detected in its own coordinates")
	game.jump_was_down = false
	Input.action_press("move_up")
	await physics_frame
	await physics_frame
	Input.action_release("move_up")
	check(game.climbing and game.player.linear_velocity.x < -0.8 and game.player.linear_velocity.y > 0.8, "climbing follows a tilted rail instead of world vertical")
	game.queue_free()
	await process_frame
	print("BUILDING PHYSICS: ", assertions, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
