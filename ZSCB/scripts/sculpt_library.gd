class_name SculptLibrary
extends RefCounted

const SAMPLE_COUNT := 32
static var _entries: Array = []

static func entries() -> Array:
	if not _entries.is_empty(): return _entries
	_add("square", "正方形", [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)], true, false)
	_add("rhombus", "菱形", [Vector2(0,1), Vector2(0.6,0), Vector2(0,-1), Vector2(-0.6,0)], true, false)
	_add("parallelogram", "平行四边形", [Vector2(-1,-0.7), Vector2(0.6,-0.7), Vector2(1,0.7), Vector2(-0.6,0.7)])
	_add("trapezoid", "梯形", [Vector2(-1,-1), Vector2(1,-1), Vector2(0.6,1), Vector2(-0.6,1)])
	_add("right_trapezoid", "直角梯形", [Vector2(-1,-1), Vector2(1,-1), Vector2(0.5,1), Vector2(-1,1)])
	_add("kite", "风筝形", [Vector2(0,1), Vector2(0.7,-0.2), Vector2(0,-1), Vector2(-0.7,-0.2)])
	for item in [[5,"pentagon","正五边形"], [6,"hexagon","正六边形"], [7,"heptagon","正七边形"], [8,"octagon","正八边形"], [9,"nonagon","正九边形"], [10,"decagon","正十边形"], [12,"dodecagon","正十二边形"]]:
		_add(item[1], item[2], _radial(item[0], 1.0), true, false)
	for item in [[4,"star4","四角星"], [5,"star5","五角星"], [6,"star6","六角星"], [8,"star8","八角星"]]:
		_add(item[1], item[2], _radial(item[0] * 2, 0.43), true, false)
	_add("cross", "十字形", [Vector2(-0.3,1),Vector2(0.3,1),Vector2(0.3,0.3),Vector2(1,0.3),Vector2(1,-0.3),Vector2(0.3,-0.3),Vector2(0.3,-1),Vector2(-0.3,-1),Vector2(-0.3,-0.3),Vector2(-1,-0.3),Vector2(-1,0.3),Vector2(-0.3,0.3)])
	_add("tee", "T形部件", [Vector2(-1,1),Vector2(1,1),Vector2(1,0.4),Vector2(0.3,0.4),Vector2(0.3,-1),Vector2(-0.3,-1),Vector2(-0.3,0.4),Vector2(-1,0.4)])
	_add("ell", "L形部件", [Vector2(-1,-1),Vector2(1,-1),Vector2(1,-0.4),Vector2(-0.4,-0.4),Vector2(-0.4,1),Vector2(-1,1)])
	_add("chevron", "人字形", [Vector2(-1,-1),Vector2(0,-0.3),Vector2(1,-1),Vector2(1,-0.3),Vector2(0,0.5),Vector2(-1,-0.3)])
	_add("arrow", "箭头", [Vector2(-1,-0.3),Vector2(0.2,-0.3),Vector2(0.2,-0.75),Vector2(1,0),Vector2(0.2,0.75),Vector2(0.2,0.3),Vector2(-1,0.3)])
	_add("double_arrow", "双向箭头", [Vector2(-1,0),Vector2(-0.4,-0.7),Vector2(-0.4,-0.25),Vector2(0.4,-0.25),Vector2(0.4,-0.7),Vector2(1,0),Vector2(0.4,0.7),Vector2(0.4,0.25),Vector2(-0.4,0.25),Vector2(-0.4,0.7)])
	var heart: Array = []
	for i in range(48):
		var t := TAU * i / 48.0
		heart.append(Vector2(16 * pow(sin(t),3), 13*cos(t)-5*cos(2*t)-2*cos(3*t)-cos(4*t)) / 17.0)
	_add("heart", "心形", heart)
	_add("shield", "盾形", [Vector2(-1,1),Vector2(1,1),Vector2(0.85,-0.4),Vector2(0,-1),Vector2(-0.85,-0.4)])
	_add("house", "房屋轮廓", [Vector2(-1,-1),Vector2(1,-1),Vector2(1,0.25),Vector2(0,1),Vector2(-1,0.25)])
	var capsule := _arc(Vector2(0.6,0), 0.5, -PI/2, PI/2, 16)
	capsule.append_array(_arc(Vector2(-0.6,0), 0.5, PI/2, PI*1.5, 16))
	_add("capsule", "胶囊形", capsule)
	var rounded: Array = []
	for i in range(4):
		var corner: Vector2 = [Vector2(0.75,0.45),Vector2(-0.75,0.45),Vector2(-0.75,-0.45),Vector2(0.75,-0.45)][i]
		rounded.append_array(_arc(corner, 0.25, PI*0.5*i, PI*0.5*(i+1), 6))
	_add("rounded_rectangle", "圆角矩形", rounded)
	_add("semicircle", "半圆", _arc(Vector2.ZERO, 1, 0, PI))
	var quarter: Array = [Vector2.ZERO]
	quarter.append_array(_arc(Vector2.ZERO, 1, 0, PI/2))
	_add("quarter_disk", "四分之一圆", quarter, true, false)
	var sector: Array = [Vector2.ZERO]
	sector.append_array(_arc(Vector2.ZERO, 1, 0, PI*2/3))
	_add("sector", "扇形", sector, true, false)
	var arch := _arc(Vector2.ZERO, 1, 0, PI)
	arch.append_array(_arc(Vector2.ZERO, 0.55, PI, 0))
	_add("arch", "拱形", arch)
	var crescent := _arc(Vector2.ZERO, 1, PI/4, PI*1.75)
	crescent.append_array(_arc(Vector2.ZERO, 0.55, PI*1.75, PI/4))
	_add("c_shape", "C形部件", crescent)
	_add("elbow", "直角折线", [Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)], false)
	_add("v_line", "V形折线", [Vector2(-1,1),Vector2(0,-1),Vector2(1,1)], false)
	_add("zigzag", "锯齿折线", [Vector2(-1,0.6),Vector2(-0.5,-0.6),Vector2(0,0.6),Vector2(0.5,-0.6),Vector2(1,0.6)], false)
	_add("arc", "半圆弧", _arc(Vector2.ZERO,1,0,PI), false)
	_add("quarter_arc", "四分之一圆弧", _arc(Vector2.ZERO,1,0,PI/2), false, false)
	_add("three_quarter_arc", "四分之三圆弧", _arc(Vector2.ZERO,1,0,PI*1.5), false, false)
	return _entries

