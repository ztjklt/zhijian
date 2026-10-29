extends SceneTree

const Editorial := preload("res://scripts/semantic_layout.gd")

var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SPAWN CLEARANCE: " + label)

func run() -> void:
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.visible = false
	game.combat.set_natives(false)
	game.set_physics_process(false)
	game.player.freeze = true
	game.player.position = Vector2(9, -1.8)
	var letter := StaticBody2D.new()
	letter.collision_layer = 1
	letter.position = Vector2(11, 1)
	letter.set_meta("map_drop_allowed", true)
	var fixture := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4, 0.12)
	fixture.shape = shape
	letter.add_child(fixture)
	game.knowledge_world.add_child(letter)
	for i in range(3): await physics_frame
	var ink := [{"points": [Vector2(10.5,0.5),Vector2(11.5,0.5),Vector2(11.5,1.5),Vector2(10.5,1.5),Vector2(10.5,0.5)]}]
	var object: Dictionary = DrawingRules.building(ink, "freehand")
	var original_paths: Array = object.paths.duplicate(true)
	var body = game._drop_candidate(object)
	check(body != null, "ink overlapping a textbook surface is moved clear instead of rejected")
	if body != null:
		check(object.y > 1.55 and object.y < 2, "a local overlap resolves upward to the nearby paper surface")
		check(absf(object.x - 11) < 0.001, "minimal upward clearance does not move a building sideways across the map")
		check(object.paths == original_paths, "clearance translates the complete drawing without changing any stroke")
		body.freeze = true
		game.objects.append(object)
		game.object_nodes.append(game._attach_body(body, object))
		for i in range(3): await physics_frame
		var query := PhysicsShapeQueryParameters2D.new()
		query.collision_mask = 1
		query.exclude = [body.get_rid()]
		var clear := true
		for part in body.get_children():
			if part is CollisionShape2D:
				query.shape = part.shape
				query.transform = body.transform * part.transform
				clear = clear and game.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
		check(clear, "the spawned real collision fixtures are outside terrain, not just the preview")
		body.queue_free()
		game.objects.clear()
		game.object_nodes.clear()
	for i in range(3): await physics_frame
	# A single thin line should also escape; do not require a filled rectangle.
	var line: Dictionary = DrawingRules.building([{"points": [Vector2(10.8, 1.02), Vector2(11.5, 1.02)]}], "freehand")
	body = game._drop_candidate(line)
	check(body != null, "even a small overlapping open stroke may generate outside a letter")
	if body != null: body.free()
	game.knowledge_world.visit(1)
	game.player.position = Vector2(28, 2)
	for i in range(3): await physics_frame
	# SystemFont changes line widths across platforms. Locate actual material,
	# rather than assuming the first poem extends to a fixed world x coordinate.
	var poem_line: Array = []
	var poem_id: String = Editorial.poems()[0].id
	for path in game.knowledge_world.paths:
		if path.get("source", "") == poem_id:
			poem_line = path.points
			break
	check(poem_line.size() >= 2, "the fixture locates the actual first poem line")
	if poem_line.size() >= 2:
		var poem_at: Vector2 = (poem_line[0] + poem_line[1]) * 0.5
		var poem_points: Array = []
		for corner in [Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,0.5),Vector2(-0.5,-0.5)]:
			poem_points.append(poem_at + corner)
		var poem: Dictionary = DrawingRules.building([{"points": poem_points}], "freehand")
		var probe := BuildObject.new()
		probe.setup(poem)
		var hits_poem := false
		for hit in PaperSpawnClearance._contacts(game, probe, Vector2.ZERO):
			# Loaded path fixtures are centred on their material's segment midpoint.
			if hit.collider.get_parent().name.begins_with("InkChunk_") and hit.collider.global_position.is_equal_approx(poem_at):
				hits_poem = true
		check(hits_poem, "the unadjusted drawing physically overlaps the real first poem line")
		probe.free()
		body = game._drop_candidate(poem)
		check(body != null, "a drawing through the real first poem line can generate")
		if body != null:
			check(body.get_meta("spawn_adjusted", false), "the actual poem overlap triggers automatic separation")
			body.free()
	var collected: Dictionary = BlueprintBag.add_entry(game.bag, DrawingRules.building([{"points": [Vector2(0,0),Vector2(0.7,0)]}], "freehand"))
	game.placing_blueprint_id = collected.entry.id
	game.place_blueprint(50, 12)
	check(game.objects.is_empty(), "reusing a dynamic blueprint in empty space still respects the 12m build range")
	check(game.placing_blueprint_id == collected.entry.id, "an out-of-range placement keeps the selected blueprint ready to retry")
	for node in game.object_nodes: node.free()
	game.objects.clear()
	game.object_nodes.clear()
	# Player overlap now translates the complete solid to its nearest safe space.
	game.player.position = Vector2(11, 1)
	for i in range(3): await physics_frame
	object = DrawingRules.building(ink, "freehand")
	body = game._drop_candidate(object)
	check(body != null, "a requested player overlap automatically moves to a safe position")
	if body != null:
		check(body.get_meta("spawn_adjusted",false), "player overlap records automatic adjustment")
		check(PaperSpawnClearance._contacts(game,body,Vector2.ZERO).is_empty(), "automatically placed solid is clear of the live player and terrain")
	if body != null: body.free()
	game.queue_free()
	await process_frame
	print("SPAWN CLEARANCE TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
