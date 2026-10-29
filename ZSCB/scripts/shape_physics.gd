class_name PaperShapePhysics
extends RefCounted

const INK_RADIUS := 0.035
const DENSITY := 4.0

# Closed contours become convex pieces; open or self-crossing ink stays a compound of round rods.
static func prepare(paths: Array) -> Dictionary:
	var shapes: Array = []
	var fills: Array = []
	var parts: Array = []
	for path in paths:
		if not path.get("collision", true): continue
		var points: Array = []
		for point in path.get("points", []):
			if not point is Vector2 or not point.is_finite(): continue
			if points.is_empty() or point.distance_squared_to(points.back()) > 0.000025: points.append(point)
		if points.size() < 2: continue
		points = _simplify(points, 0.012)
		var closed: bool = points.size() >= 4 and points[0].distance_to(points.back()) <= 0.12
		var polygon := PackedVector2Array(points)
		if closed:
			polygon.remove_at(polygon.size() - 1)
			if _simple(polygon):
				var properties := _polygon_properties(polygon)
				if properties.area > 0.008:
					if Geometry2D.is_polygon_clockwise(polygon): polygon.reverse()
					var pieces := Geometry2D.decompose_polygon_in_convex(polygon)
					if not pieces.is_empty():
						for piece in pieces: shapes.append({"polygon": piece})
						fills.append(polygon)
						parts.append(properties)
						continue
		for i in range(1, points.size()):
			var a: Vector2 = points[i - 1]
			var b: Vector2 = points[i]
			var length := a.distance_to(b)
			if length < 0.006: continue
			shapes.append({"a": a, "b": b})
			var area := 2 * INK_RADIUS * length + PI * INK_RADIUS * INK_RADIUS
			var mass := area * DENSITY
			parts.append({"area": area, "mass": mass, "center": (a + b) * 0.5, "inertia": mass * (length * length / 12 + INK_RADIUS * INK_RADIUS * 0.5)})
	var raw_mass := 0.0
	var weighted := Vector2.ZERO
	for part in parts:
		raw_mass += part.mass
		weighted += part.center * part.mass
	var center := weighted / raw_mass if raw_mass > 0 else Vector2.ZERO
	var moment := 0.0
	for part in parts: moment += part.inertia + part.mass * part.center.distance_squared_to(center)
	var mass := clampf(raw_mass, 0.15, 45)
	return {"shapes": shapes, "fills": fills, "center": center, "mass": mass, "inertia": maxf(0.0001, moment * mass / maxf(raw_mass, 0.0001))}

static func _polygon_properties(polygon: PackedVector2Array) -> Dictionary:
	var twice_area := 0.0
	var weighted := Vector2.ZERO
	var polar := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var cross := a.cross(b)
		twice_area += cross
		weighted += (a + b) * cross
		polar += cross * (a.dot(a) + a.dot(b) + b.dot(b))
	var area := absf(twice_area) * 0.5
	var center := weighted / (3 * twice_area) if absf(twice_area) > 0.00001 else Vector2.ZERO
	var mass := area * DENSITY
	return {"area": area, "center": center, "mass": mass, "inertia": maxf(0, absf(polar) * DENSITY / 12 - mass * center.length_squared())}

static func _simple(polygon: PackedVector2Array) -> bool:
	var count := polygon.size()
	if count < 3: return false
	for i in count:
		for j in range(i + 1, count):
			if j == i + 1 or (i == 0 and j == count - 1): continue
			if Geometry2D.segment_intersects_segment(polygon[i], polygon[(i + 1) % count], polygon[j], polygon[(j + 1) % count]) != null: return false
	return true

static func _simplify(points: Array, tolerance: float) -> Array:
	if points.size() <= 3: return points
	var farthest := 0.0
	var split := 0
	var a: Vector2 = points.front()
	var b: Vector2 = points.back()
	for i in range(1, points.size() - 1):
		var distance: float = points[i].distance_to(Geometry2D.get_closest_point_to_segment(points[i], a, b))
		if distance > farthest:
			farthest = distance
			split = i
	if farthest <= tolerance: return [a, b]
	var left := _simplify(points.slice(0, split + 1), tolerance)
	var right := _simplify(points.slice(split), tolerance)
	left.pop_back()
	left.append_array(right)
	return left
