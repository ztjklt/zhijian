extends SceneTree
## Independent exhaustive contact oracle catches dropped ink and changed grip ordering.
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("BLADE NEAREST: " + label)

func paths_at(old: Array, current: Array, time: float) -> Array:
	if old.size() != current.size(): return current
	var result: Array = []
	for p in current.size():
		if old[p].size() != current[p].size(): result.append(current[p]); continue
		var points := PackedVector2Array()
		for i in current[p].size(): points.append(old[p][i] * (1.0 - time) + current[p][i] * time)
		result.append(points)
	return result

func exhaustive(old: Array, current: Array, geometry: Array, origin: Vector2) -> Dictionary:
	var distance := 0.0
	for p in mini(old.size(), current.size()):
		for i in mini(old[p].size(), current[p].size()): distance = maxf(distance, old[p][i].distance_to(current[p][i]))
	var steps := clampi(ceili(distance / 0.035), 1, 64)
	for sample in range(steps + 1):
		var time := float(sample) / steps
		var nearest := {}
		for path in paths_at(old, current, time):
			for i in range(1, path.size()):
				for outline in geometry:
					for j in range(1, outline.size()):
						var crossing = Geometry2D.segment_intersects_segment(path[i - 1], path[i], outline[j - 1], outline[j])
						var pair := Geometry2D.get_closest_points_between_segments(path[i - 1], path[i], outline[j - 1], outline[j])
						if crossing == null and pair[0].distance_squared_to(pair[1]) > 0.05 ** 2: continue
						var point: Vector2 = crossing if crossing != null else (pair[0] + pair[1]) * 0.5
						if not origin.is_finite(): return {"position": point, "time": time}
						if nearest.is_empty() or origin.distance_squared_to(point) < origin.distance_squared_to(nearest.position): nearest = {"position": point, "time": time}
		if not nearest.is_empty(): return nearest
	return {}

func same(a: Dictionary, b: Dictionary) -> bool:
	return a.is_empty() == b.is_empty() and (a.is_empty() or (is_equal_approx(a.time, b.time) and a.position.distance_to(b.position) < 0.00001))

func run() -> void:
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	var battle = game.combat
	var blades: Array = [PackedVector2Array([Vector2(1, 0), Vector2(1, 1)]), PackedVector2Array([Vector2(-1, 0), Vector2(-1, 1)])]
	var wall: Array = [PackedVector2Array([Vector2(-2, 0.5), Vector2(2, 0.5)])]
	var contact: Dictionary = battle._blade_geometry_contact(blades, blades, wall, Vector2(-2, 0.5))
	check(not contact.is_empty() and contact.position.is_equal_approx(Vector2(-1, 0.5)) and contact.time == 0, "later stroke nearest grip wins at same first time")
	contact = battle._blade_geometry_contact(blades, blades, wall, Vector2.INF)
	check(not contact.is_empty() and contact.position.is_equal_approx(Vector2(1, 0.5)), "absent grip keeps first traversal contact")
	var line: Array = [PackedVector2Array([Vector2.ZERO, Vector2.RIGHT])]
	for gap in [0.0, 0.0499, 0.05, 0.0501]:
		var edge: Array = [PackedVector2Array([Vector2(0.5, gap), Vector2(0.5, gap + 1)])]
		check(same(battle._blade_geometry_contact(line, line, edge, Vector2.ZERO), exhaustive(line, line, edge, Vector2.ZERO)), "zero-height and radius boundary " + str(gap))
	var hollow: Array = [PackedVector2Array([Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1)])]
	var inside: Array = [PackedVector2Array([Vector2(0, -0.5), Vector2(0, 0.5)])]
	check(battle._blade_geometry_contact(hollow, hollow, inside, Vector2.ZERO).is_empty(), "empty ink interior stays empty")
	check(battle._blade_geometry_contact(line, line, [], Vector2.ZERO).is_empty(), "no geometry means no contact")
	var rng := RandomNumberGenerator.new()
	rng.seed = 727105
	for trial in 64:
		var old: Array = []; var current: Array = []; var geometry: Array = []
		for p in 3:
			var before := PackedVector2Array(); var after := PackedVector2Array(); var outline := PackedVector2Array()
			var shift := Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			for i in 4:
				var point := Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
				before.append(point); after.append(point + shift)
				outline.append(Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)))
			old.append(before); current.append(after); geometry.append(outline)
		if trial % 8 == 0: old.pop_back()
		var origin := Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		check(same(battle._blade_geometry_contact(old, current, geometry, origin), exhaustive(old, current, geometry, origin)), "complete moving oracle " + str(trial))
	# Legal maximum point/stroke budget, with most ink far from actual material.
	var dense: Array = []; var material: Array = []
	for stroke in 128:
		var points := PackedVector2Array()
		for i in 64:
			points.append(Vector2(-1.0 + 2.0 * i / 63.0, 0) if stroke == 0 else Vector2(1.5 + i * 0.001, 1.5 + stroke * 0.001))
		dense.append(points)
	for i in 16: material.append(PackedVector2Array([Vector2(i * 0.01, -0.1), Vector2(i * 0.01, 0.1)]))
	var started := Time.get_ticks_usec()
	contact = battle._blade_geometry_contact(dense, dense, material, Vector2(-1, 0))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print("BLADE NEAREST MAX8192 elapsed_ms=", snappedf(elapsed, 0.001))
	# First endpoint within the 0.05m ink tolerance is x=-3/63; contact
	# lies halfway to wall x=0, so the grip-nearest contact is x=-1/42.
	check(not contact.is_empty() and contact.time == 0 and absf(contact.position.x + 1.0 / 42.0) < 0.00001, "all8192 points preserve nearest wall contact including ink radius")
	check(elapsed <= 16.67, "maximum ink contact ordering stays within unchanged16.67ms budget")
	game.queue_free()
	await process_frame
	print("BLADE NEAREST: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
