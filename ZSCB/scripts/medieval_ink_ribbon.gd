extends RefCounted
## One feathered triangle strip per visible brush stroke. Shared vertices at
## joins avoid overshooting or darkening the paper at every Bézier sample.
static func draw(canvas: Node2D, game, line: PackedVector2Array, start: float, total: float, weight: String, cache: Dictionary) -> void:
	if line.size() < 2 or total <= 0.0002:
		return
	var ppu: float = game.PIXELS_PER_UNIT
	# The paper camera only translates or scales. Finished marks reuse their
	# local mesh while the camera walks; only the wet tip needs new vertices.
	if cache.is_empty() or cache.ppu != ppu or cache.count != line.size() or cache.tip != line[-1] or cache.start != start:
		bake(cache, line, start, total, weight, ppu)
	canvas.draw_set_transform(game.world_to_screen(line[0]))
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), cache.indices, cache.vertices, cache.colors)
	canvas.draw_set_transform(Vector2.ZERO)

static func bake(cache: Dictionary, line: PackedVector2Array, start: float, total: float, weight: String, ppu: float, tint := Color(0.095, 0.075, 0.058)) -> void:
	var ink := Color(tint, 0.88)
	var width := 3.4
	if weight == "fine":
		width = 2.05
		ink.a = 0.73
	elif weight == "faint":
		width = 1.5
		ink.a = 0.46
	var edge_color := Color(ink, 0)
	var centers := PackedVector2Array([Vector2.ZERO])
	var distances := PackedFloat32Array([start])
	var traveled := start
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length / 0.16))
		for j in range(1, steps + 1):
			var t := float(j) / steps
			centers.append((a.lerp(b, t) - line[0]) * Vector2(ppu, -ppu))
			distances.append(traveled + length * t)
		traveled += length

	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in centers.size():
		var prev := centers[maxi(0, i - 1)]
		var at := centers[i]
		var next := centers[mini(i + 1, centers.size() - 1)]
		var forward := (next - at).normalized()
		var tangent := (forward + (at - prev).normalized()).normalized()
		if tangent.length_squared() <= 0.0001:
			tangent = forward
		var normal := tangent.orthogonal()
		var join := 1.0
		if i > 0 and i < centers.size() - 1:
			join = minf(1.6, 1.0 / maxf(0.3, absf(tangent.dot(forward))))
		var s := clampf(distances[i] / total, 0, 1)
		var pressure := 0.30 + 0.70 * smoothstep(0, 0.17, s) * smoothstep(0, 0.23, 1 - s)
		var inner := maxf(0.06, 0.5 * width * pressure - 0.32) * join
		var outer := inner + 0.76 * join
		vertices.append_array(PackedVector2Array([at - normal*outer, at - normal*inner, at + normal*inner, at + normal*outer]))
		colors.append_array(PackedColorArray([edge_color, ink, ink, edge_color]))
		if i > 0:
			for band in 3:
				var v := (i - 1) * 4 + band
				indices.append_array(PackedInt32Array([v, v + 4, v + 5, v, v + 5, v + 1]))
	cache.ppu = ppu
	cache.count = line.size()
	cache.tip = line[-1]
	cache.start = start
	cache.vertices = vertices
	cache.colors = colors
	cache.indices = indices
