extends RefCounted
## Saved cubic v1: one optional [out_x,out_y,in_x,in_y] per anchor span.
## Both handles are offsets from their own anchor. Null spans stay straight.
## Keep this deterministic subdivision scheme stable: work cursors refer to
## indices on the baked polyline, as do collision, ink and hand placement.
const FLATNESS := 0.009
const MAX_DEPTH := 5
const MAX_GROUND_SAMPLES := 128
const MAX_DETAIL_SAMPLES := 768
const EPSILON := 0.0002

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func validate_handles(handles: Variant, anchors: Array, bounds: Rect2, max_slope: float = INF) -> String:
	if handles == null:
		return ""
	if not handles is Array or handles.size() != anchors.size() - 1:
		return "每一对锚点需要对应一组控制柄或 null"
	for i in handles.size():
		var handle = handles[i]
		if handle == null:
			continue
		if not handle is Array or handle.size() != 4:
			return "控制柄须为四个相对坐标"
		for v in handle:
			if not _finite_number(v):
				return "控制柄坐标无效"
		var a := Vector2(anchors[i][0], anchors[i][1])
		var b := Vector2(anchors[i + 1][0], anchors[i + 1][1])
		var first := a + Vector2(handle[0], handle[1])
		var second := b + Vector2(handle[2], handle[3])
		for p: Vector2 in [first, second]:
			if not p.is_finite() or p.x < bounds.position.x - EPSILON or p.x > bounds.end.x + EPSILON or p.y < bounds.position.y - EPSILON or p.y > bounds.end.y + EPSILON:
				return "控制柄伸出本段纸面"
		if is_finite(max_slope):
			if first.x < a.x or second.x < first.x or b.x < second.x:
				return "地表曲线的两个控制点须按向东顺序留在锚点之间"
			for sign_y: float in [-1.0, 1.0]:
				var direction := Vector2(max_slope, sign_y)
				if _minimum_quadratic(direction.dot(first - a), direction.dot(second - first), direction.dot(b - second)) < -0.00005:
					return "曲线的局部斜率或端点切线过陡"
	return ""

# For a monotone cubic, |dy/dx| <= slope iff slope*x'(t) ± y'(t)
# stay nonnegative. These derivatives are quadratic Bernstein polynomials.
static func _minimum_quadratic(a: float, b: float, c: float) -> float:
	var minimum := minf(a, c)
	var bend := a - 2.0 * b + c
	if bend > 0:
		var t := (a - b) / bend
		if t > 0 and t < 1:
			minimum = minf(minimum, lerpf(lerpf(a, b, t), lerpf(b, c, t), t))
	return minimum

static func height(contour: PackedVector2Array, x: float) -> float:
	for i in range(1, contour.size()):
		var a := contour[i - 1]
		var b := contour[i]
		if x <= b.x:
			return lerpf(a.y, b.y, clampf((x - a.x) / (b.x - a.x), 0, 1))
	return contour[-1].y

# A painted stroke and its supporting ground are both polylines. Over any
# interval where both are linear their difference is linear, so its extrema
# occur at stroke vertices or at a crossed ground knot (including backstrokes).
static func clearance_range(line: PackedVector2Array, ground: PackedVector2Array) -> Vector2:
	var low := INF
	var high := -INF
	for i in line.size():
		var b := line[i]
		var gap := b.y - height(ground, b.x)
		low = minf(low, gap)
		high = maxf(high, gap)
		if i == 0:
			continue
		var a := line[i - 1]
		var left := minf(a.x, b.x)
		var right := maxf(a.x, b.x)
		for knot in ground:
			if knot.x <= left:
				continue
			if knot.x >= right:
				break
			var t := (knot.x - a.x) / (b.x - a.x)
			gap = lerpf(a.y, b.y, t) - knot.y
			low = minf(low, gap)
			high = maxf(high, gap)
	return Vector2(low, high)

static func _project(at: Vector2, soil: PackedVector2Array) -> Vector2:
	return at if soil.is_empty() else at + Vector2(0, height(soil, at.x))

static func _anchor(pair: Array, soil: PackedVector2Array) -> Vector2:
	# Legacy JSON heights are doubles. Add before converting to Vector2, just
	# as the original straight-stroke importer did.
	if soil.is_empty():
		return Vector2(pair[0], pair[1])
	return Vector2(pair[0], height(soil, pair[0]) + pair[1])

static func bake(anchors: Array, handles: Variant, soil := PackedVector2Array()) -> PackedVector2Array:
	var a := Vector2(anchors[0][0], anchors[0][1])
	var result := PackedVector2Array([_anchor(anchors[0], soil)])
	for i in range(1, anchors.size()):
		var b := Vector2(anchors[i][0], anchors[i][1])
		var h = null if handles == null else handles[i - 1]
		if h == null:
			var at := _anchor(anchors[i], soil)
			if result[-1].distance_to(at) > EPSILON:
				result.append(at)
		else:
			_subdivide(result, a, a + Vector2(h[0], h[1]), b + Vector2(h[2], h[3]), b, soil, 0)
		a = b
	return result

static func _subdivide(result: PackedVector2Array, a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, soil: PackedVector2Array, depth: int) -> void:
	# Split with de Casteljau. Distance to the finite chord also catches a loop
	# or a curve whose endpoints coincide. Height-relative marks are sampled
	# often enough to follow ground curvature underneath a long flat detail.
	var first := _project(a, soil)
	var last := _project(b, soil)
	var chord := last - first
	var flat := false
	if chord.length_squared() > 0.00000001:
		flat = true
		for pole: Vector2 in [c1, c2]:
			var point := _project(pole, soil)
			var closest := first + chord * clampf((point - first).dot(chord) / chord.length_squared(), 0, 1)
			if closest.distance_squared_to(point) > FLATNESS * FLATNESS:
				flat = false
				break
	if depth >= MAX_DEPTH or (flat and (soil.is_empty() or chord.length_squared() <= 0.16)):
		if result[-1].distance_to(last) > EPSILON:
			result.append(last)
		return
	var ac := (a + c1) * 0.5
	var bc := (b + c2) * 0.5
	var center := (c1 + c2) * 0.5
	var left := (ac + center) * 0.5
	var right := (bc + center) * 0.5
	var middle := (left + right) * 0.5
	_subdivide(result, a, ac, left, middle, soil, depth + 1)
	_subdivide(result, middle, right, bc, b, soil, depth + 1)

static func end_tangent(points: Array, handles: Variant) -> Vector2:
	var end := Vector2(points[-1][0], points[-1][1])
	var start := Vector2(points[-2][0], points[-2][1])
	var h = null if handles == null else handles[-1]
	if h != null:
		var incoming := -Vector2(h[2], h[3])
		if incoming.length_squared() > 0.00000001:
			return incoming.normalized()
		var remaining := end - start - Vector2(h[0], h[1])
		if remaining.length_squared() > 0.00000001:
			return remaining.normalized()
	return (end - start).normalized()