static func _radial(count: int, inner: float) -> Array:
	var points: Array = []
	for i in count:
		var radius := inner if inner < 1 and i % 2 == 1 else 1.0
		points.append(Vector2.from_angle(PI/2 + TAU*i/count) * radius)
	return points

static func _arc(center: Vector2, radius: float, start: float, end: float, steps: int = 24) -> Array:
	var points: Array = []
	for i in range(steps + 1): points.append(center + Vector2.from_angle(lerpf(start,end,i/float(steps))) * radius)
	return points

static func _add(kind: String, label: String, points: Array, closed: bool = true, stretch: bool = true) -> void:
	if closed: points.append(points[0])
	var samples := _resample(points, closed)
	var center := _mean(samples)
	for i in samples.size(): samples[i] -= center
	_entries.append({"kind":kind,"label":label,"points":points,"closed":closed,"stretch":stretch,"samples":samples,"center":center})

# Join only nearby endpoints, never draw artificial segments between disconnected strokes.
static func _join(strokes: Array, span: float) -> Array:
	var remaining: Array = []
	for stroke in strokes:
		if stroke.points.size() >= 2: remaining.append(stroke.points.duplicate())
	if remaining.is_empty(): return []
	var points: Array = remaining.pop_front()
	while not remaining.is_empty():
		var best := span * 0.12
		var selected := -1
		var reverse := false
		var prepend := false
		for i in remaining.size():
			for end in range(2):
				for side in range(2):
					var p: Vector2 = remaining[i].front() if end == 0 else remaining[i].back()
					var distance: float = p.distance_to(points.front() if side == 0 else points.back())
					if distance < best:
						best = distance
						selected = i
						prepend = side == 0
						reverse = end == side
		if selected < 0: return []
		var next: Array = remaining.pop_at(selected)
		if reverse: next.reverse()
		if prepend:
			next.append_array(points)
			points = next
		else: points.append_array(next)
	return points

static func candidates(strokes: Array, span: float) -> Array:
	var points := _join(strokes, span)
	if points.size() < 2: return []
	var closed: bool = points.front().distance_to(points.back()) < span * 0.12
	if closed: points[points.size()-1] = points[0]
	var target := _resample(points, closed)
	var center := _mean(target)
	for i in target.size(): target[i] -= center
	var ranked := _polygon_candidates(points, span, closed)
	for entry in entries():
		if entry.closed != closed: continue
		var best: Dictionary = {"error":INF}
		for reverse in [false,true]:
			for shift in range(SAMPLE_COUNT if closed else 1):
				var fit := _align(entry, target, shift, reverse)
				if fit.error < best.error: best = fit
		if sqrt(best.error) / span > 0.09: continue
		var fitted: Array = []
		for p in entry.points: fitted.append(center + ((p-entry.center)*best.scale).rotated(best.angle))
		ranked.append({"kind":entry.kind,"points":fitted,"penalty":-0.0005 if entry.kind == "square" else 0.001,"match_error":best.error})
	ranked.sort_custom(func(a: Dictionary,b: Dictionary): return a.match_error < b.match_error)
	return ranked.slice(0, 4)

