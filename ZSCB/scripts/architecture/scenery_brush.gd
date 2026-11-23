extends RefCounted
## Scenery paths and the building artwork are drawn in the same metre space.
const Palette := preload("res://scripts/pen_palette.gd")
const Ribbon := preload("res://scripts/medieval_ink_ribbon.gd")
const POOL := "wash_pool"
const BRUSHES := {"bold":"浓线", "fine":"细线", "wash":"淡墨铺色", POOL:"积色薄洗"}
const MIN_LENGTH := 0.045
const UNITS := 60.0
const ROWS := [0.0, 0.16, 0.38, 0.74, 1.0]
const DENSITY := [0.76, 1.37, 1.05, 0.75, 0.48]

static func is_wash(brush: String) -> bool:
	return brush == "wash" or brush == POOL

## Library washes store a polygon boundary. A pen path closes at its first point.
static func reference_points(points: Array, brush: String) -> Array:
	if not is_wash(brush) or points.size() < 3: return points
	var a = points.front()
	var b = points.back()
	if Vector2(a[0],a[1]).distance_to(Vector2(b[0],b[1])) <= 0.025: return points
	var closed := points.duplicate()
	closed.append(a)
	return closed

static func add_treatments(command: Dictionary, paths: Array) -> void:
	if paths.any(func(p): return p.has("ink_treatment")):
		command.ink_treatments = paths.map(func(p): return p.get("ink_treatment",""))

static func valid_treatments(command: Dictionary, count: int) -> bool:
	if not command.has("ink_treatments"): return true
	var treatments = command.ink_treatments
	if command.get("tool") != "draw_scenery" or not treatments is Array or treatments.size() != count: return false
	var brushes = command.get("brushes",[])
	if not brushes is Array or (not brushes.is_empty() and brushes.size() != count): return false
	for i in count:
		if treatments[i] not in ["","body","reserve"]: return false
		if treatments[i] == "reserve" and (brushes.is_empty() or brushes[i] not in ["wash",POOL]): return false
	return true

