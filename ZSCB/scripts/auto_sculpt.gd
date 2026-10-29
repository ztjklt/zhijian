class_name AutoSculpt
extends RefCounted

const LABELS := {"circle": "圆形", "ellipse": "椭圆", "rectangle": "矩形", "triangle": "三角形", "line": "直线"}

static func label(kind: String) -> String:
	if LABELS.has(kind): return LABELS[kind]
	for entry in SculptLibrary.entries():
		if entry.kind == kind: return entry.label
	return "几何部件"

# Compare both directions so a partial arc cannot silently invent a whole circle.
static func fit(strokes: Array) -> Dictionary:
	var b := ShapeMatcher.bounds(strokes)
	if b.is_empty() or maxf(b.width, b.height) < 0.25:
		return {"object": {}, "error": "笔画太短，请继续补画，再按 5 确认"}
	var span := Vector2(b.width, b.height).length()
	var segments: Array = []
	var samples: Array[Vector2] = []
	var total_length := 0.0
	for stroke in strokes:
		var pts: Array = stroke.get("points", [])
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var z: Vector2 = pts[i]
			if not a.is_finite() or not z.is_finite():
				return {"object": {}, "error": "轮廓无效，请重新绘画"}
			if a.distance_to(z) < 0.0001: continue
			segments.append([a, z])
			total_length += a.distance_to(z)
	# Carry sample spacing across segment boundaries: drawing slowly must not add weight.
	var spacing := maxf(span / 60.0, total_length / 512.0)
	var next_sample := spacing * 0.5
	var walked := 0.0
	for segment in segments:
		var length: float = segment[0].distance_to(segment[1])
		while next_sample < walked + length:
			samples.append(segment[0].lerp(segment[1], (next_sample - walked) / length))
			next_sample += spacing
		walked += length
	if samples.size() < 2:
		return {"object": {}, "error": "请画出完整轮廓，再按 5 确认"}
	var center := Vector2.ZERO
	for p in samples: center += p
	center /= samples.size()
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	var xr := 0.0
	var yr := 0.0
	for p in samples:
		var v := p - center
		xx += v.x * v.x
		xy += v.x * v.y
		yy += v.y * v.y
		xr += v.x * v.length_squared()
		yr += v.y * v.length_squared()
	var angle := 0.5 * atan2(2 * xy, xx - yy)
	var candidates: Array = []
	var box := _box(samples, angle)
	var line := [Vector2(box.min.x, (box.min.y + box.max.y) * 0.5).rotated(angle), Vector2(box.max.x, (box.min.y + box.max.y) * 0.5).rotated(angle)]
	candidates.append({"kind": "line", "points": line, "penalty": 0.0})
	var determinant := xx * yy - xy * xy
	if determinant > 0.000001:
		var circle_center := center + Vector2(yy * xr - xy * yr, xx * yr - xy * xr) / (2 * determinant)
		var radius := 0.0
		for p in samples: radius += p.distance_to(circle_center)
		radius /= samples.size()
		candidates.append({"kind": "circle", "points": _oval(circle_center, Vector2.ONE * radius, 0), "penalty": 0.0})
	var radii: Vector2 = (box.max - box.min) * 0.5
	if minf(radii.x, radii.y) > 0.06 and maxf(radii.x, radii.y) / minf(radii.x, radii.y) > 1.18:
		candidates.append({"kind": "ellipse", "points": _oval(((box.min + box.max) * 0.5).rotated(angle), radii, angle), "penalty": 0.006})
	var all_points := PackedVector2Array()
	for segment in segments:
		all_points.append(segment[0])
		all_points.append(segment[1])
	var hull := Geometry2D.convex_hull(all_points)
	if hull.size() > 3:
		hull.remove_at(hull.size() - 1)
		hull = _corners(hull)
		var best_area := INF
		var rectangle: Array = []
		for i in hull.size():
			var tilt := (hull[(i + 1) % hull.size()] - hull[i]).angle()
			var extent := _box(Array(all_points), tilt)
			var size: Vector2 = extent.max - extent.min
			if size.x * size.y < best_area:
				best_area = size.x * size.y
				rectangle = []
				for p in [extent.min, Vector2(extent.max.x, extent.min.y), extent.max, Vector2(extent.min.x, extent.max.y), extent.min]:
					rectangle.append(p.rotated(tilt))
		candidates.append({"kind": "rectangle", "points": rectangle, "penalty": 0.0})
		var largest := 0.0
		var triangle: Array = []
		# A maximum-area inscribed triangle finds the three original corners even with edge jitter.
		for i in hull.size():
			for j in range(i + 1, hull.size()):
				for k in range(j + 1, hull.size()):
					var area := absf((hull[j] - hull[i]).cross(hull[k] - hull[i]))
					if area > largest:
						largest = area
						triangle = [hull[i], hull[j], hull[k], hull[i]]
		candidates.append({"kind": "triangle", "points": triangle, "penalty": 0.0})
	candidates.append_array(SculptLibrary.candidates(strokes, span))
	var best: Dictionary = {}
	var best_score := INF
	for candidate in candidates:
		var error := _score(candidate.points, samples, segments, span)
		var score: float = error + candidate.penalty
		if score < best_score:
			best_score = score
			best = candidate
	if best.is_empty() or best_score > 0.065:
		return {"object": {}, "error": "轮廓还不够清楚，请继续补画几何轮廓，再按 5"}
	var fitted := ShapeMatcher.bounds([{"points": best.points}])
	var origin := Vector2((fitted.min_x + fitted.max_x) * 0.5, (fitted.min_y + fitted.max_y) * 0.5)
	var local_points: Array = []
	for p in best.points: local_points.append(p - origin)
	return {"object": {"kind": best.kind, "source": "sculpt", "role": "building", "paths": [{"points": local_points, "collision": true}],
		"x": origin.x, "y": origin.y, "angle": 0.0, "dynamic": true, "health": 120.0, "max_health": 120.0}, "error": ""}

static func _box(points: Array, angle: float) -> Dictionary:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in points:
		var v: Vector2 = p.rotated(-angle)
		low = low.min(v)
		high = high.max(v)
	return {"min": low, "max": high}

static func _corners(hull: PackedVector2Array) -> PackedVector2Array:
	# Retain significant corners; bound the cubic triangle search on densely sampled curves.
	while hull.size() > 24:
		var least_area := INF
		var remove := 0
		for i in hull.size():
			var previous := hull[(i + hull.size() - 1) % hull.size()]
			var next := hull[(i + 1) % hull.size()]
			var area := absf((hull[i] - previous).cross(next - previous))
			if area < least_area:
				least_area = area
				remove = i
		hull.remove_at(remove)
	return hull

static func _oval(center: Vector2, radii: Vector2, angle: float) -> Array:
	var points: Array = []
	for i in range(64):
		var t := TAU * i / 64.0
		points.append(center + (Vector2(cos(t), sin(t)) * radii).rotated(angle))
	points.append(points[0])
	return points

static func _distance(point: Vector2, segments: Array) -> float:
	var nearest := INF
	for segment in segments:
		nearest = minf(nearest, point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])))
	return nearest

static func _score(points: Array, samples: Array[Vector2], raw: Array, span: float) -> float:
	var edges: Array = []
	for i in range(1, points.size()): edges.append([points[i - 1], points[i]])
	if edges.is_empty(): return INF
	var forward := 0.0
	for p in samples: forward += _distance(p, edges)
	var reverse := 0.0
	var count := 0
	for edge in edges:
		var steps := maxi(1, ceili(edge[0].distance_to(edge[1]) / (span / 60.0)))
		for step in steps:
			var distance := _distance(edge[0].lerp(edge[1], (step + 0.5) / steps), raw)
			if sqrt(distance) > span * 0.18: return INF
			reverse += distance
			count += 1
	return sqrt((forward / samples.size() + reverse / count) * 0.5) / span
