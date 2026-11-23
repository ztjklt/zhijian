extends RefCounted
## A saved sheet is a chain of small world-space strokes, each rooted in the
## preceding stroke. Only its ground contour participates in physics.
const GroundWash := preload("res://scripts/east_ground_wash.gd")
const Pages := preload("res://scripts/east_paper_pages.gd")
const Cubic := preload("res://scripts/medieval_ink_curve.gd")
const Ribbon := preload("res://scripts/medieval_ink_ribbon.gd")
const ORIGINAL_EDGE := Vector2(185, 13.2)
const WORLD_MARK_HEIGHT := 2.0
# Allow source rounding and the sub-centimetre deviation of the ground bake.
const WORLD_MARK_TOLERANCE := 0.012
const FOOT_TOLERANCE := 0.025
const LIMITS := {
	"segments_per_page": Pages.SIZE, "min_points": 2, "max_points": 16,
	"min_step": 0.4, "max_step": 12.0, "min_width": 4.0, "max_width": 32.0,
	"max_slope": 0.6, "min_y": -6.0, "max_y": 24.0,
	"max_strokes": 12, "max_stroke_points": 16, "max_stroke_height": 3.0,
	"max_world_stroke_height": WORLD_MARK_HEIGHT, "contact_tolerance": FOOT_TOLERANCE,
	"max_ground_samples": Cubic.MAX_GROUND_SAMPLES, "max_detail_samples": Cubic.MAX_DETAIL_SAMPLES
}
const EPSILON := 0.0002 # allow JSON/Vector2 round trips at the far end of the sheet
const DRAW_SECONDS := 2.4
const MAX_NIB_STEP := 0.32
const NIB_TOLERANCE := 0.012
const MAX_PEN_REACH := 1.8

var committed_ids := {}
var segments: Array = []
var drawings: Array = []
var pending := {}
var preview := {}
var brush_time := 0.0
var actor_driven := false
# -1 is ground. Detail strokes retain their own path and lift between marks.
var stroke_index := -1
var span_index := 0
var span_fraction := 0.0

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