static func wash_polygon(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 4 or points[0].distance_to(points[-1]) > 0.025:
		return PackedVector2Array()
	var boundary := PackedVector2Array()
	for p in points:
		if boundary.is_empty() or boundary[-1].distance_squared_to(p) > 0.00000001:
			boundary.append(p)
	if boundary.size() > 1 and boundary[0].distance_to(boundary[-1]) <= 0.025:
		boundary.remove_at(boundary.size()-1)
	if boundary.size() < 3 or Geometry2D.triangulate_polygon(boundary).is_empty():
		return PackedVector2Array()
	return boundary

## Reuse the same convex cutouts as the physical body. Keep each pencil mark
## and colored wash local to its original layer when the object breaks.
static func after_damage(paths: Array, cuts: Array) -> Array:
	if cuts.is_empty(): return paths
	var cutters := []
	for i in cuts.size(): cutters.append(PaperObjectDamage._cutter(cuts[i],i))
	var result := []
	for path in paths:
		var points := PackedVector2Array(path.points)
		var pieces := []
		var brush: String = path.get("brush","bold")
		if is_wash(brush):
			var polygon := wash_polygon(points)
			var indices := Geometry2D.triangulate_polygon(polygon)
			for i in range(0,indices.size(),3):
				pieces.append(PackedVector2Array([polygon[indices[i]],polygon[indices[i+1]],polygon[indices[i+2]]]))
			for cutter in cutters:
				var clipped := []
				for piece in pieces: clipped.append_array(PaperObjectDamage._subtract(piece,cutter))
				pieces = clipped
			for piece in pieces:
				var boundary := PackedVector2Array(piece)
				boundary.append(boundary[0])
				var clipped_path := {"points":boundary,"brush":brush,"pigment":path.get("pigment","inherit")}
				if path.has("ink_treatment"): clipped_path.ink_treatment = path.ink_treatment
				if brush == POOL:
					clipped_path.wash_domain = _wash_bounds(polygon)
				result.append(clipped_path)
		else:
			for i in range(1,points.size()):
				for segment in PaperObjectDamage._remaining(points[i-1],points[i],cutters):
					PaperObjectDamage._append_path(pieces,segment)
			for piece in pieces:
				piece.brush = path.get("brush","bold")
				piece.pigment = path.get("pigment","inherit")
				if path.has("ink_treatment"): piece.ink_treatment = path.ink_treatment
				result.append(piece)
	return result

static func _wash_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	return bounds

## Clip a triangle (or one of its slices) in local paper coordinates. Computing
## each crossing from the lower endpoint makes adjacent slices meet exactly.
static func _clip_row(polygon: PackedVector2Array, row: float, above: bool) -> PackedVector2Array:
	var slice := PackedVector2Array()
	if polygon.is_empty():
		return slice
	var prev := polygon[-1]
	var prev_inside := prev.y >= row if above else prev.y <= row
	for p in polygon:
		var inside := p.y >= row if above else p.y <= row
		if inside != prev_inside:
			var lower := prev if prev.y < p.y else p
			var upper := p if prev.y < p.y else prev
			var x := lerpf(lower.x, upper.x, (row - lower.y) / (upper.y - lower.y))
			slice.append(Vector2(x, row))
		if inside:
			slice.append(p)
		prev = p
		prev_inside = inside
	return slice

## Slice the existing triangulation without painting a second transparent coat.
## Within each band the single alpha field is affine, even across old diagonals.
static func _pool_wash(polygon: PackedVector2Array, bounds: Rect2, ink: Color,
		vertices: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, triangles.size(), 3):
		var a := polygon[triangles[i]]
		var b := polygon[triangles[i + 1]]
		var c := polygon[triangles[i + 2]]
		var bottom := minf(a.y, minf(b.y, c.y))
		var top := maxf(a.y, maxf(b.y, c.y))
		var triangle := PackedVector2Array([a, b, c])
		for band in ROWS.size() - 1:
			var lo: float = bounds.position.y + ROWS[band] * bounds.size.y
			var hi: float = bounds.position.y + ROWS[band + 1] * bounds.size.y
			if top <= lo or bottom >= hi:
				continue
			var slice := triangle
			if bottom < lo:
				slice = _clip_row(slice, lo, true)
			if top > hi:
				slice = _clip_row(slice, hi, false)
			if slice.size() < 3:
				continue
			var base := vertices.size()
			for j in range(1, slice.size() - 1):
				if absf((slice[j] - slice[0]).cross(slice[j + 1] - slice[0])) > 0.000000001:
					indices.append_array(PackedInt32Array([base, base + j, base + j + 1]))
			vertices.append_array(slice)
			for p in slice:
				var amount := clampf((p.y - lo) / (hi - lo), 0, 1)
				var side := clampf((p.x - bounds.get_center().x) / bounds.size.x, -.5, .5)
				var density := lerpf(DENSITY[band], DENSITY[band + 1], amount) + side * 0.14
				colors.append(Color(ink, ink.a * density))

## One mesh stores the ordered pen marks in local, Y-up world metres.
static func mesh_for(paths: Array, color: Color) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for path in paths:
		var points := PackedVector2Array(path.points)
		var brush: String = path.get("brush", "bold")
		var pigment: String = path.get("pigment","inherit")
		var tint := Palette.resolve(pigment,color)
		if points.size() < 2: continue
		var base := vertices.size()
		if is_wash(brush):
			var polygon := wash_polygon(points)
			if polygon.size() < 3: continue
			var ink := Color(tint, 0.19 if pigment == "inherit" else 0.32)
			match path.get("ink_treatment",""):
				"body": ink.a = 0.60
				"reserve": ink = Color("#f8f4e8")
			if brush == POOL:
				var bounds: Rect2 = path.wash_domain if path.has("wash_domain") else _wash_bounds(polygon)
				if bounds.size.y >= 0.12 and bounds.size.x >= 0.04:
					_pool_wash(polygon, bounds, ink, vertices, colors, indices)
					continue
			for i in Geometry2D.triangulate_polygon(polygon): indices.append(base + i)
			vertices.append_array(polygon)
			for p in polygon: colors.append(ink)
		else:
			var length := 0.0
			for i in range(1, points.size()): length += points[i].distance_to(points[i-1])
			var ribbon := {}
			Ribbon.bake(ribbon, points, 0, length, brush, UNITS, tint)
			for v in ribbon.vertices: vertices.append(points[0] + v * Vector2(1,-1) / UNITS)
			for i in ribbon.indices: indices.append(base + i)
			if path.get("ink_treatment") == "body":
				for vertex_color: Color in ribbon.colors:
					if vertex_color.a > 0: vertex_color.a = 0.93
					colors.append(vertex_color)
			else:
				colors.append_array(ribbon.colors)
	var mesh := ArrayMesh.new()
	if not indices.is_empty():
		var surface := []
		surface.resize(Mesh.ARRAY_MAX)
		surface[Mesh.ARRAY_VERTEX] = vertices
		surface[Mesh.ARRAY_COLOR] = colors
		surface[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh
