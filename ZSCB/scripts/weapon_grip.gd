class_name PaperWeaponGrip
extends RefCounted

static func practice_sword() -> Dictionary:
	var sword := make_weapon([{"points": [Vector2(-0.035, 0), Vector2(-0.035, 0.64), Vector2(0, 0.83), Vector2(0.06, 0.64), Vector2(0.06, 0), Vector2(-0.035, 0)]}, {"points": [Vector2(-0.13, 0.14), Vector2(0.15, 0.14)]}], Vector2(-0.035, 0.065))
	sword.model_fill = true
	return sword

static func accepts(strokes: Array, point: Vector2) -> bool:
	return snap_point(strokes, point) != null

# A grip belongs to the ink, never merely to the empty bounding rectangle.
static func snap_point(strokes: Array, point: Vector2) -> Variant:
	if not point.is_finite(): return null
	var closest: Variant = null
	var distance := 0.12 * 0.12
	for stroke in strokes:
		var points: Array = stroke.get("points", [])
		for index in range(1, points.size()):
			var a: Vector2 = points[index - 1]
			var b: Vector2 = points[index]
			if not a.is_finite() or not b.is_finite(): continue
			var candidate := Geometry2D.get_closest_point_to_segment(point, a, b)
			var candidate_distance := point.distance_squared_to(candidate)
			if candidate_distance <= distance:
				distance = candidate_distance
				closest = candidate
	return closest

static func make_weapon(strokes: Array, point: Vector2) -> Dictionary:
	var snapped: Variant = snap_point(strokes, point)
	if snapped == null: return {}
	point = snapped
	var weapon := DrawingRules.weapon(strokes)
	if weapon.is_empty(): return {}
	var bounds := ShapeMatcher.bounds(strokes)
	var center := Vector2((bounds.min_x + bounds.max_x) * 0.5, (bounds.min_y + bounds.max_y) * 0.5)
	var factor: float = weapon.reach / maxf(bounds.width, bounds.height)
	weapon.paths = []
	weapon.grip = (point - center) * factor
	var farthest := 0.0
	for stroke in strokes:
		var points: Array = []
		for p in stroke.points:
			var local: Vector2 = (p - center) * factor
			points.append(local)
			farthest = maxf(farthest, local.distance_to(weapon.grip))
		if points.size() >= 2: weapon.paths.append({"points": points, "collision": false})
	weapon.reach = clampf(farthest, 0.8, 2.7)
	return weapon
