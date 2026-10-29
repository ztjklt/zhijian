class_name ShapeMatcher

static func bounds(strokes: Array) -> Dictionary:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	var count := 0
	for stroke in strokes:
		var points: Array = stroke.get("points", stroke) if stroke is Dictionary else stroke
		for p in points:
			min_x = min(min_x, p.x)
			min_y = min(min_y, p.y)
			max_x = max(max_x, p.x)
			max_y = max(max_y, p.y)
			count += 1
	if count == 0:
		return {}
	return {
		"min_x": min_x, "min_y": min_y,
		"max_x": max_x, "max_y": max_y,
		"width": max_x - min_x, "height": max_y - min_y,
		"count": count,
	}

static func features(strokes: Array) -> Dictionary:
	var b := bounds(strokes)
	if b.is_empty() or (b.width < 0.08 and b.height < 0.08):
		return {}
	var horizontal := 0.0
	var vertical := 0.0
	var diagonal := 0.0
	var closed := 0
	var length := 0.0
	var count := 0
	for stroke in strokes:
		var pts: Array = stroke.get("points", stroke) if stroke is Dictionary else stroke
		if pts.size() >= 2:
			count += 1
			var first: Vector2 = pts[0]
			var last: Vector2 = pts[pts.size() - 1]
			var closing := first.distance_to(last)
			if pts.size() >= 4 and closing < max(0.15, min(b.width, b.height) * 0.24):
				closed += 1
			for i in range(1, pts.size()):
				var dx := absf(pts[i].x - pts[i - 1].x)
				var dy := absf(pts[i].y - pts[i - 1].y)
				var seg := sqrt(dx * dx + dy * dy)
				length += seg
				if dx > dy * 2:
					horizontal += seg
				elif dy > dx * 2:
					vertical += seg
				else:
					diagonal += seg
	if length < 0.25:
		return {}
	return {
		"aspect": max(b.width, 0.08) / max(b.height, 0.08),
		"horizontal": horizontal / length,
		"vertical": vertical / length,
		"diagonal": diagonal / length,
		"closed": 1.0 if closed > 0 else 0.0,
		"strokes": count,
		"bounds": b,
	}

const PROFILES := [
	{"id": "wall", "label": "城墙", "aspect": 2.0, "horizontal": 0.48, "vertical": 0.42, "diagonal": 0.10, "closed": 1},
	{"id": "tower", "label": "塔楼", "aspect": 0.55, "horizontal": 0.38, "vertical": 0.54, "diagonal": 0.08, "closed": 1},
	{"id": "gate", "label": "门洞", "aspect": 1.15, "horizontal": 0.18, "vertical": 0.52, "diagonal": 0.30, "closed": 0},
	{"id": "ramp", "label": "斜坡", "aspect": 2.0, "horizontal": 0.08, "vertical": 0.08, "diagonal": 0.84, "closed": 0},
	{"id": "platform", "label": "平台", "aspect": 3.2, "horizontal": 0.88, "vertical": 0.06, "diagonal": 0.06, "closed": 0},
	{"id": "ladder", "label": "梯子", "aspect": 0.35, "horizontal": 0.42, "vertical": 0.56, "diagonal": 0.02, "closed": 0},
]

static func rank(strokes: Array) -> Dictionary:
	var f := features(strokes)
	if f.is_empty():
		return {"ranked": [], "error": "笔画太短，请画出更完整的轮廓"}
	var ranked: Array = []
	for profile in PROFILES:
		var aspect_cost: float = absf(log(f.aspect / profile.aspect)) * 0.65
		var direction_cost: float = absf(f.horizontal - profile.horizontal) * 0.8 \
			+ absf(f.vertical - profile.vertical) * 0.8 \
			+ absf(f.diagonal - profile.diagonal) * 0.8
		var closure_cost: float = 0.0 if f.closed == profile.closed else 0.9
		ranked.append({
			"id": profile.id, "label": profile.label,
			"score": aspect_cost + direction_cost + closure_cost,
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	return {"ranked": ranked, "error": ""}

static func _scale_path(points: Array, width: float, height: float) -> Array:
	var result: Array = []
	for p in points:
		result.append(Vector2((p.x - 0.5) * width, (p.y - 0.5) * height))
	return result

static func make_prefab(id: String, raw_bounds: Dictionary) -> Array:
	var width: float = max(raw_bounds.width, 2.5 if id == "gate" else (0.8 if id == "ladder" else 0.7))
	var height: float = max(raw_bounds.height, 2.0 if id == "gate" else (2.2 if id == "ladder" else 0.3))
	var paths: Array = []
	var add := func(points: Array, collision: bool = true) -> void:
		paths.append({"points": _scale_path(points, width, height), "collision": collision})

	if id == "wall":
		add.call([Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(0,0)])
		add.call([Vector2(0.1,0.32), Vector2(0.9,0.32)], false)
		add.call([Vector2(0.1,0.66), Vector2(0.9,0.66)], false)
	elif id == "tower":
		add.call([Vector2(0.12,0), Vector2(0.88,0), Vector2(0.88,1), Vector2(0.12,1), Vector2(0.12,0)])
		add.call([Vector2(0.02,0.92), Vector2(0.02,1.08), Vector2(0.2,1.08), Vector2(0.2,0.92),
			Vector2(0.4,0.92), Vector2(0.4,1.08), Vector2(0.6,1.08), Vector2(0.6,0.92),
			Vector2(0.8,0.92), Vector2(0.8,1.08), Vector2(0.98,1.08), Vector2(0.98,0.92)], false)
		add.call([Vector2(0.38,0.58), Vector2(0.62,0.58), Vector2(0.62,0.80), Vector2(0.38,0.80), Vector2(0.38,0.58)], false)
	elif id == "gate":
		add.call([Vector2(0.10,0.86), Vector2(0.90,0.86)])
		add.call([Vector2(0.10,0), Vector2(0.10,0.86), Vector2(0.90,0.86), Vector2(0.90,0)], false)
		add.call([Vector2(0.27,0), Vector2(0.27,0.51), Vector2(0.37,0.68), Vector2(0.50,0.75),
			Vector2(0.63,0.68), Vector2(0.73,0.51), Vector2(0.73,0)], false)
	elif id == "ramp":
		add.call([Vector2(0,1), Vector2(1,0)])
		add.call([Vector2(0,1), Vector2(1,1)], false)
	elif id == "platform":
		add.call([Vector2(0,0.45), Vector2(1,0.45)])
		add.call([Vector2(0.06,0.56), Vector2(0.94,0.56)], false)
	elif id == "ladder":
		add.call([Vector2(0.12,0), Vector2(0.12,1)], false)
		add.call([Vector2(0.88,0), Vector2(0.88,1)], false)
		for rung in range(1, 6):
			var y := rung / 6.0
			add.call([Vector2(0.12,y), Vector2(0.88,y)], false)
	else:
		return []
	return paths
