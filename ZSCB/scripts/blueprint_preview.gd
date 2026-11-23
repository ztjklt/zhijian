extends Control
const Pens := preload("res://scripts/functional_pens.gd")
var paths: Array = []
var pen_mesh: ArrayMesh

func set_entry(entry: Dictionary) -> void:
	paths = entry.get("paths",[])
	pen_mesh = Pens.Brush.mesh_for(paths,Pens.STYLES.get(entry.get("ink_style","ink"),PaperTheme.INK)) if entry.has("pen") else null
	queue_redraw()

func _draw() -> void:
	var bounds := ShapeMatcher.bounds(paths)
	if bounds.is_empty(): return
	var scale_factor: float = minf((size.x - 20) / maxf(bounds.width, 0.1), (size.y - 12) / maxf(bounds.height, 0.1))
	var center := Vector2((bounds.min_x + bounds.max_x) * 0.5, (bounds.min_y + bounds.max_y) * 0.5)
	if pen_mesh != null:
		if pen_mesh.get_surface_count() > 0:
			var zoom := Vector2(scale_factor,-scale_factor)
			draw_set_transform(size * 0.5-center*zoom,0,zoom)
			draw_mesh(pen_mesh,null)
			draw_set_transform(Vector2.ZERO)
		return
	for path in paths:
		var points := PackedVector2Array()
		for point in path.points:
			var p: Vector2 = (point - center) * scale_factor
			points.append(size * 0.5 + Vector2(p.x, -p.y))
		if points.size() > 1:
			draw_polyline(points, PaperTheme.INK, 1.8, true)
