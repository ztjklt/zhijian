extends Control
var paths: Array = []
func _draw() -> void:
	var bounds := ShapeMatcher.bounds(paths)
	if bounds.is_empty(): return
	var scale_factor: float = minf((size.x - 20) / maxf(bounds.width, 0.1), (size.y - 12) / maxf(bounds.height, 0.1))
	var center := Vector2((bounds.min_x + bounds.max_x) * 0.5, (bounds.min_y + bounds.max_y) * 0.5)
	for path in paths:
		var points := PackedVector2Array()
		for point in path.points:
			var p: Vector2 = (point - center) * scale_factor
			points.append(size * 0.5 + Vector2(p.x, -p.y))
		if points.size() > 1:
			draw_polyline(points, PaperTheme.INK, 1.8, true)
