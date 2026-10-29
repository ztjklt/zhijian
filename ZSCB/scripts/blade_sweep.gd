class_name PaperBladeSweep
extends RefCounted
## Contacts use the displayed weapon's complete paths and their swept motion.
## No owner-centered reach cone, guessed attack ray, or effect arc is a hit box.

const EDGE_RADIUS := 0.025
const SAMPLE_SPACING := 0.035
const MAX_SAMPLES := 64

static func motion_distance(old: Array, current: Array) -> float:
	var distance := 0.0
	for i in mini(old.size(), current.size()):
		for j in mini(old[i].size(), current[i].size()):
			distance = maxf(distance, old[i][j].distance_to(current[i][j]))
	return distance

static func at_time(old: Array, current: Array, time: float) -> Array:
	if old.size() != current.size(): return current
	var result: Array = []
	for i in current.size():
		if old[i].size() != current[i].size():
			result.append(current[i])
			continue
		var path := PackedVector2Array()
		for j in current[i].size(): path.append(old[i][j].lerp(current[i][j], time))
		result.append(path)
	return result

static func _point_contact(paths: Array, center: Vector2, radius: float, filled: bool = false) -> Dictionary:
	for path in paths:
		if filled and path.size() > 3 and path[0].is_equal_approx(path[-1]) and Geometry2D.is_point_in_polygon(center, path):
			return {"position": center}
		for i in range(1, path.size()):
			var point := Geometry2D.get_closest_point_to_segment(center, path[i - 1], path[i])
			if point.distance_squared_to(center) <= (radius + EDGE_RADIUS) ** 2:
				return {"position": point}
	return {}

static func bounds(paths: Array) -> Rect2:
	var result := Rect2()
	var started := false
	for path in paths:
		for point in path:
			if not started:
				result = Rect2(point, Vector2.ZERO)
				started = true
			else: result = result.expand(point)
	return result

static func swept_bounds(old: Array, current: Array) -> Rect2:
	if old.is_empty(): return bounds(current)
	if current.is_empty(): return bounds(old)
	return bounds(old).merge(bounds(current))

static func circle_contact(old: Array, current: Array, center: Vector2, radius: float, filled: bool = false) -> Dictionary:
	if current.is_empty() or not swept_bounds(old, current).grow(radius + EDGE_RADIUS).intersects(Rect2(center, Vector2.ZERO), true): return {}
	var steps := clampi(ceili(motion_distance(old, current) / SAMPLE_SPACING), 1, MAX_SAMPLES)
	for i in range(steps + 1):
		var time := float(i) / steps
		var hit := _point_contact(at_time(old, current, time), center, radius, filled)
		if not hit.is_empty():
			hit.time = time
			return hit
	return {}

static func moving_point_time(old: Array, current: Array, a: Vector2, b: Vector2, radius: float, filled: bool = false) -> float:
	if current.is_empty() or not swept_bounds(old, current).grow(radius + EDGE_RADIUS).intersects(Rect2(a, Vector2.ZERO).expand(b), true): return INF
	var steps := clampi(ceili((motion_distance(old, current) + a.distance_to(b)) / SAMPLE_SPACING), 1, MAX_SAMPLES)
	for i in range(steps + 1):
		var time := float(i) / steps
		if not _point_contact(at_time(old, current, time), a.lerp(b, time), radius, filled).is_empty(): return time
	return INF

static func blade_contact(old_a: Array, current_a: Array, old_b: Array, current_b: Array) -> Dictionary:
	if current_a.is_empty() or current_b.is_empty(): return {}
	if not swept_bounds(old_a, current_a).grow(EDGE_RADIUS * 2).intersects(swept_bounds(old_b, current_b), true): return {}
	var static_a := old_a == current_a
	var static_b := old_b == current_b
	var distance := motion_distance(old_a, current_a) + motion_distance(old_b, current_b)
	var steps := clampi(ceili(distance / SAMPLE_SPACING), 1, MAX_SAMPLES)
	for sample in range(steps + 1):
		var time := float(sample) / steps
		var paths_a := current_a if static_a else at_time(old_a, current_a, time)
		var paths_b := current_b if static_b else at_time(old_b, current_b, time)
		for a in paths_a:
			for i in range(1, a.size()):
				var segment_bounds := Rect2(a[i - 1], Vector2.ZERO).expand(a[i]).grow(EDGE_RADIUS * 2)
				for b in paths_b:
					for j in range(1, b.size()):
						if not segment_bounds.intersects(Rect2(b[j - 1], Vector2.ZERO).expand(b[j]), true): continue
						var crossing = Geometry2D.segment_intersects_segment(a[i - 1], a[i], b[j - 1], b[j])
						if crossing != null: return {"position": crossing, "time": time}
						var nearest := Geometry2D.get_closest_points_between_segments(a[i - 1], a[i], b[j - 1], b[j])
						if nearest[0].distance_squared_to(nearest[1]) <= (EDGE_RADIUS * 2) ** 2:
							return {"position": (nearest[0] + nearest[1]) * 0.5, "time": time}
	return {}

static func model_damage(weapon: Dictionary, speed: float) -> float:
	var length := 0.0
	var area := 0.0
	var grip: Vector2 = weapon.get("grip", Vector2.ZERO)
	for path in weapon.get("paths", []):
		var points = path.points
		for point in points: length = maxf(length, point.distance_to(grip))
		if points.size() > 3 and points[0].is_equal_approx(points[-1]):
			var signed_area := 0.0
			for i in range(1, points.size()): signed_area += points[i - 1].cross(points[i])
			area += absf(signed_area) * 0.5
	var model_weight := 8.0 + clampf(length, 0, 2.7) * 10 + sqrt(minf(area, 0.5)) * 12
	var momentum := clampf(0.55 + maxf(0, speed) / 18.0, 0.55, 1.4)
	return roundf(clampf(model_weight * momentum, 5.0, 40.0))
