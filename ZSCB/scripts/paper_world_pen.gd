extends RefCounted
## Shared authoring boundary. The world owns validated geometry, collision and replay.
const MODES := {"platform":"承重浮台","rock":"实岩","carve":"挖空","backdrop":"洞背墙","scenery":"远景线稿","water":"水域"}
const ANCHORS := {"free":"自由放置","ground":"地表支点","wall":"岩壁支点","hanging":"上方吊点"}

static func point(value: Variant) -> Vector2:
	if not value is Array or value.size()!=2: return Vector2.INF
	for n in value:
		if not (n is int or n is float) or not is_finite(float(n)): return Vector2.INF
	return Vector2(value[0],value[1])

const SNAP_RANGE := 0.35
const CONTACT_EPSILON := 0.0001

static func within_anchor_reach(first: Vector2, requested: Vector2) -> bool:
	return first.is_finite() and requested.is_finite() and first.distance_to(requested)<=SNAP_RANGE+CONTACT_EPSILON

static func resolve_anchor(game, anchor: Dictionary) -> Vector2:
	var pos := point(anchor.get("at"))
	if not pos.is_finite() or not ANCHORS.has(anchor.get("kind")): return Vector2.INF
	if anchor.kind=="free": return pos
	var best := Vector2.INF
	if anchor.kind in ["ground","hanging"]:
		var face := "floor" if anchor.kind=="ground" else "ceiling"
		for surface in game.medieval_world.paper_surfaces(pos.x,pos.y-SNAP_RANGE-CONTACT_EPSILON,pos.y+SNAP_RANGE+CONTACT_EPSILON):
			var candidate := Vector2(pos.x,surface.y)
			if surface.face==face and (not best.is_finite() or candidate.distance_to(pos)<best.distance_to(pos)): best=candidate
	var axis := Vector2.RIGHT if anchor.kind=="wall" else Vector2.DOWN
	var space: PhysicsDirectSpaceState2D=game.get_world_2d().direct_space_state
	for side in [-1,1]:
		var ray:=PhysicsRayQueryParameters2D.create(pos+axis*(SNAP_RANGE+.001)*side,pos-axis*(SNAP_RANGE+.001)*side,1)
		var hit:=space.intersect_ray(ray)
		if hit.is_empty(): continue
		if hit.collider is BuildObject and hit.collider.data.get("dynamic",true) and hit.collider.data.get("anchor",{}).get("kind","free")=="free": continue
		var normal:Vector2=hit.normal
		var accepted:bool=absf(normal.x)>.65 if anchor.kind=="wall" else normal.y>.6 if anchor.kind=="ground" else normal.y<-.6
		var at:Vector2=hit.position
		if accepted and within_anchor_reach(at,pos) and (not best.is_finite() or at.distance_to(pos)+.0001<best.distance_to(pos)): best=at
	return best

static func should_align(mode: String) -> bool:
	return mode not in ["carve","water"]

static func preview_offset(game, first: Vector2) -> Vector2:
	if game.pen_anchor_kind=="free" or (game.draw_mode==8 and (game.paper_pen_mode=="legacy" or not should_align(game.paper_pen_mode))): return Vector2.ZERO
	if not game.draft.is_empty() and game.draw_mode!=8:
		if game.draft[0].has("sheet"): return Vector2.ZERO
		first=game.draft[0].points[0]
	var at:=resolve_anchor(game,{"kind":game.pen_anchor_kind,"at":[first.x,first.y]})
	return at-first if at.is_finite() else Vector2.ZERO

static func _signature(mode: String, kind: String, at: Array, points: Array, service: Variant = null) -> String:
	var numbers: Array=[]
	for pair in points:
		if not point(pair).is_finite(): return ""
		numbers.append([float(pair[0]),float(pair[1])])
	var parts: Array=[mode,kind,[float(at[0]),float(at[1])],numbers]
	if service!=null:
		if not service is Dictionary or service.get("kind")!="fruit_market" or not point(service.get("at")).is_finite(): return ""
		parts.append(["fruit_market",float(service.at[0]),float(service.at[1])])
	return JSON.stringify(parts).sha256_text()

