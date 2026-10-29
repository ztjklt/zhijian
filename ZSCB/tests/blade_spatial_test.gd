extends SceneTree
## Independent exhaustive oracle preserves the pre-optimization contact contract.
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("BLADE SPATIAL: " + label)

func exhaustive(old_a: Array, current_a: Array, old_b: Array, current_b: Array) -> Dictionary:
	var distance := PaperBladeSweep.motion_distance(old_a, current_a) + PaperBladeSweep.motion_distance(old_b, current_b)
	var steps := clampi(ceili(distance / 0.035), 1, 64)
	for sample in range(steps + 1):
		var time := float(sample) / steps
		for a in PaperBladeSweep.at_time(old_a, current_a, time):
			for i in range(1, a.size()):
				for b in PaperBladeSweep.at_time(old_b, current_b, time):
					for j in range(1, b.size()):
						var crossing = Geometry2D.segment_intersects_segment(a[i - 1], a[i], b[j - 1], b[j])
						if crossing != null: return {"position": crossing, "time": time}
						var nearest := Geometry2D.get_closest_points_between_segments(a[i - 1], a[i], b[j - 1], b[j])
						if nearest[0].distance_squared_to(nearest[1]) <= 0.05 ** 2:
							return {"position": (nearest[0] + nearest[1]) * 0.5, "time": time}
	return {}

func same_contact(a: Dictionary, b: Dictionary) -> bool:
	return a.is_empty() == b.is_empty() and (a.is_empty() or (is_equal_approx(a.time, b.time) and a.position.distance_to(b.position) < 0.0001))

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 443021
	# Dropping any middle segment or motion endpoint makes these differ from the
	# exhaustive predicate. Includes static paths, overlap and distant geometry.
	for trial in range(64):
		var old_a: Array = []
		var current_a: Array = []
		var old_b: Array = []
		var current_b: Array = []
		for model in range(2):
			for path_index in range(2):
				var old := PackedVector2Array()
				var current := PackedVector2Array()
				var shift := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) if trial % 3 != 0 else Vector2.ZERO
				for point_index in range(4):
					var point := Vector2(rng.randf_range(-2, 2) + (6 if trial % 4 == 0 and model == 1 else 0), rng.randf_range(-2, 2))
					old.append(point)
					current.append(point + shift)
				if model == 0: old_a.append(old); current_a.append(current)
				else: old_b.append(old); current_b.append(current)
		check(same_contact(PaperBladeSweep.blade_contact(old_a, current_a, old_b, current_b), exhaustive(old_a, current_a, old_b, current_b)), "exact contact/time agrees with exhaustive moving paths " + str(trial))
	var horizontal: Array = [PackedVector2Array([Vector2.ZERO, Vector2.RIGHT])]
	var tangent: Array = [PackedVector2Array([Vector2(0.5, 0.04), Vector2(0.5, 1)])]
	check(not PaperBladeSweep.blade_contact(horizontal, horizontal, tangent, tangent).is_empty(), "zero-height bounds preserve contacts within the edge radius")
	check(not PaperBladeSweep.circle_contact(horizontal, horizontal, Vector2(0.5, 0.125), 0.1).is_empty(), "circle broad phase includes its maximum boundary")
	check(PaperBladeSweep.moving_point_time(horizontal, horizontal, Vector2(0.5, 1), Vector2(0.5, -1), 0.01) < 1, "arrow crossing survives swept bounds")
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var world = game.knowledge_world
	var battle = game.combat
	for chapter in range(6):
		var x: float = chapter * 26.0 + 9
		for height in [-0.1, 1.0, 3.5, 9.0]:
			var at := Vector2(x, world.surface_height(x) + height)
			var before: Array = [PackedVector2Array([at + Vector2(-1, -1), at + Vector2(1, 1)])]
			var after: Array = [PackedVector2Array([at + Vector2(1, -1), at + Vector2(-1, 1)])]
			var expected := exhaustive(before, after, world.collision_geometry, world.collision_geometry)
			var actual: Dictionary = battle._blade_structure(before, after)
			check(same_contact(actual, expected), "terrain index agrees across chapter/height " + str(chapter) + "/" + str(height))
	# A new map geometry array of identical length must invalidate old cells.
	var original: Array = world.collision_geometry
	world.collision_geometry = [PackedVector2Array([Vector2(1000, 0), Vector2(1000, 2)])]
	var far: Array = [PackedVector2Array([Vector2(999, 1), Vector2(1001, 1)])]
	check(not battle._blade_structure(far, far).is_empty(), "terrain replacement rebuilds the index")
	world.collision_geometry = [PackedVector2Array([Vector2(1005, 0), Vector2(1005, 2)])]
	check(battle._blade_structure(far, far).is_empty(), "same-count replacement cannot leave stale terrain contacts")
	world.collision_geometry.append(PackedVector2Array([Vector2(1000, 0), Vector2(1000, 2)]))
	check(not battle._blade_structure(far, far).is_empty(), "in-place terrain additions invalidate cached cells")
	world.collision_geometry = original
	var wall: Dictionary = DrawingRules.building([{"points": [Vector2.ZERO, Vector2(0, 2)]}], "freehand")
	wall.x = 1000.0
	wall.y = 0.0
	game.objects.append(wall)
	var middle: Array = [PackedVector2Array([Vector2(999.9, 1), Vector2(1000.1, 1)])]
	check(not battle._blade_structure(middle, middle).is_empty(), "dynamic structure retains middle-of-blade contact")
	wall.x = 1005.0
	check(battle._blade_structure(middle, middle).is_empty(), "moving a structure cannot leave a stale contact")
	wall.x = 1000.5
	wall.y = 1.0
	wall.angle = PI / 2
	check(not battle._blade_structure(middle, middle).is_empty(), "rotated structure uses its current full contour")
	game.objects.clear()
	game.queue_free()
	await process_frame
	print("BLADE SPATIAL TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