static func _vector(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

static func validate_command(cmd: Variant, revision: int, edge: Vector2) -> String:
	if not Pages.usable(edge):return "此处原生笔尖已无法分辨相邻落点"
	if revision < 0:return "纸边版次无效"
	if not cmd is Dictionary or not _number(cmd.get("revision")) or float(cmd.revision) != revision:
		return "纸边已变化，请重新读边"
	if not cmd.get("name") is String or cmd.name.strip_edges().is_empty() or cmd.name.length() > 32:
		return "地形名须为 1–32 个字"
	if cmd.has("ground_material") and cmd.ground_material not in GroundWash.TYPES:return "地层材质须为 soil、stone、bank 或 paper"
	var points = cmd.get("points")
	if not points is Array or points.size() < LIMITS.min_points or points.size() > LIMITS.max_points:
		return "地表轮廓需要 2–16 个点"
	var previous := edge
	for i in points.size():
		if not _pair(points[i]):
			return "地表坐标无效"
		var point := _vector(points[i])
		if not point.is_finite() or point.y < LIMITS.min_y or point.y > LIMITS.max_y:
			return "地表高度超出纸面"
		if i == 0:
			if point.distance_to(edge) > .008:
				return "起笔处没有接上当前纸边"
			continue
		var dx := point.x - previous.x
		if dx < LIMITS.min_step - EPSILON or dx > LIMITS.max_step + EPSILON:
			return "轮廓须向东，每步 0.4–12 米"
		if absf(point.y - previous.y) > dx * LIMITS.max_slope + EPSILON:
			return "地表太陡，人物无法步行"
		previous = point
	var width := previous.x - edge.x
	if width < LIMITS.min_width - EPSILON or width > LIMITS.max_width + EPSILON:
		return "一段纸边宽度须为 4–32 米"
	if cmd.has("stroke_space") and (not cmd.stroke_space is String or cmd.stroke_space != "world"):
		return "未知的地标坐标系"
	var world_space: bool = cmd.has("stroke_space")
	var strokes = cmd.get("strokes", [])
	if not strokes is Array or strokes.size() > LIMITS.max_strokes:
		return "装饰笔画超出上限"
	for stroke in strokes:
		if not stroke is Array or stroke.size() < 2 or stroke.size() > LIMITS.max_stroke_points:
			return "每条装饰笔画需要 2–16 个点"
		for p in stroke:
			if not _pair(p) or p[0] < edge.x - EPSILON or p[0] > previous.x + EPSILON:
				return "装饰须落在本段横向纸面内"
			if world_space:
				if p[1] < LIMITS.min_y - WORLD_MARK_TOLERANCE or p[1] > LIMITS.max_y + WORLD_MARK_HEIGHT + WORLD_MARK_TOLERANCE:
					return "世界坐标高度超出纸面"
			elif p[1] < 0 or p[1] > LIMITS.max_stroke_height:
				return "装饰须落在本段地表上方 0–3 米内"
	return _validate_brushwork(cmd, edge, previous)

static func _validate_brushwork(cmd: Dictionary, edge: Vector2, end: Vector2) -> String:
	var world_space: bool = cmd.has("stroke_space")
	if cmd.has("stroke_contacts") and not world_space:
		return "世界接地点需要 world 坐标系"
	for key: String in ["style", "landmark"]:
		var max_length := 32 if key == "style" else 48
		if cmd.has(key) and (not cmd[key] is String or cmd[key].length() > max_length):
			return "笔法或地标文字过长"
	var ground_bounds := Rect2(edge.x, LIMITS.min_y, end.x - edge.x, LIMITS.max_y - LIMITS.min_y)
	var error := Cubic.validate_handles(cmd.get("terrain_handles"), cmd.points, ground_bounds, LIMITS.max_slope)
	if error != "":
		return error
	var strokes: Array = cmd.get("strokes", [])
	var handles = cmd.get("stroke_handles")
	if handles != null:
		if not handles is Array or handles.size() != strokes.size():
			return "地标控制柄须与笔画一一对应"
		var bounds := Rect2(edge.x, 0, end.x - edge.x, LIMITS.max_stroke_height)
		if world_space:
			# Controls describe shape, not pen positions. Only the actual drawn
			# curve must be reachable; a control may lie outside that envelope.
			bounds = Rect2(edge.x, LIMITS.min_y - WORLD_MARK_HEIGHT, end.x - edge.x, LIMITS.max_y - LIMITS.min_y + 3.0 * WORLD_MARK_HEIGHT)
		for i in strokes.size():
			error = Cubic.validate_handles(handles[i], strokes[i], bounds)
			if error != "":
				return error
	if cmd.has("stroke_level"):
		if not cmd.stroke_level is Array or cmd.stroke_level.size() != strokes.size():
			return "水平笔须与笔画一一对应"
		for flag in cmd.stroke_level:
			if not flag is bool:
				return "水平笔须用 true 或 false 标记"
	if cmd.has("stroke_ink"):
		if not cmd.stroke_ink is Array or cmd.stroke_ink.size() != strokes.size():
			return "墨色须与笔画一一对应"
		for weight in cmd.stroke_ink:
			if weight not in ["bold","fine","faint"]:
				return "墨色须为 bold、fine 或 faint"
	if cmd.get("terrain_handles") != null or handles != null or cmd.has("stroke_level") or world_space:
		var drawing := _drawing(cmd)
		if drawing.ink_error != "":
			return drawing.ink_error
		var contour: PackedVector2Array = drawing.contour
		if contour.size() > Cubic.MAX_GROUND_SAMPLES:
			return "地面曲线过于细密"
		for i in range(1, contour.size()):
			var delta := contour[i] - contour[i - 1]
			if delta.x <= 0 or absf(delta.y) > LIMITS.max_slope * delta.x + EPSILON:
				return "采样后的地表超出步行坡度"
		var total := 0
		for mark: PackedVector2Array in drawing.marks:
			total += mark.size()
		if total > Cubic.MAX_DETAIL_SAMPLES:
			return "地标曲线过于细密"
		if world_space:
			for mark: PackedVector2Array in drawing.marks:
				var gap := Cubic.clearance_range(mark, contour)
				if gap.x < -WORLD_MARK_TOLERANCE:
					return "世界笔迹穿入地表"
				if gap.y > WORLD_MARK_HEIGHT + WORLD_MARK_TOLERANCE:
					return "世界笔迹高过画家可触及的两米"
			return _validate_contacts(cmd, contour)
	return ""

static func _validate_contacts(cmd: Dictionary, contour: PackedVector2Array) -> String:
	var contacts = cmd.get("stroke_contacts", [])
	if not contacts is Array or contacts.size() > 16:
		return "地标接地点最多十六处"
	var strokes: Array = cmd.get("strokes", [])
	var seen := {}
	for foot in contacts:
		if not foot is Array or foot.size() != 2 or not _integer(foot[0]) or not _integer(foot[1]):
			return "接地点须指定笔画和锚点序号"
		if foot[0] < 0 or foot[0] >= strokes.size():
			return "找不到接地点的笔画"
		var stroke: Array = strokes[int(foot[0])]
		if foot[1] < 0 or foot[1] >= stroke.size():
			return "找不到接地点的锚点"
		var key := Vector2i(int(foot[0]), int(foot[1]))
		if seen.has(key):
			return "同一接地点被重复标记"
		seen[key] = true
		var at := _vector(stroke[key.y])
		if absf(at.y - Cubic.height(contour, at.x)) > FOOT_TOLERANCE:
			return "指定的地标落脚点没有贴住地面"
	return ""

static func valid_chain(value: Variant) -> bool:
	if not value is Array:
		return false
	var edge := ORIGINAL_EDGE
	var ids:={}
	for index in value.size():
		var segment = value[index]
		if validate_command(segment, index, edge) != "":
			return false
		if _vector(segment.points[0]).distance_to(edge)>EPSILON:return false
		if segment.has("work_id"):
			var id=segment.work_id
			if not id is String or id.is_empty() or ids.has(id):return false
			ids[id]=true
		if segment.has("work") and (index != value.size() - 1 or not _valid_work(segment)):
			return false
		edge = _vector(segment.points.back())
	return true

static func _integer(value: Variant) -> bool:
	return _number(value) and floorf(float(value)) == float(value)

static func _valid_work(segment: Dictionary) -> bool:
	var work = segment.work
	if not work is Dictionary or not _integer(work.get("stroke")) or not _integer(work.get("span")):
		return false
	if not _number(work.get("fraction")) or work.fraction < 0 or work.fraction >= 1:
		return false
	var drawing := _drawing(segment)
	if work.stroke < -1 or work.stroke >= drawing.marks.size():
		return false
	var path: PackedVector2Array = drawing.contour if work.stroke == -1 else drawing.marks[int(work.stroke)]
	if work.span < 0 or work.span >= path.size() - 1:
		return false
	# Numeric save fields must also resolve to a non-degenerate physics face
	# after the world coordinates are converted back to Vector2 precision.
	var span := int(work.span)
	var at := path[span].lerp(path[span + 1], float(work.fraction))
	return work.fraction == 0 or (at != path[span] and at != path[span + 1])

func observe(profile: PackedVector2Array) -> Dictionary:
	var tail: Array = []
	for i in range(maxi(0, profile.size() - 6), profile.size()):
		tail.append([profile[i].x, profile[i].y])
	var context := _previous_work(profile)
	var revision:=segments.size()
	var index:=Pages.page_of(revision)
	var limits:=LIMITS.duplicate(true)
	limits.ground_materials=GroundWash.TYPES.duplicate()
	# Older readers compare global revision to max_segments. Expose only
	# the end of the currently writable leaf, including a newly opened leaf.
	limits.max_segments=(index+1)*Pages.SIZE if Pages.usable(profile[-1]) else revision
	return {"page_index":index,"page_number":index+1,"page_offset":revision%Pages.SIZE,"can_extend":Pages.usable(profile[-1]),
		"revision": segments.size(), "edge": tail.back().duplicate(), "tail": tail, "previous_work": context,
		"previous_name": "" if segments.is_empty() else segments.back().name,
		"busy": not pending.is_empty(), "limits": limits
	}

func _previous_work(profile: PackedVector2Array) -> Dictionary:
	var saved: Dictionary = {} if segments.is_empty() else segments.back()
	var base_tangent := (profile[-1] - profile[-2]).normalized()
	var tangent := base_tangent if saved.is_empty() else Cubic.end_tangent(saved.points, saved.get("terrain_handles"))
	var slope := tangent.y / maxf(0.000001, tangent.x)
	var fallback_style := "山脊墨线" if saved.is_empty() else "曲线墨笔" if saved.has("terrain_handles") else "墨线折笔"
	var result := {"name":saved.get("name", "边境营地"), "style":saved.get("style", fallback_style),
		"landmark":saved.get("landmark", "营地东侧山脊" if saved.is_empty() else saved.name),
		"end_tangent":[tangent.x, tangent.y], "end_slope":slope,
		"surface_slope":base_tangent.y / maxf(0.000001, base_tangent.x),
		"walkable_join_slope":clampf(slope, -LIMITS.max_slope, LIMITS.max_slope),
		"stroke_count":saved.get("strokes", []).size()}
	if not saved.is_empty():
		result.height_change = saved.points.back()[1] - saved.points.front()[1]
		result.width = saved.points.back()[0] - saved.points.front()[0]
	return result

func start(cmd: Dictionary, edge: Vector2, controlled: bool = false) -> Dictionary:
	if not pending.is_empty():
		return {"ok": false, "error": "画家正在落笔"}
	var id = cmd.get("work_id")
	if id!=null and ((not id is String) or id.is_empty() or id.length()>96): return {"ok":false,"error":"作品编号无效"}
	if id!=null and committed_ids.has(id):return {"ok":false,"error":"该作品已经落笔","work_id":id,"duplicate":true}
	if cmd.get("points") is Array and not cmd.points.is_empty() and _pair(cmd.points[0]) and _vector(cmd.points[0]).distance_to(edge)<=.008:
		cmd=cmd.duplicate(true)
		cmd.points[0]=[edge.x,edge.y]
	var error := validate_command(cmd, segments.size(), edge)
	if error != "":
		return {"ok": false, "error": error}
	pending = {"revision": segments.size(), "name": cmd.name.strip_edges(), "points": cmd.points.duplicate(true)}
	if controlled and cmd.get("author_id")=="companion" and cmd.get("work_id") is String:
		pending.author_id="companion"
		pending.work_id=cmd.work_id.left(96)
		for key in ["team_id","world_id"]:
			if cmd.get(key) is String: pending[key]=cmd[key].left(96)
	pending.points[0] = [edge.x, edge.y]
	if cmd.has("ground_material"):pending.ground_material=cmd.ground_material
	if cmd.has("stroke_space"):
		pending.stroke_space = cmd.stroke_space
	for field: String in ["strokes", "terrain_handles", "stroke_handles", "stroke_ink", "stroke_level", "stroke_contacts"]:
		if cmd.get(field) is Array:
			pending[field] = cmd[field].duplicate(true)
	for field: String in ["style", "landmark"]:
		if cmd.has(field):
			pending[field] = cmd[field].strip_edges()
	preview = _drawing(pending)
	actor_driven = controlled
	stroke_index = -1
	span_index = 0
	span_fraction = 0.0
	brush_time = 0
	return {"ok": true}

func _complete() -> void:
	if pending.has("work_id"):committed_ids[pending.work_id]=true
	segments.append(pending)
	drawings.append(preview)
	pending = {}
	preview = {}
	actor_driven = false

func advance(delta: float) -> PackedVector2Array:
	if pending.is_empty() or actor_driven:
		return PackedVector2Array()
	brush_time += delta
	if brush_time < DRAW_SECONDS:
		return PackedVector2Array()
	var contour: PackedVector2Array = preview.contour
	_complete()
	return contour

func _work_path() -> PackedVector2Array:
	return preview.contour if stroke_index == -1 else preview.marks[stroke_index]

func work_target(step_m: float) -> Dictionary:
	if not actor_driven or not is_finite(step_m):
		return {}
	var path := _work_path()
	var at := path[span_index].lerp(path[span_index + 1], span_fraction)
	var nib := at.move_toward(path[span_index + 1], clampf(step_m, 0, MAX_NIB_STEP))
	return {"phase": "ground" if stroke_index == -1 else "detail", "stroke": stroke_index,
		"span": span_index, "from": at, "nib": nib}

func advance_nib(nib: Vector2, hand: Vector2, reach: float) -> Dictionary:
	if not actor_driven or not nib.is_finite() or not hand.is_finite() or not is_finite(reach) or reach <= 0:
		return {}
	var path := _work_path()
	var a := path[span_index]
	var b := path[span_index + 1]
	var from := a.lerp(b, span_fraction)
	if maxf(hand.distance_to(nib), hand.distance_to(from)) > minf(reach, MAX_PEN_REACH) + NIB_TOLERANCE:
		return {}
	if from.distance_to(nib) > MAX_NIB_STEP + NIB_TOLERANCE:
		return {}
	var next_fraction := clampf((nib - a).dot(b - a) / a.distance_squared_to(b), 0, 1)
	if next_fraction <= span_fraction:
		return {}
	var on_line := a.lerp(b, next_fraction)
	if on_line == from or nib.distance_to(on_line) > NIB_TOLERANCE:
		return {}
	if on_line.distance_to(b) <= EPSILON:
		next_fraction = 1
		on_line = b
	var update := {"ground": stroke_index == -1, "new_face": span_fraction == 0, "start": a, "tip": on_line}
	span_fraction = next_fraction
	if next_fraction >= 1:
		span_index += 1
		span_fraction = 0
		if span_index >= path.size() - 1:
			span_index = 0
			stroke_index += 1
			if stroke_index >= preview.marks.size():
				_complete()
	return update

func snapshot() -> Array:
	var saved := segments.duplicate(true)
	if not pending.is_empty():
		var segment := pending.duplicate(true)
		if actor_driven:
			segment.work = {"stroke": stroke_index, "span": span_index, "fraction": span_fraction}
		# A legacy timed stroke dries on load, an actor resumes at its real tip.
		saved.append(segment)
	return saved

func restore(saved: Array) -> void:
	pending = {}
	preview = {}
	actor_driven = false
	segments = saved.duplicate(true)
	for index in segments.size():
		var segment: Dictionary = segments[index]
		if not segment.has("work_id"):
			segment.work_id="east-history-"+str(index)+"-"+str(segment.name).sha256_text().left(16)
			segment.author_id="companion"
			segment.source="historical"
	drawings.clear()
	if not segments.is_empty() and segments.back().has("work"):
		pending = segments.pop_back()
		var work: Dictionary = pending.work
		pending.erase("work")
		preview = _drawing(pending)
		actor_driven = true
		stroke_index = int(work.stroke)
		span_index = int(work.span)
		span_fraction = float(work.fraction)
	committed_ids.clear()
	for segment in segments:
		if segment.has("work_id"):committed_ids[segment.work_id]=true
		drawings.append(_drawing(segment))

func worked_contour() -> PackedVector2Array:
	if not actor_driven:
		return PackedVector2Array()
	var contour: PackedVector2Array = preview.contour
	if stroke_index >= 0:
		return contour
	var result := contour.slice(0, span_index + 1)
	if span_fraction > 0:
		result.append(contour[span_index].lerp(contour[span_index + 1], span_fraction))
	return result

static func _drawing(segment: Dictionary) -> Dictionary:
	var contour := Cubic.bake(segment.points, segment.get("terrain_handles"))
	var marks: Array[PackedVector2Array] = []
	var weights: Array[String] = []
	var ribbon_cache: Array[Dictionary] = []
	var lengths := PackedFloat32Array()
	var strokes: Array = segment.get("strokes", [])
	var handles = segment.get("stroke_handles")
	var world_space: bool = segment.get("stroke_space") == "world"
	var expressive: bool = world_space or handles != null or segment.get("terrain_handles") != null or segment.has("stroke_ink") or segment.has("stroke_level")
	var ink_error := ""
	var projection_ground := PackedVector2Array() if world_space else contour
	for i in strokes.size():
		var line := Cubic.bake(strokes[i], null if handles == null else handles[i], projection_ground)
		if segment.has("stroke_level") and segment.stroke_level[i]:
			if world_space:
				for at in line:
					if absf(at.y - line[0].y) > 0.002:
						ink_error = "world 水平笔须使用同一世界高度"
						break
			else:
				line = _level_stroke(line, contour)
				if line.size() < 2:
					ink_error = "水平笔须有横向长度，且整笔落在可画的地面上方"
		if line.size() < 2:
			if world_space:
				ink_error = "世界坐标笔画缺少有效长度"
			continue
		marks.append(line)
		if expressive:
			var weight := "bold" if i == 0 else "fine"
			if segment.has("stroke_ink"):
				weight = segment.stroke_ink[i]
			weights.append(weight)
			ribbon_cache.append({})
			var arc_length := 0.0
			for j in range(1, line.size()):
				arc_length += line[j-1].distance_to(line[j])
			lengths.append(arc_length)
	return {"contour": contour, "material":segment.get("ground_material","soil"), "marks": marks, "weights": weights, "arc_lengths":lengths,
		"expressive":expressive, "ink_error":ink_error, "ribbon_cache":ribbon_cache}

static func _level_stroke(line: PackedVector2Array, contour: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	var level := line[0].y
	var min_x := line[0].x
	var max_x := min_x
	for p in line:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		var flat := Vector2(p.x, level)
		if result.is_empty() or result[-1].distance_to(flat) > EPSILON:
			result.append(flat)
	var lo := Cubic.height(contour, min_x)
	var hi := Cubic.height(contour, max_x)
	var highest := maxf(lo, hi)
	var lowest := minf(lo, hi)
	for knot in contour:
		if knot.x > min_x and knot.x < max_x:
			highest = maxf(highest, knot.y)
			lowest = minf(lowest, knot.y)
	if level < highest - 0.02 or level > lowest + LIMITS.max_stroke_height:
		return PackedVector2Array()
	return result

func expressive_at(x: float) -> bool:
	if x <= ORIGINAL_EDGE.x:
		return false
	if actor_driven and x >= preview.contour[0].x:
		return preview.expressive
	var i:=_drawing_at(x)
	return i>=0 and drawings[i].expressive

func _drawing_at(x:float) -> int:
	var lo:=0
	var hi:=drawings.size()
	while lo<hi:
		var mid: int=(lo+hi)/2
		if drawings[mid].contour[0].x<=x:lo=mid+1
		else:hi=mid
	return lo-1

func draw(canvas: Node2D, game, left: float, right: float, ink: Color) -> void:
	for index in range(maxi(0,_drawing_at(left)),drawings.size()):
		var drawing:Dictionary=drawings[index]
		var contour: PackedVector2Array = drawing.contour
		if contour[0].x>right:break
		if contour[-1].x >= left and contour[0].x <= right:
			_draw_marks(canvas, game, drawing.marks, INF, drawing.weights, drawing.arc_lengths, drawing.ribbon_cache)
	if preview.is_empty():
		return
	var contour: PackedVector2Array = preview.contour
	if contour[-1].x < left or contour[0].x > right:
		return
	if actor_driven:
		# Physical soil already renders the wet ground up to the held pencil.
		# Details follow pen order, including leftwards and vertical strokes.
		if stroke_index >= 0:
			_draw_worked_marks(canvas, game)
		return
	var fraction := smoothstep(0.0, 1.0, brush_time / DRAW_SECONDS)
	var tip := Vector2(lerpf(contour[0].x, contour[-1].x, fraction), 0)
	tip.y = Cubic.height(contour, tip.x)
	var screen_tip: Vector2 = game.world_to_screen(tip)
	var line := PackedVector2Array()
	for p in contour:
		if p.x >= tip.x:
			break
		line.append(game.world_to_screen(p))
	line.append(screen_tip)
	if line.size() > 1:
		canvas.draw_polyline(line, ink, 1.8, true)
	_draw_marks(canvas, game, preview.marks, tip.x, preview.weights, preview.arc_lengths, preview.ribbon_cache)
	_draw_brush(canvas, screen_tip, clampf(game.PIXELS_PER_UNIT / 60.0, 0.8, 1.5))

func _draw_worked_marks(canvas: Node2D, game) -> void:
	var done: Array = preview.marks.slice(0, stroke_index)
	var path := _work_path()
	var active := path.slice(0, span_index + 1)
	if span_fraction > 0:
		active.append(path[span_index].lerp(path[span_index + 1], span_fraction))
	done.append(active)
	_draw_marks(canvas, game, done, INF, preview.weights, preview.arc_lengths, preview.ribbon_cache)

static func _draw_marks(canvas: Node2D, game, marks: Array, limit: float, weights: Array, arc_lengths: PackedFloat32Array, cache: Array) -> void:
	var pencil := Color(0.115, 0.09, 0.065, 0.69)
	for index in marks.size():
		var mark: PackedVector2Array = marks[index]
		if not weights.is_empty() and is_inf(limit):
			Ribbon.draw(canvas, game, mark, 0, arc_lengths[index], weights[index], cache[index])
			continue
		var run := PackedVector2Array()
		var run_start := 0.0
		var travel := 0.0
		for i in range(1, mark.size()):
			var a := mark[i - 1]
			var b := mark[i]
			var along := travel
			travel += a.distance_to(b)
			if minf(a.x, b.x) >= limit:
				continue
			if a.x > limit:
				a = b.lerp(a, (limit - b.x) / (a.x - b.x))
				along += a.distance_to(mark[i - 1])
			elif b.x > limit:
				b = a.lerp(b, (limit - a.x) / (b.x - a.x))
			if weights.is_empty():
				canvas.draw_line(game.world_to_screen(a), game.world_to_screen(b), pencil, 1.45, true)
				continue
			if run.is_empty() or run[-1].distance_to(a) > EPSILON:
				if not run.is_empty():
					Ribbon.draw(canvas, game, run, run_start, arc_lengths[index], weights[index], cache[index])
				run = PackedVector2Array([a])
				run_start = along
			if run[-1].distance_to(b) > EPSILON:
				run.append(b)
		if not run.is_empty():
			Ribbon.draw(canvas, game, run, run_start, arc_lengths[index], weights[index], cache[index])

static func _draw_brush(canvas: Node2D, tip: Vector2, scale: float) -> void:
	# A small wooden drawing pencil. Its graphite point is on the actual contour.
	var shaft := Vector2(0.62, -0.785) * scale
	var half := Vector2(-shaft.y, shaft.x) * 3.2
	var root := tip + shaft * 13
	var end := tip + shaft * 48
	var outline := Color("40352c")
	var corners := PackedVector2Array([tip, root - half, end - half, end + half, root + half])
	canvas.draw_colored_polygon(corners, Color("e2bf87"))
	canvas.draw_colored_polygon(PackedVector2Array([root - half, end - half, end + half, root + half]), Color("ae7447"))
	canvas.draw_line(root - half * 0.38, end - half * 0.38, Color("e8c293"), 1.4, true)
	corners.append(tip)
	canvas.draw_polyline(corners, outline, 1.25, true)
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip + shaft * 5.3 - half * 0.4, tip + shaft * 5.3 + half * 0.4]), outline)
	canvas.draw_circle(tip, 1.7 * scale, outline, true, -1.0, true)
