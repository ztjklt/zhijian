class_name PaperInkReserve
extends RefCounted
## Session resource, deliberately outside world saves and undo history.
const MAXIMUM := 300.0
const RECOVERY_DELAY := 2.0
const RECOVERY_RATE := 25.0
const ARROW_COST := 4.0
var amount := MAXIMUM
var wait := 0.0
var last_cost := 0.0
var recent := 0.0

static func cost(object: Dictionary) -> float:
	var length := 0.0
	var area := 0.0
	for path in object.get("paths", []):
		var points = path.get("points", [])
		for i in range(1, points.size()): length += points[i - 1].distance_to(points[i])
		# Match the physics closure tolerance; its last endpoint is discarded.
		if points.size() > 3 and points[0].distance_to(points[-1]) <= 0.12:
			var polygon := PackedVector2Array(points)
			polygon.remove_at(polygon.size() - 1)
			if PaperShapePhysics._simple(polygon):
				area += PaperShapePhysics._polygon_properties(polygon).area
	return clampf(ceilf((12.0 if object.get("role", "") == "weapon" else 4.0) + length * 1.25 + area * 0.6), 6, 80)

func can_spend(price: float) -> bool:
	return is_finite(price) and price >= 0 and amount + 0.00001 >= price

func spend(price: float) -> bool:
	if not can_spend(price): return false
	if price == 0: return true
	amount = maxf(0, amount - price)
	wait = RECOVERY_DELAY
	last_cost = price
	recent = 0.9
	return true

func step(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	var recovery_time := maxf(0, delta - wait)
	wait = maxf(0, wait - delta)
	recent = maxf(0, recent - delta)
	amount = minf(MAXIMUM, amount + recovery_time * RECOVERY_RATE)