static func valid_appearance(stroke: Dictionary) -> bool:
	if not preload("res://scripts/distant_sheet.gd").valid_mark(stroke): return false
	if stroke.get("ink_treatment") == "soil_repair":
		if stroke.get("mode") != "rock" or stroke.has("projection") or not stroke.has("source_work_id"): return false
	elif stroke.has("ink_treatment"):
		if stroke.has("projection") or stroke.get("mode") not in ["backdrop","scenery"]: return false
		if stroke.ink_treatment not in ["body","reserve"] or (stroke.ink_treatment=="reserve" and stroke.mode!="backdrop"): return false
	if stroke.has("pigment") and (stroke.get("mode") not in ["backdrop","scenery"] or not preload("res://scripts/pen_palette.gd").valid(stroke.pigment)):return false
	if stroke.has("brush") and (stroke.get("mode")!="scenery" or stroke.brush not in ["bold","fine"]):return false
	if stroke.has("source_stroke"):
		var id=stroke.source_stroke
		if not stroke.has("source_work_id") or not (id is int or id is float) or int(id)!=id or id<0:return false
	return not stroke.has("source_work_id") or (stroke.source_work_id is String and not stroke.source_work_id.is_empty() and stroke.source_work_id.length()<=128)

static func from_draft(draft: Array, mode: String, kind: String) -> Array:
	var records := []
	for stroke in draft:
		var points := []
		for at: Vector2 in stroke.points: points.append([at.x,at.y])
		if points.is_empty(): continue
		if not stroke.has("paper_work_id"): stroke.paper_work_id = "stroke-"+Crypto.new().generate_random_bytes(12).hex_encode()
		var record := {"work_id":stroke.paper_work_id,"mode":mode,"points":points,"anchor":{"kind":kind,"at":points[0]}}
		if mode in ["scenery","backdrop"] and stroke.has("pigment"):record.pigment=stroke.pigment
		if stroke.has("ink_treatment") and (mode in ["scenery","backdrop"] or mode=="rock" and stroke.ink_treatment=="soil_repair"):
			record.ink_treatment=stroke.ink_treatment
		if mode=="scenery" and (stroke.has("brush") or not stroke.has("source_work_id")):
			record.brush="bold" if stroke.get("brush","bold")=="bold" else "fine"
		if stroke.has("source_work_id"):
			record.source_work_id=stroke.source_work_id
			if stroke.has("paper_name"): record.name=stroke.paper_name
			if stroke.has("paper_anchor_at"):record.anchor.at=stroke.paper_anchor_at
			if stroke.has("service"):record.service=stroke.service
		records.append(record)
	return records

## The first submission may be delivered again after moving the original sheet.
static func _same_projection(space, previous: Dictionary, stroke: Dictionary) -> bool:
	if not previous.has("projection") and not stroke.has("projection"): return true
	if not previous.has("projection") or not stroke.has("projection"): return false
	var page: Dictionary = previous.projection.duplicate()
	var first: Dictionary = space.entries.get(page.id + "-0", {}).get("record", {})
	var moves: Array = first.get("sheet_moves", [])
	if moves.is_empty(): return page == stroke.projection
	page.origin = moves[0].from_origin
	page.size = moves[0].from_size
	for receipt in moves:
		for change in receipt.get("changes", []):
			if int(change.index) == int(page.index):
				if change.from == "mist": page.wash_effect = "mist"
				else: page.erase("wash_effect")
				return page == stroke.projection
	return page == stroke.projection

