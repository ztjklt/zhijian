extends RefCounted
## Cross sections of the same convex pieces used for the surviving ink area.
const TOLERANCE := 0.00001

static func _intervals(pieces: Array, offset: float, vertical: bool) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	for polygon: PackedVector2Array in pieces:
		var low := INF
		var high := -INF
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var normal_a := a.x if vertical else a.y
			var normal_b := b.x if vertical else b.y
			var along_a := a.y if vertical else a.x
			var along_b := b.y if vertical else b.x
			if absf(normal_a - offset) <= TOLERANCE:
				low = minf(low, along_a)
				high = maxf(high, along_a)
			if (normal_a < offset and normal_b > offset) or (normal_a > offset and normal_b < offset):
				var hit := lerpf(along_a, along_b, (offset - normal_a) / (normal_b - normal_a))
				low = minf(low, hit)
				high = maxf(high, hit)
		if high - low > TOLERANCE:
			spans.append(Vector2(low, high))
	spans.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var merged: Array[Vector2] = []
	for span in spans:
		if merged.is_empty() or span.x > merged[-1].y + TOLERANCE:
			merged.append(span)
		else:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, span.y))
	return merged

static func measure(pieces: Array, origin: Vector2, levels: Array) -> Array:
	var rows := []
	for height in levels:
		if typeof(height) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(height)):
			continue
		var local_y := float(height) - origin.y
		var spans := []
		for width in _intervals(pieces, local_y, false):
			var depth := 0.0
			var probe_x := 0.0
			for fraction in [0.25, 0.5, 0.75]:
				var x := lerpf(width.x, width.y, fraction)
				for column in _intervals(pieces, x, true):
					if column.x < local_y and local_y <= column.y + TOLERANCE and local_y - column.x > depth:
						depth = local_y - column.x
						probe_x = x
			if depth > TOLERANCE:
				spans.append({"left": origin.x + width.x, "right": origin.x + width.y,
					"depth": depth, "at": [origin.x + probe_x, float(height)]})
		rows.append({"level": float(height), "spans": spans})
	return rows
