extends RefCounted
## Pigment on a moving paper cutout. Coordinates run from its lower left to upper right.

static func _cut(mark: Dictionary, outline: PackedVector2Array, bounds := Rect2()) -> Array[PackedVector2Array]:
	if not bounds.has_area():
		bounds = Rect2(outline[0],Vector2.ZERO)
		for p in outline: bounds = bounds.expand(p)
	var path := PackedVector2Array()
	for uv in mark.points:
		var local := bounds.position + bounds.size * Vector2(uv[0],uv[1])
		if path.is_empty() or not local.is_equal_approx(path[-1]): path.append(local)
	if mark.brush=="thin":
		if path.size()<2: return []
		return Geometry2D.intersect_polyline_with_polygon(path,outline)
	if path.size()>1 and path[0].is_equal_approx(path[-1]): path.resize(path.size()-1)
	if path.size()<3 or Geometry2D.triangulate_polygon(path).size()!=(path.size()-2)*3: return []
	return Geometry2D.intersect_polygons(path,outline)

static func valid(marks: Variant, outline: PackedVector2Array, bounds := Rect2()) -> bool:
	if not marks is Array or marks.size()>8: return false
	for mark in marks:
		if not mark is Dictionary or mark.get("brush") not in ["thin","wash"]: return false
		var pigment = mark.get("pigment")
		if not pigment is String or pigment.length()!=7 or not pigment.begins_with("#") or not pigment.substr(1).is_valid_hex_number(false): return false
		if mark.has("source") and (not mark.source is String or mark.source.is_empty() or mark.source.length()>128): return false
		var points = mark.get("points")
		if not points is Array or points.size()<(2 if mark.brush=="thin" else 3) or points.size()>24: return false
		for uv in points:
			if not uv is Array or uv.size()!=2: return false
			for v in uv:
				if typeof(v) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(v) or v<0 or v>1: return false
		if _cut(mark,outline,bounds).is_empty(): return false
	return true

static func strokes(marks: Array, outline: PackedVector2Array, bounds := Rect2()) -> Array:
	var result := []
	for mark in marks:
		var is_wash: bool = mark.brush=="wash"
		var pigment := Color(str(mark.pigment),.64 if is_wash else .92)
		for clipped in _cut(mark,outline,bounds):
			if clipped.size()<(3 if is_wash else 2): continue
			if is_wash:
				if Geometry2D.triangulate_polygon(clipped).is_empty(): continue
				clipped.append(clipped[0])
			result.append({"points":clipped,"pigment":pigment,"brush":mark.brush})
	return result
