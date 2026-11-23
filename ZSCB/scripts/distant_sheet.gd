extends RefCounted
## A scene on a small drawing sheet and its nonphysical impression in the world.
const Palette := preload("res://scripts/pen_palette.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const MAX_CENTER_DISTANCE := 16.0
const MAX_STROKES := 128

static func pair(value: Variant) -> Vector2:
	if not value is Array or value.size()!=2: return Vector2.INF
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return Vector2.INF
	return Vector2(value[0],value[1])

static func valid_size(size: Vector2) -> bool:
	return size.is_finite() and size.x>=1.0 and size.x<=20.0 and size.y>=0.2 and size.y<=10.0

## Closed mountain washes fade toward the bottom of their own sheet.
static func mist_color(pigment: Color, height_fraction: float) -> Color:
	return Color(pigment, 0.22 * clampf(height_fraction, 0.0, 1.0))

## Render the original sheet in the atlas and in the placement preview.
## The UV origin is the lower left corner of the paper.
static func preview(canvas: CanvasItem, rect: Rect2, strokes: Array, highlight: int = -1) -> void:
	for i in strokes.size():
		var stroke: Dictionary = strokes[i]
		var path := PackedVector2Array()
		var colors := PackedColorArray()
		var pigment := Palette.resolve(stroke.get("pigment","inherit"), Color("544f49"))
		for uv in stroke.points:
			path.append(rect.position + Vector2(uv[0], 1.0-uv[1])*rect.size)
			if stroke.brush=="mist":colors.append(mist_color(pigment,uv[1]))
		if (Brush.is_wash(stroke.brush) or stroke.brush=="mist") and path.size()>2:
			if path[0].is_equal_approx(path[-1]):
				path.resize(path.size()-1)
				if not colors.is_empty():colors.resize(path.size())
			if Geometry2D.triangulate_polygon(path).is_empty():continue
			if colors.is_empty():canvas.draw_colored_polygon(path,Color(pigment,.20))
			else:canvas.draw_polygon(path,colors)
		elif path.size()>=2:
			canvas.draw_polyline(path,Color(pigment,.45),1.65 if stroke.brush=="bold" else 1.0,true)
		if i==highlight and path.size()>=2:canvas.draw_polyline(path,Color(.15,.44,.5,.65),1.5,true)

static func valid_mark(record: Dictionary) -> bool:
	if not record.has("projection"): return not record.has("sheet_moves")
	var page=record.projection
	if not page is Dictionary or page.get("version")!=1 or not page.get("id") is String or page.id.is_empty() or page.id.length()>128: return false
	if record.get("mode") not in ["scenery","backdrop"] or record.has("service") or not record.get("anchor") is Dictionary or record.anchor.get("kind")!="free": return false
	if page.has("wash_effect") and (page.wash_effect!="mist" or record.mode!="backdrop"): return false
	var count=page.get("count")
	var index=page.get("index")
	if not (count is float or count is int) or not (index is float or index is int): return false
	if int(count)!=count or int(index)!=index or count<1 or count>MAX_STROKES or index<0 or index>=count: return false
	if record.get("work_id")!=page.id+"-"+str(int(index)):return false
	var origin:=pair(page.get("origin"))
	var size:=pair(page.get("size"))
	var points=record.get("points")
	if not origin.is_finite() or not valid_size(size) or not points is Array or not page.get("uv") is Array or page.uv.size()!=points.size(): return false
	for i in points.size():
		var uv:=pair(page.uv[i])
		if not uv.is_finite() or uv.x<0 or uv.x>1 or uv.y<0 or uv.y>1: return false
		var world:=pair(points[i])
		if not world.is_finite() or world.distance_to(origin+uv*size)>0.0002: return false
	return not points.is_empty() and pair(record.anchor.get("at")).is_equal_approx(pair(points[0])) and valid_moves(record)

static func prepare(game, author: String, spec: Dictionary) -> Dictionary:
	if author not in ["companion","player"] or not is_instance_valid(game) or game.medieval_world==null or game.network_session!=null:
		return {"ok":false,"error":"请在本队单人世界中展开远景纸。"}
	var id=spec.get("sheet_id")
	var title=spec.get("name")
	if not id is String or id.strip_edges().is_empty() or id.length()>100 or not title is String or title.strip_edges().is_empty() or title.length()>56:
		return {"ok":false,"error":"远景纸需要本次原稿编号和画名。"}
	var origin:=pair(spec.get("origin"))
	var size:=pair(spec.get("size"))
	if not origin.is_finite() or not valid_size(size):
		return {"ok":false,"error":"请选宽 1–20 米、高 0.2–10 米的画幅。"}
	var ink=spec.get("strokes")
	if not ink is Array or ink.is_empty() or ink.size()>MAX_STROKES:
		return {"ok":false,"error":"一张远景纸容纳 1–128 笔。"}
	var foot:Vector2=game.player.position
	var hand:=foot+Vector2(0,0.35)
	if author=="companion":
		var painter=game.medieval_world.get_node_or_null("SandboxCompanion")
		if painter==null or painter.actor==null: return {"ok":false,"error":"画家尚未入场。"}
		foot=painter.actor.player.position
		hand=painter.actor.hand_world()
	if foot.distance_to(origin+size*0.5)>MAX_CENTER_DISTANCE:
		return {"ok":false,"error":"请走到画幅中心 16 米内再展开远景纸。"}
	var paper_size:=size*minf(0.94/size.x,0.64/size.y)
	var miniature:=Rect2(hand+Vector2(0.08,-paper_size.y*0.45),paper_size)
	var scope:Dictionary=game.team_slot
	var group:="vista-"+JSON.stringify([scope.team_id,scope.world_id,author,id]).sha256_text().left(24)
	var records: Array=[]
	var hand_lines: Array=[]
	var sources:Dictionary={}
	for i in ink.size():
		var stroke=ink[i]
		if not stroke is Dictionary or not stroke.get("brush") is String or not Palette.valid(stroke.get("pigment","inherit")):
			return {"ok":false,"error":"第 %d 笔需要浓线、细线或淡面和有效颜料。" % (i+1)}
		var wash:bool=Brush.is_wash(stroke.brush) or stroke.brush=="mist"
		if not wash and stroke.brush not in ["fine","bold"]:
			return {"ok":false,"error":"第 %d 笔需要浓线、细线或淡面和有效颜料。" % (i+1)}
		for field in stroke:
			if field not in ["points","brush","pigment","source_work_id","source_stroke"]:
				return {"ok":false,"error":"远景纸只接受线形、颜料和原稿来源。"}
		var source=stroke.get("points")
		if not source is Array or source.size()<2 or source.size()>256: return {"ok":false,"error":"每笔需要 2–256 个纸上坐标。"}
		var data:={"version":1,"id":group,"index":i,"count":ink.size(),"origin":spec.origin.duplicate(),"size":spec.size.duplicate(),"uv":[]}
		var record:={"projection":data,"work_id":group+"-"+str(i),"world_id":scope.world_id,"team_id":scope.team_id,"author_id":author,"name":title,"points":[],"pigment":stroke.get("pigment","inherit")}
		if stroke.brush=="mist": data.wash_effect="mist"
		record.mode="backdrop" if wash else "scenery"
		if not wash:record.brush=stroke.brush
		if stroke.has("source_work_id") or stroke.has("source_stroke"):
			var source_id=stroke.get("source_work_id")
			var index=stroke.get("source_stroke")
			if not source_id is String or source_id.is_empty() or not (index is int or index is float) or int(index)!=index:
				return {"ok":false,"error":"请给出本队图页编号与取用的原笔号。"}
			if not sources.has(source_id):
				var original:Dictionary=load("res://scripts/team_atlas.gd").read_sheet(game,{"team_id":scope.team_id,"world_id":scope.world_id,"work_id":source_id})
				if not original.ok:return original
				sources[source_id]=original.recipe.get("strokes",[]).size()
			if index<0 or index>=sources[source_id]:return {"ok":false,"error":"第 %d 笔引用的原笔号在这张图页上不存在。" % (i+1)}
			record.source_work_id=source_id
			record.source_stroke=int(index)
		var line: Array=[]
		for p in source:
			var uv:=pair(p)
			if not uv.is_finite() or uv.x<0 or uv.x>1 or uv.y<0 or uv.y>1:
				return {"ok":false,"error":"第 %d 笔越出原纸，请在 0–1 之间落笔。" % (i+1)}
			var at:=origin+size*uv
			if not record.points.is_empty() and at.distance_to(pair(record.points[-1]))<=0.0001:continue
			var tip:=miniature.position+miniature.size*uv
			data.uv.append(p.duplicate())
			record.points.append([at.x,at.y])
			line.append([tip.x,tip.y])
		if wash and record.points.size()>1 and pair(record.points[0]).distance_to(pair(record.points[-1]))<=0.0001:
			record.points.pop_back();data.uv.pop_back();line.pop_back()
		if record.points.size()<(3 if wash else 2):return {"ok":false,"error":"第 %d 笔缺少可见的轮廓。" % (i+1)}
		record.anchor={"kind":"free","at":record.points[0].duplicate()}
		if wash:line.append(line.front())
		records.append(record)
		hand_lines.append(line)
	return {"ok":true,"records":records,"hand_lines":hand_lines,"paper_rect":miniature,"work_id":group}

static func _author_foot(game, author: String) -> Vector2:
	if author == "player":
		return game.player.position
	if author == "companion":
		var painter = game.medieval_world.get_node_or_null("SandboxCompanion")
		if painter != null and painter.actor != null:
			return painter.actor.player.position
	return Vector2.INF

static func frames(game, author: String) -> Array:
	var pages: Array = []
	if not is_instance_valid(game) or game.network_session != null or game.medieval_world == null:
		return pages
	var space = game.medieval_world.paper_space
	if space == null or space.sheet_count == 0:
		return pages
	var foot := _author_foot(game, author)
	for mark in space.works:
		if mark.author_id != author or not mark.has("projection") or mark.projection.index != 0:
			continue
		var page: Dictionary = mark.projection
		var wash_strokes: Array = []
		for i in int(page.count):
			var line: Dictionary = space.entries.get(page.id + "-" + str(i), {}).get("record", {})
			if line.get("mode") == "backdrop":
				wash_strokes.append({"index":i, "brush":line.projection.get("wash_effect", "wash"), "pigment":line.get("pigment","inherit")})
		var center := pair(page.origin) + pair(page.size) * 0.5
		pages.append({"team_id":game.team_slot.team_id, "world_id":game.team_slot.world_id,
			"work_id":page.id, "name":mark.get("name", "远景纸"), "author_id":author,
			"origin":page.origin.duplicate(), "size":page.size.duplicate(),
			"wash_strokes":wash_strokes, "revision":mark.get("sheet_moves", []).size(), "in_range":foot.distance_to(center) <= MAX_CENTER_DISTANCE})
	return pages

static func valid_moves(record: Dictionary) -> bool:
	if not record.has("sheet_moves"):
		return true
	var history = record.sheet_moves
	if not history is Array or history.is_empty() or record.get("projection", {}).get("index", -1) != 0:
		return false
	var ids := {}
	var previous: Dictionary = {}
	var brushes := {}
	for i in history.size():
		var move = history[i]
		if not move is Dictionary or not move.get("request_id") is String or move.request_id.is_empty() or move.request_id.length() > 128 or ids.has(move.request_id):
			return false
		if move.get("revision") != i + 1 or move.get("work_id") != record.projection.id or move.get("author_id") != record.get("author_id"):
			return false
		if not pair(move.get("from_origin")).is_finite() or not valid_size(pair(move.get("from_size"))) or not pair(move.get("origin")).is_finite() or not valid_size(pair(move.get("size"))):
			return false
		if i > 0 and (move.from_origin != previous.origin or move.from_size != previous.size):
			return false
		if move.get("kind","move") == "wash":
			if move.origin != move.from_origin or move.size != move.from_size or not _valid_wash_receipt(move, int(record.projection.count), brushes):
				return false
		elif move.get("kind","move") != "move":
			return false
		ids[move.request_id] = true
		previous = move
	return previous.origin == record.projection.origin and previous.size == record.projection.size

## Move an existing author's complete nonphysical sheet. Original UV, work IDs,
## ordering and provenance stay on the actual strokes. The first carries the history.
static func reframe(game, author: String, spec: Dictionary, commit := true) -> Dictionary:
	if not is_instance_valid(game) or game.network_session != null or game.medieval_world == null or author not in ["player", "companion"]:
		return {"ok":false, "error":"请在本队单人世界中调整远景。"}
	if spec.get("team_id") != game.team_slot.get("team_id") or spec.get("world_id") != game.team_slot.get("world_id"):
		return {"ok":false, "error":"这张远景图页来自另一份世界。"}
	var id = spec.get("work_id")
	var request = spec.get("request_id")
	var expected = spec.get("expected_revision")
	var origin := pair(spec.get("origin"))
	var size := pair(spec.get("size"))
	if not id is String or not request is String or request.strip_edges().is_empty() or request.length() > 128 or not (expected is int or expected is float) or expected < 0 or expected != floor(expected):
		return {"ok":false, "error":"请从原图页取得作品编号、改位编号和当前版本。"}
	if not origin.is_finite() or not valid_size(size):
		return {"ok":false, "error":"请选宽 1–20 米、高 0.2–10 米的画幅。"}
	var space = game.medieval_world.paper_space
	var first: Dictionary = space.entries.get(id + "-0", {}).get("record", {}) if space != null else {}
	if first.get("projection", {}).get("id") != id or first.get("author_id") != author:
		return {"ok":false, "error":"作者只能调整自己已落在本世界的远景原作。"}
	var base: Dictionary = first.projection
	var total := 0
	for mark in space.works:
		if mark.get("projection", {}).get("id") == id:
			total += 1
	if total != int(base.count):
		return {"ok":false, "error":"原作总笔数与图页不符。"}
	var history: Array = first.get("sheet_moves", [])
	for receipt in history:
		if receipt.request_id == request:
			if receipt.get("kind","move") != "move" or receipt.revision != expected + 1 or pair(receipt.origin) != origin or pair(receipt.size) != size:
				return {"ok":false, "error":"这张改位收据已用于另一条指令。"}
			return {"ok":true, "work_id":id, "revision":history.size(), "receipt":receipt.duplicate(true), "replayed":true}
	if expected != history.size():
		return {"ok":false, "error":"画幅已经改过，请重读图页再决定位置。"}
	if origin == pair(base.origin) and size == pair(base.size):
		return {"ok":false, "error":"新画幅与原画幅相同。"}
	var foot := _author_foot(game, author)
	if foot.distance_to(pair(base.origin) + pair(base.size)*0.5) > MAX_CENTER_DISTANCE or foot.distance_to(origin + size*0.5) > MAX_CENTER_DISTANCE:
		return {"ok":false, "error":"请走到原画幅和新画幅中心各 16 米以内。"}
	var new_origin: Array = base.origin.duplicate() if origin == pair(base.origin) else spec.origin.duplicate()
	var new_size: Array = base.size.duplicate() if size == pair(base.size) else spec.size.duplicate()
	var receipt := {"work_id":id, "request_id":request, "revision":history.size()+1, "author_id":author,
		"from_origin":base.origin.duplicate(), "from_size":base.size.duplicate(), "origin":new_origin, "size":new_size}
	var records: Array = []
	for i in int(base.count):
		var source: Dictionary = space.entries.get(id + "-" + str(i), {}).get("record", {})
		var page: Dictionary = source.get("projection", {})
		if page.get("id") != id or page.get("index") != i or page.get("count") != base.count or page.get("origin") != base.origin or page.get("size") != base.size or source.get("author_id") != author or source.team_id != first.team_id or source.world_id != first.world_id:
			return {"ok":false, "error":"原作的笔号、画幅或署名不完整。"}
		var mark := source.duplicate(true)
		mark.projection.origin = new_origin
		mark.projection.size = new_size
		mark.points = []
		for uv in page.uv:
			var p := origin + pair(uv) * size
			mark.points.append([p.x, p.y])
		mark.anchor.at = mark.points[0].duplicate()
		mark.erase("chunk_id")
		if i == 0:
			mark.sheet_moves = history.duplicate(true)
			mark.sheet_moves.append(receipt)
		var normalized: Dictionary = space.normalized(mark)
		if normalized.is_empty() or not valid_mark(normalized):
			return {"ok":false, "error":"这个尺度下第 %d 笔无法保留原轮廓。" % (i+1)}
		records.append(normalized)
	if commit:
		space.replace_projection(records)
	return {"ok":true, "work_id":id, "revision":receipt.revision, "receipt":receipt.duplicate(true), "replayed":false}

## The public pen numbers are zero based. Order does not change an edit's identity.
static func _wash_choices(edits: Variant, count: int) -> Dictionary:
	var choices := {}
	if not edits is Array or edits.is_empty() or edits.size() > count:
		return choices
	for edit in edits:
		if not edit is Dictionary or edit.size() != 2 or edit.get("brush") not in ["wash", "mist"]:
			return {}
		var index = edit.get("index")
		if not (index is int or index is float) or not is_finite(index) or index != floor(index) or index < 0 or index >= count or choices.has(int(index)):
			return {}
		choices[int(index)] = edit.brush
	return choices

static func _valid_wash_receipt(receipt: Dictionary, count: int, brushes: Dictionary) -> bool:
	var choices := _wash_choices(receipt.get("edits"), count)
	var changes = receipt.get("changes")
	var cost = receipt.get("ink_cost")
	if choices.is_empty() or not changes is Array or changes.is_empty() or not (cost is int or cost is float) or not is_finite(cost) or cost != floor(cost) or cost < 6*changes.size() or cost > 80*changes.size():
		return false
	var changed := {}
	for change in changes:
		if not change is Dictionary or not change.has("index") or not (change.index is int or change.index is float) or change.index != floor(change.index):
			return false
		var i := int(change.index)
		if changed.has(i) or not choices.has(i) or change.get("brush") != choices[i] or change.get("from") not in ["wash","mist"] or change.from == change.brush:
			return false
		if brushes.get(i, change.from) != change.from:
			return false
		changed[i] = true
	for i in choices:
		if not changed.has(i) and brushes.get(i, choices[i]) != choices[i]:
			return false
		brushes[i] = choices[i]
	return true

static func revise_washes(game, author: String, spec: Dictionary, commit := true) -> Dictionary:
	if not is_instance_valid(game) or game.network_session != null or game.medieval_world == null or author not in ["player","companion"]:
		return {"ok":false, "error":"请在本队单人世界打开原纸。"}
	if spec.get("team_id") != game.team_slot.get("team_id") or spec.get("world_id") != game.team_slot.get("world_id"):
		return {"ok":false, "error":"这张原纸属于另一份世界。"}
	var id = spec.get("work_id")
	var request = spec.get("request_id")
	var expected = spec.get("expected_revision")
	if not id is String or not request is String or request.strip_edges().is_empty() or request.length() > 128 or not (expected is int or expected is float) or not is_finite(expected) or expected < 0 or expected != floor(expected):
		return {"ok":false, "error":"请重读原纸编号和版本再改笔。"}
	var space = game.medieval_world.paper_space
	var first: Dictionary = space.entries.get(id + "-0", {}).get("record", {}) if space != null else {}
	var page: Dictionary = first.get("projection", {})
	if page.get("id") != id or first.get("author_id") != author:
		return {"ok":false, "error":"作者只能改自己在本世界留下的原纸。"}
	var choices := _wash_choices(spec.get("edits"), int(page.count))
	if choices.is_empty():
		return {"ok":false, "error":"请为每个原笔号选择一种洗法，每笔只选一次。"}
	var history: Array = first.get("sheet_moves", [])
	for receipt in history:
		if receipt.request_id == request:
			if receipt.get("kind") != "wash" or receipt.revision != expected + 1 or _wash_choices(receipt.edits, int(page.count)) != choices:
				return {"ok":false, "error":"这一编号已经用于另一条改稿指令。"}
			return {"ok":true, "work_id":id, "revision":history.size(), "ink_spent":0, "ink_cost":0, "receipt":receipt.duplicate(true), "replayed":true}
	if expected != history.size():
		return {"ok":false, "error":"原纸已经改过，请重读当前版本。"}
	if _author_foot(game,author).distance_to(pair(page.origin) + pair(page.size)*0.5) > MAX_CENTER_DISTANCE:
		return {"ok":false, "error":"请走到原画幅中心 16 米以内。"}
	var edits: Array = []
	var changes: Array = []
	var records: Array = []
	var cost := 0.0
	for i in int(page.count):
		var mark: Dictionary = space.entries.get(id+"-"+str(i), {}).get("record", {})
		var member: Dictionary = mark.get("projection", {})
		if member.get("id") != id or member.get("index") != i or member.get("count") != page.count or member.get("origin") != page.origin or member.get("size") != page.size or mark.get("author_id") != author or mark.team_id != first.team_id or mark.world_id != first.world_id:
			return {"ok":false, "error":"原纸的笔号、画幅或署名不齐。"}
		var updated := mark.duplicate(true) if i == 0 or choices.has(i) else {}
		if choices.has(i):
			if mark.mode != "backdrop":
				return {"ok":false, "error":"第 %d 笔是轮廓线，请选原纸上的色面。" % (i+1)}
			var previous: String = member.get("wash_effect", "wash")
			edits.append({"index":i, "brush":choices[i]})
			if previous != choices[i]:
				var length := 0.0
				for j in range(1,mark.points.size()):
					length += pair(mark.points[j-1]).distance_to(pair(mark.points[j]))
				cost += DrawingRules.paper_ink_cost(length)
				changes.append({"index":i, "from":previous, "brush":choices[i]})
				if choices[i] == "mist":
					updated.projection.wash_effect = "mist"
				else:
					updated.projection.erase("wash_effect")
		if not updated.is_empty():
			records.append(updated)
	if changes.is_empty():
		return {"ok":false, "error":"所选笔已经采用这种洗法。"}
	var reservoir = game.ink if author == "player" else game.medieval_world.get_node("SandboxCompanion").actor.ink
	if not reservoir.can_spend(cost):
		return {"ok":false, "error":"这些笔需要 %d 墨，作者墨量不足。" % int(cost)}
	var receipt := {"kind":"wash", "work_id":id, "author_id":author, "request_id":request, "revision":history.size()+1,
		"from_origin":page.origin.duplicate(), "origin":page.origin.duplicate(), "from_size":page.size.duplicate(),
		"size":page.size.duplicate(), "edits":edits, "changes":changes, "ink_cost":cost}
	records[0].sheet_moves = history.duplicate(true)
	records[0].sheet_moves.append(receipt)
	if commit:
		space.replace_projection(records)
		reservoir.spend(cost)
	return {"ok":true, "work_id":id, "revision":receipt.revision, "ink_cost":cost, "ink_spent":cost if commit else 0, "receipt":receipt.duplicate(true), "replayed":false}
