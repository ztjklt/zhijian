extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("CASTLE LAYOUT: "+label)
func finish() -> void:
	print("CASTLE LAYOUT TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func run() -> void:
	var path := "res://scripts/medieval_castle_layout.gd"
	check(ResourceLoader.exists(path),"deterministic castle atlas decomposition exists")
	if not ResourceLoader.exists(path): finish(); return
	var layout = load(path)
	var parts: Array = layout.records()
	print("CASTLE ATLAS: ",parts.size()," separate contiguous tiles")
	check(parts.size() >= 20 and parts.size() <= 40,"concept becomes a bounded set of independently destructible pieces")
	var ids := {}
	var min_x := INF
	var max_x := -INF
	var top := -INF
	var total_area := 0.0
	for part in parts:
		check(part.kind == "castle_piece" and not ids.has(part.id),"each atlas tile has its own stable identity "+part.id)
		ids[part.id] = true
		var source: Rect2 = part.source_uv
		check(source.position.x >= 0 and source.position.y >= 0 and source.end.x <= 1.0001 and source.end.y <= 1.0001,"source tile stays inside the master atlas "+part.id)
		check(layout.descriptor(part.id).size.is_equal_approx(part.size),"restoring an identity resolves the same physical dimensions "+part.id)
		min_x = minf(min_x,part.x-part.size.x*0.5)
		max_x = maxf(max_x,part.x+part.size.x*0.5)
		for polygon in part.polygons:
			check(polygon.size() >= 3 and not Geometry2D.decompose_polygon_in_convex(polygon).is_empty(),"tile provides real valid collision geometry "+part.id)
			for point in polygon: top = maxf(top,part.y+point.y)
			total_area += area(polygon)
	check(min_x >= 67.99 and max_x <= 88.01 and max_x-min_x >= 19.5,"castle spans the twenty-metre plateau without crossing its edges")
	check(top-layout.FLOOR >= 10 and top-layout.FLOOR <= 12,"pointed keep silhouette rises ten to twelve metres")
	var gate: Vector2 = layout.entry_position()
	var player := PackedVector2Array([gate+Vector2(-0.24,0.04),gate+Vector2(0.24,0.04),gate+Vector2(0.24,1.24),gate+Vector2(-0.24,1.24)])
	var blocked := false
	for part in parts:
		for polygon in world_polygons(part):
			for overlap in Geometry2D.intersect_polygons(player,polygon):
				if area(overlap) > 0.0001: blocked = true
	check(not blocked,"gate opening fits the actual character body rather than an opaque atlas rectangle")
	var overlap_area := 0.0
	var source_overlap := 0.0
	var matched_edges := 0
	for i in parts.size():
		for j in range(i+1,parts.size()):
			var a_uv: Rect2 = parts[i].source_uv
			var b_uv: Rect2 = parts[j].source_uv
			if a_uv.intersects(b_uv): source_overlap += a_uv.intersection(b_uv).get_area()
			if is_equal_approx(a_uv.position.y,b_uv.position.y) and is_equal_approx(a_uv.end.x,b_uv.position.x):
				check(is_equal_approx(parts[i].x+parts[i].size.x*0.5,parts[j].x-parts[j].size.x*0.5),"adjacent source pixels meet at the same world-space seam")
				matched_edges += 1
			if is_equal_approx(a_uv.position.x,b_uv.position.x) and is_equal_approx(a_uv.end.y,b_uv.position.y):
				check(is_equal_approx(parts[i].y,parts[j].y+parts[j].size.y),"vertical source strips meet with no missing world-space row")
			for a in world_polygons(parts[i]):
				for b in world_polygons(parts[j]):
					for overlap in Geometry2D.intersect_polygons(a,b): overlap_area += area(overlap)
	check(overlap_area < 0.001,"seamless tile joins do not duplicate overlapping physical solids")
	check(source_overlap < 0.000001 and matched_edges >= 20,"atlas tiles cover adjacent ink with no duplicated or missing source strip")
	check(total_area > 100,"castle is a substantial connected building rather than detached tiny props")
	check(layout.descriptor("castle-piece-999").is_empty(),"unknown saved tile identities cannot invent geometry")
	var mutated: Array = layout.records()
	mutated[0].x = -1000
	check(layout.records()[0].x > 60,"callers cannot mutate the canonical layout through a returned record")
	for role in layout.role_positions():
		var feet := Vector2(role.x,role.y)
		var supported := false
		var embedded := false
		for part in parts:
			for polygon in world_polygons(part):
				if Geometry2D.is_point_in_polygon(feet+Vector2(0,-0.01),polygon): supported = true
				if Geometry2D.is_point_in_polygon(feet+Vector2(0,0.1),polygon): embedded = true
		check(supported and not embedded,"royal "+role.kind+" stands on a real open wall walk")
	finish()
func area(points: PackedVector2Array) -> float:
	var result := 0.0
	for i in points.size(): result += points[i].cross(points[(i+1)%points.size()])
	return absf(result)*0.5
func world_polygons(part: Dictionary) -> Array:
	var result: Array = []
	for polygon in part.polygons:
		var points := PackedVector2Array()
		for point in polygon: points.append(point+Vector2(part.x,part.y))
		result.append(points)
	return result
