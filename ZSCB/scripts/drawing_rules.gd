class_name DrawingRules
extends RefCounted

const GROUND := -2.8
const BUILD_RANGE := 12.0
const MAX_POINTS := 8192
const BUILD_KINDS := ["auto", "freehand", "platform", "wall", "ladder", "ramp", "tower", "gate"]

static func weapon(strokes: Array) -> Dictionary:
	var b := ShapeMatcher.bounds(strokes)
	if b.is_empty() or maxf(b.width, b.height) < 0.25:
		return {}
	var vertical: bool = b.height > b.width
	var length: float = maxf(b.width, b.height)
	var reach := clampf(length, 0.8, 2.7)
	var scale_factor := reach / length
	var paths: Array = []
	for stroke in strokes:
		var points: Array = []
		for p in stroke.points:
			var local := Vector2(p.y - b.min_y, (b.min_x + b.max_x) * 0.5 - p.x) if vertical else Vector2(p.x - b.min_x, p.y - (b.min_y + b.max_y) * 0.5)
			points.append(local * scale_factor)
		if points.size() >= 2: paths.append({"points": points, "collision": false})
	if paths.is_empty(): return {}
	var breadth: float = minf(b.width, b.height) * scale_factor
	var weight := clampf(breadth / reach, 0.0, 1.0)
	return {"source": "own", "role": "weapon", "kind": "weapon", "paths": paths,
		"reach": reach, "damage": roundf(18 + weight * 20), "cooldown": 0.34 + weight * 0.38,
		"dynamic": false, "x": 0.0, "y": 0.0, "angle": 0.0}

static func building(strokes: Array, choice: String) -> Dictionary:
	var b := ShapeMatcher.bounds(strokes)
	if b.is_empty() or maxf(b.width, b.height) < 0.25: return {}
	var kind := choice
	if choice == "auto":
		var match_result := ShapeMatcher.rank(strokes)
		if match_result.error != "": return {}
		kind = match_result.ranked[0].id
	if kind not in BUILD_KINDS: return {}
	var width: float = clampf(b.width, 0.3, 8.0)
	var height: float = clampf(b.height, 0.15, 6.0)
	var paths: Array = []
	if kind == "freehand":
		var center := Vector2((b.min_x + b.max_x) * 0.5, (b.min_y + b.max_y) * 0.5)
		var factor := minf(1.0, minf(8.0 / maxf(b.width, 0.01), 6.0 / maxf(b.height, 0.01)))
		for stroke in strokes:
			var points: Array = []
			for p in stroke.points: points.append((p - center) * factor)
			if points.size() > 1: paths.append({"points": points, "collision": true})
	else:
		paths = ShapeMatcher.make_prefab(kind, {"width": width, "height": height})
	if paths.is_empty(): return {}
	if kind == "ladder":
		for path in paths: path.collision = true
	elif kind == "gate" and paths.size() > 1: paths[1].collision = true
	return {"role": "building", "source": "own" if kind == "freehand" else "library", "kind": kind,
		"paths": paths, "dynamic": true, "angle": 0.0, "x": (b.min_x + b.max_x) * 0.5,
		"y": (b.min_y + b.max_y) * 0.5, "health": 120.0, "max_health": 120.0}

static func placement(source: Dictionary, desired: Vector2, objects: Array, player_pos: Vector2) -> Dictionary:
	var obj: Dictionary = source.duplicate(true)
	var b := ShapeMatcher.bounds(obj.paths)
	if b.is_empty(): return {"valid": false, "object": obj, "reason": "没有可放置的轮廓"}
	var pos := desired
	pos.y = maxf(pos.y, GROUND - b.min_y + 0.035)
	var bottom: float = pos.y + b.min_y
	var supported := absf(bottom - GROUND) <= 0.65
	if supported: pos.y = GROUND - b.min_y + 0.035
	var best := 0.45
	var correction := Vector2.ZERO
	# Snap path endpoints to existing fixed geometry, so platforms can bridge and stack.
	for other in objects:
		if other.get("role", "") != "building": continue
		for other_path in other.paths:
			for anchor in other_path.points:
				var world_anchor: Vector2 = anchor.rotated(float(other.get("angle", 0))) + Vector2(other.x, other.y)
				for path in obj.paths:
					for endpoint in [path.points.front(), path.points.back()]:
						var delta: Vector2 = world_anchor - (endpoint + pos)
						if delta.length() < best and pos.y + delta.y + b.min_y >= GROUND - 0.01:
							best = delta.length()
							correction = delta
							supported = true
	pos += correction
	obj.x = pos.x
	obj.y = pos.y
	if pos.distance_to(player_pos) > BUILD_RANGE:
		return {"valid": false, "object": obj, "reason": "离角色太远，走近一点再搭建"}
	if not supported:
		return {"valid": false, "object": obj, "reason": "把底边靠近地面，或把端点连到已有建筑"}
	for path in obj.paths:
		if not path.get("collision", true): continue
		for i in range(1, path.points.size()):
			var a: Vector2 = path.points[i - 1] + pos
			var z: Vector2 = path.points[i] + pos
			if Geometry2D.get_closest_point_to_segment(player_pos, a, z).distance_to(player_pos) < 0.38:
				return {"valid": false, "object": obj, "reason": "这里会挡住自己，换一个落点"}
	return {"valid": true, "object": obj, "reason": "已吸附 · 点击纸面放置"}