static func submit(game, strokes: Array, author: String, commit := true) -> Dictionary:
	var world = game.medieval_world
	if world==null or game.network_session!=null or not world.has_method("apply_paper_plan"): return {"ok":false,"error":"当前地图没有可绘制的区块。"}
	if strokes.is_empty() or strokes.size()>128 or author not in ["player","companion"]: return {"ok":false,"error":"本轮笔划或作者无效。"}
	var body = game.player
	var reservoir = game.ink
	if author=="companion":
		var painter = world.get_node_or_null("SandboxCompanion")
		if painter==null or painter.actor==null: return {"ok":false,"error":"画家尚未入场。"}
		body = painter.actor.player
		reservoir = painter.actor.ink
	var prepared := []
	for stroke in strokes:
		if not stroke is Dictionary or not MODES.has(stroke.get("mode")) or not stroke.get("work_id") is String or stroke.work_id.is_empty() or stroke.work_id.length()>96: return {"ok":false,"error":"笔划缺少有效作品标识或模式。"}
		if not stroke.get("anchor") is Dictionary or not stroke.get("points") is Array or stroke.points.size()<2 or stroke.points.size()>256: return {"ok":false,"error":"每笔需声明支点，点数应在 2–256 之间。"}
		for field in ["team_id","world_id","author_id"]:
			var expected: String = author if field=="author_id" else game.team_slot[field]
			if stroke.has(field) and stroke[field]!=expected: return {"ok":false,"error":"这份笔稿属于另一位作者或另一个世界。"}
		var anchor: Dictionary=stroke.anchor
		if not ANCHORS.has(anchor.get("kind")) or not point(anchor.get("at")).is_finite():return {"ok":false,"error":"支点无效。"}
		var at := point(anchor.at)
		var first := point(stroke.points[0])
		if not first.is_finite() or (anchor.kind!="free" and not within_anchor_reach(first,at)): return {"ok":false,"error":"请从声明的支点起笔。"}
		if not valid_appearance(stroke):return {"ok":false,"error":"景线使用浓线或细线，色面使用本队公共色板。"}
		var previous:Dictionary=world.paper_space.entries.get(stroke.work_id,{}).get("record",{})
		var points:Array=stroke.points.duplicate(true)
		var signature:=_signature(stroke.mode,anchor.kind,anchor.at,points,stroke.get("service"))
		if signature.is_empty(): return {"ok":false,"error":"无效的落笔点。"}
		if not previous.is_empty():
			if not _same_projection(world.paper_space, previous, stroke):
				return {"ok":false,"error":"同一作品编号的原纸与画幅不同。"}
			for field in ["pigment","brush","source_work_id","source_stroke","ink_treatment"]:
				if previous.get(field)!=stroke.get(field):return {"ok":false,"error":"同一作品编号的笔触、颜料或母稿不同。"}
			var canonical:=_signature(previous.mode,previous.anchor.kind,previous.anchor.at,previous.points,previous.get("service"))
			if (signature==canonical or signature==previous.get("placement_signature","")) and previous.author_id==author and previous.team_id==game.team_slot.team_id and previous.world_id==game.team_slot.world_id and str(previous.get("name",""))==str(stroke.get("name","")):
				prepared.append(previous)
				continue
			return {"ok":false,"error":"作品编号已经对应另一笔。"}
		var hit:=resolve_anchor(game,anchor)
		if not hit.is_finite(): return {"ok":false,"error":"支点附近没有可接触的对应表面。"}
		var record:Dictionary={"work_id":stroke.work_id,"mode":stroke.mode,"author_id":author,"team_id":game.team_slot.team_id,"world_id":game.team_slot.world_id}
		if stroke.has("name"):record.name=str(stroke.name).left(56)
		for field in ["pigment","brush","source_work_id","source_stroke","projection","ink_treatment"]:
			if stroke.has(field):record[field]=stroke[field]
		record.placement_signature=signature
		if anchor.kind!="free":
			if should_align(stroke.mode):
				var offset:=hit-first
				for n in points.size():
					if not point(points[n]).is_finite(): return {"ok":false,"error":"无效的落笔点。"}
					points[n]=[float(points[n][0])+offset.x,float(points[n][1])+offset.y]
				points[0]=[hit.x,hit.y]
		if stroke.has("service"):
			var station:=point(stroke.service.at)
			if anchor.kind!="free" and should_align(stroke.mode): station+=hit-first
			record.service={"kind":"fruit_market","at":[station.x,station.y]}
		var cell: Vector2i = world.paper_cell_at(hit)
		record.merge({"points":points,"anchor":{"kind":anchor.kind,"at":anchor.at.duplicate() if anchor.kind=="free" else [hit.x,hit.y]},"chunk_id":"%d,%d"%[cell.x,cell.y]})
		prepared.append(record)
	var trial: Dictionary = world.apply_paper_plan(prepared,false)
	if not trial.ok: return trial
	var cost := 0.0
	for i in prepared.size():
		if not trial.results[i].changed: continue
		var line: Dictionary = prepared[i]
		var projected:bool=line.has("projection")
		if projected:
			var frame_center:=point(line.projection.origin)+0.5*point(line.projection.size)
			if frame_center.distance_to(body.position)>preload("res://scripts/distant_sheet.gd").MAX_CENTER_DISTANCE:
				return {"ok":false,"error":"请走到画幅中心 16 米内落笔。"}
		if not projected and point(line.anchor.at).distance_to(body.position)>DrawingRules.BUILD_RANGE: return {"ok":false,"error":"首点与所选支点未接触，或作者离支点太远。"}
		var previous := point(line.points[0])
		var length := 0.0
		for pair in line.points:
			var at := point(pair)
			if not at.is_finite() or (not projected and at.distance_to(body.position)>DrawingRules.BUILD_RANGE): return {"ok":false,"error":"请走到笔划 12 米内再落笔。"}
			length += previous.distance_to(at)
			previous = at
		cost += DrawingRules.paper_ink_cost(length)
	if not reservoir.can_spend(cost): return {"ok":false,"error":"作者墨量不足，草稿保留。"}
	if not commit:
		trial.ink_cost=cost
		return trial
	var result: Dictionary = world.apply_paper_plan(prepared,true)
	if result.ok and cost>0: reservoir.spend(cost)
	if result.ok: result.ink_spent = cost
	return result
