class_name PaperNetValidation
extends RefCounted

const MAX_STROKES := 128
const MAX_POINTS := DrawingRules.MAX_POINTS
const MAX_POSITION := 100000.0
const MAX_WIDTH := 8.0
const MAX_HEIGHT := 6.0

static func _fail(message: String, key: String) -> Dictionary:
	return {"ok": false, "error": message, key: {}}

static func _number(value: Variant, limit: float = MAX_POSITION) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= limit

static func _paths(value: Variant) -> Dictionary:
	if not value is Array or value.is_empty() or value.size() > MAX_STROKES: return {"ok": false}
	var paths: Array = []
	var total := 0
	for raw in value:
		if not raw is Dictionary: return {"ok": false}
		var points: Variant = raw.get("points")
		if not (points is Array or points is PackedVector2Array) or points.size() < 2: return {"ok": false}
		total += points.size()
		if total > MAX_POINTS or not raw.get("collision", true) is bool: return {"ok": false}
		var copied: Array = []
		for point in points:
			if not point is Vector2 or not point.is_finite() or absf(point.x) > MAX_WIDTH or absf(point.y) > MAX_HEIGHT: return {"ok": false}
			copied.append(point)
		paths.append({"points": copied, "collision": raw.get("collision", true)})
	var bounds := ShapeMatcher.bounds(paths)
	if bounds.width > MAX_WIDTH + 0.00001 or bounds.height > MAX_HEIGHT + 0.00001 or maxf(bounds.width, bounds.height) < 0.001: return {"ok": false}
	return {"ok": true, "paths": paths, "bounds": bounds}

static func _kind(value: Variant) -> bool:
	if not value is String or value.length() > 64: return false
	if value in ["freehand", "platform", "wall", "ladder", "ramp", "tower", "gate", "circle", "ellipse", "rectangle", "triangle", "line"]: return true
	for entry in SculptLibrary.entries():
		if value == entry.kind: return true
	return false

static func object(value: Variant) -> Dictionary:
	if not value is Dictionary: return _fail("造物格式无效", "object")
	if value.get("role", "building") not in ["", "building"] or value.get("source", "own") not in ["own", "library", "sculpt"] or not _kind(value.get("kind", "freehand")): return _fail("造物类型无效", "object")
	for field in ["x", "y", "angle"]:
		if not _number(value.get(field, 0.0), TAU * 1000 if field == "angle" else MAX_POSITION): return _fail("造物位置无效", "object")
	if not value.get("dynamic", true) is bool or not value.get("model_fill", false) is bool: return _fail("造物属性无效", "object")
	var geometry := _paths(value.get("paths"))
	if not geometry.ok: return _fail("造物笔画无效或超过上限", "object")
	# A whitelist makes all identity, revision, health and motion fields server-owned.
	var clean := {"role": "building", "source": value.get("source", "own"), "kind": value.get("kind", "freehand"),
		"x": float(value.get("x", 0)), "y": float(value.get("y", 0)), "angle": float(value.get("angle", 0)),
		"dynamic": value.get("dynamic", true), "paths": geometry.paths, "health": 120.0, "max_health": 120.0}
	return {"ok": true, "error": "", "object": clean}

static func weapon(value: Variant) -> Dictionary:
	if not value is Dictionary: return _fail("武器格式无效", "weapon")
	if not PaperWeaponTypes.valid(value.get("weapon_type", "sword")): return _fail("武器类型无效", "weapon")
	if value.get("role", "weapon") != "weapon" or value.get("kind", "weapon") != "weapon": return _fail("武器类型无效", "weapon")
	var geometry := _paths(value.get("paths"))
	if not geometry.ok: return _fail("武器笔画无效或超过上限", "weapon")
	var bounds: Dictionary = geometry.bounds
	if maxf(bounds.width, bounds.height) > 2.70001: return _fail("武器超过尺寸上限", "weapon")
	var grip: Variant = value.get("grip", Vector2.ZERO)
	if not grip is Vector2 or not grip.is_finite(): return _fail("武器握点无效", "weapon")
	var snapped: Variant = PaperWeaponGrip.snap_point(geometry.paths, grip)
	if snapped == null: return _fail("握点必须位于真实笔画", "weapon")
	var stats := DrawingRules.weapon(geometry.paths)
	if stats.is_empty(): return _fail("武器笔画太短", "weapon")
	var farthest := 0.0
	for path in geometry.paths:
		path.collision = false
		for point in path.points: farthest = maxf(farthest, point.distance_to(snapped))
	if farthest > 2.70001: return _fail("握点到剑身超过尺寸上限", "weapon")
	var reach := clampf(farthest, 0.8, 2.7)
	var derived := {"reach": reach, "damage": stats.damage, "cooldown": stats.cooldown}
	for field in derived:
		if value.has(field) and (not _number(value[field]) or not is_equal_approx(float(value[field]), float(derived[field]))): return _fail("武器属性与笔画不符", "weapon")
	if not value.get("model_fill", false) is bool: return _fail("武器填充属性无效", "weapon")
	var clean := {"source": "own", "role": "weapon", "kind": "weapon", "paths": geometry.paths, "grip": snapped,
		"reach": reach, "damage": stats.damage, "cooldown": stats.cooldown, "dynamic": false, "x": 0.0, "y": 0.0, "angle": 0.0}
	if value.has("weapon_type"): clean.weapon_type = value.weapon_type
	if value.has("model_fill"): clean.model_fill = value.model_fill
	return {"ok": true, "error": "", "weapon": clean}