static func _align(entry: Dictionary, target: Array, shift: int, reverse: bool) -> Dictionary:
	return _align_samples(entry.samples, target, shift, reverse, entry.stretch, entry.closed)

static func _align_samples(source: Array, target: Array, shift: int, reverse: bool, stretch: bool, closed: bool) -> Dictionary:
	var count := source.size()
	var scale := Vector2.ONE
	var angle := 0.0
	var xx := 0.0
	var yy := 0.0
	for p in source:
		xx += p.x*p.x
		yy += p.y*p.y
	for iteration in range(5):
		var dot := 0.0
		var cross := 0.0
		for i in count:
			var index := posmod(shift-i, count) if reverse and closed else count-1-i if reverse else (i+shift)%count
			var p: Vector2 = source[i]*scale
			dot += p.dot(target[index])
			cross += p.cross(target[index])
		angle = atan2(cross,dot)
		var sx := 0.0
		var sy := 0.0
		for i in count:
			var index := posmod(shift-i, count) if reverse and closed else count-1-i if reverse else (i+shift)%count
			var v: Vector2 = target[index].rotated(-angle)
			sx += source[i].x*v.x
			sy += source[i].y*v.y
		if stretch: scale = Vector2(maxf(0.001,sx/maxf(xx,0.001)),maxf(0.001,sy/maxf(yy,0.001)))
		else: scale = Vector2.ONE * maxf(0.001,(sx+sy)/(xx+yy))
	var error := 0.0
	for i in count:
		var index := posmod(shift-i, count) if reverse and closed else count-1-i if reverse else (i+shift)%count
		error += ((source[i]*scale).rotated(angle) - target[index]).length_squared()
	return {"error":error/count,"scale":scale,"angle":angle}

# Corner correspondence survives unequal axis scaling; equal-length curve samples do not.
static func _polygon_candidates(points: Array, span: float, closed: bool) -> Array:
	if not closed: return []
	var vertices := points.slice(0, points.size()-1)
	var changed := true
	while changed and vertices.size() > 3:
		changed = false
		for i in vertices.size():
			var a: Vector2 = vertices[posmod(i-1, vertices.size())]
			var z: Vector2 = vertices[(i+1)%vertices.size()]
			if vertices[i].distance_to(Geometry2D.get_closest_point_to_segment(vertices[i],a,z)) < span*0.012:
				vertices.remove_at(i)
				changed = true
				break
	if vertices.size() > 16: return []
	var center := _mean(vertices)
	var target: Array = []
	for p in vertices: target.append(p-center)
	var result: Array = []
	for entry in entries():
		if not entry.closed or entry.points.size() != vertices.size()+1: continue
		var source_center := _mean(entry.points.slice(0,entry.points.size()-1))
		var best: Dictionary = {"error":INF}
		for mirror in [Vector2.ONE,Vector2(-1,1)]:
			var source: Array = []
			for p in entry.points.slice(0,entry.points.size()-1): source.append((p-source_center)*mirror)
			for reverse in [false,true]:
				for shift in vertices.size():
					var fit := _align_samples(source,target,shift,reverse,entry.stretch,true)
					if fit.error < best.error:
						best = fit
						best.mirror = mirror
		if sqrt(best.error)/span > 0.06: continue
		var fitted: Array = []
		for p in entry.points: fitted.append(center+((p-source_center)*best.scale*best.mirror).rotated(best.angle))
		result.append({"kind":entry.kind,"points":fitted,"penalty":-0.0005 if entry.kind=="square" else 0.001,"match_error":best.error})
	return result

static func _mean(points: Array) -> Vector2:
	var result := Vector2.ZERO
	for p in points: result += p
	return result / maxf(1,points.size())

static func _resample(points: Array, closed: bool) -> Array:
	var lengths: Array[float] = [0.0]
	for i in range(1,points.size()): lengths.append(lengths.back()+points[i-1].distance_to(points[i]))
	var result: Array = []
	var edge := 1
	for i in SAMPLE_COUNT:
		var distance: float = lengths.back()*i/(SAMPLE_COUNT if closed else SAMPLE_COUNT-1)
		while edge < lengths.size()-1 and lengths[edge] < distance: edge += 1
		var fraction: float = (distance-lengths[edge-1])/maxf(0.000001,lengths[edge]-lengths[edge-1])
		result.append(points[edge-1].lerp(points[edge],fraction))
	return result
