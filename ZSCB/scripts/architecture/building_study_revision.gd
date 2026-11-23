extends RefCounted
## Replace selected old slots in original draw order; the first selected slot holds
## the new component. Every other slot and its source stays in its original order.
const Study := preload("res://scripts/atlas_study.gd")
const Plans := preload("res://scripts/architecture/building_plans.gd")
const MAX_EDIT := 8

static func expand(game, rows: Array, layers: Array, read_sheet: Callable) -> Dictionary:
	var slots := {}
	var count := 0
	for row in rows:
		if not row is Dictionary:return {"error":"请选择已有笔号。"}
		var ids = row.get("indices") if row.has("reference") else [row.get("index",layers.find(row.get("layer")) if layers.count(row.get("layer"))==1 else -1)]
		if not ids is Array or ids.is_empty() or ids.size()>MAX_EDIT:return {"error":"请选择1至8笔原层。"}
		var targets := []
		for id in ids:
			if typeof(id) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(id) or floor(id)!=id or id<0 or id>=layers.size() or slots.has(int(id)):
				return {"error":"原笔号不存在、重复或图层重名，请用唯一原笔号。"}
			targets.append(int(id))
			slots[int(id)]=[]
		targets.sort()
		var first:int=targets[0]
		if row.has("reference"):
			if row.size()!=2 or not row.reference is Dictionary:return {"error":"组笔需要 indices 和 reference。"}
			var r:Dictionary=row.reference
			for k in r:
				if k not in ["study","part","strokes","origin","scale","mirror_x","pigment","layer","team_id","world_id"]:return {"error":"未识别的组笔字段。"}
			if r.has("strokes")==r.has("part") or not r.get("study") is String or not r.get("layer") is String or r.layer.strip_edges().is_empty():return {"error":"请给组笔命名并选定原页笔号或部件。"}
			var ref:={"team_id":r.get("team_id",game.team_slot.team_id),"world_id":r.get("world_id",game.team_slot.world_id),"work_id":r.study}
			var sheet:Dictionary=read_sheet.call(game,ref)
			if not sheet.get("ok",false):return {"error":sheet.error}
			if sheet.entry.format not in ["reference","plan","drawing"] or sheet.recipe.get("strokes",[]).is_empty():return {"error":"所选页没有可用原墨迹。"}
			var selected=r.get("strokes")
			if r.has("part"):
				var part:=Study.read_part(sheet,str(r.part))
				if part.ok:
					selected=part.strokes.map(func(item):return item.stroke)
				else:
					selected=[]
					for i in sheet.recipe.strokes.size():
						if sheet.recipe.strokes[i].layer==r.part:selected.append(i)
					if selected.is_empty():return {"error":part.error}
			if not selected is Array or selected.is_empty() or selected.size()>MAX_EDIT:return {"error":"单次新笔最多8笔，请少选几笔。"}
			selected=selected.duplicate()
			var colors:={}
			for id in selected:
				if typeof(id) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(id) or floor(id)!=id or id<0 or id>=sheet.recipe.strokes.size():return {"error":"原页没有该笔号。"}
				if r.get("pigment","source")!="source":colors[str(int(id))]=r.pigment
			selected.sort()
			var build:=Study.compose(sheet,{"strokes":selected,"origin":r.get("origin"),"scale":r.get("scale",[1,1]),"mirror_x":r.get("mirror_x",false),"pigments":colors,"batch_id":"建筑局部取笔"})
			if not build.ok:return {"error":build.error}
			for ink in build.strokes:
				var old:Dictionary=sheet.recipe.strokes[ink.source_stroke]
				var name:String=r.layer.strip_edges()+"·"+old.layer+"#"+str(ink.source_stroke)
				if name.length()>32:return {"error":"展开的笔层名超过32字，请缩短组名。"}
				var line:={"layer":name,"brush":old.brush,"pigment":ink.pigment,"points":ink.points,"source":{"source_work_id":ref.work_id,"source_stroke":ink.source_stroke}}
				if old.has("ink_treatment"):line.ink_treatment=old.ink_treatment
				slots[first].append(line)
		else:
			var line:Dictionary=row.duplicate(true)
			line.layer=layers[first]
			line.erase("source")
			slots[first].append(line)
		count+=slots[first].size()
		if count>MAX_EDIT or slots.size()>MAX_EDIT:return {"error":"局部改绘每次最多取代8笔、落8笔。"}
	if slots.is_empty():return {"error":"请选择需要改绘的笔。"}
	return {"slots":slots,"count":count}

static func protected(layout:Dictionary,index:int,points:Array,offset:Vector2=Vector2.ZERO) -> bool:
	var layer:String=layout.layers[index]
	for station:Dictionary in layout.get("stations",[]):
		if layer in station.get("roof_layers",[]) or layer in station.get("fixture_layers",[]):return true
	for support:Array in layout.supports:
		var foot:=offset+Plans.point(support)
		for i in range(1,points.size()):
			var a:Vector2=points[i-1] if points[i-1] is Vector2 else Plans.point(points[i-1])
			var b:Vector2=points[i] if points[i] is Vector2 else Plans.point(points[i])
			if foot.distance_to(Geometry2D.get_closest_point_to_segment(foot,a,b))<.035:return true
	return false

static func cuts_access(layout:Dictionary,points:Array) -> bool:
	for access:Array in layout.access:
		var use:=Plans.point(access)
		var half:=.73 if Plans.paired_station(layout,use.x) else .40
		var lane:=Rect2(use+Vector2(-half,.06),Vector2(2*half,1.44))
		var corners:=[lane.position,Vector2(lane.end.x,lane.position.y),lane.end,Vector2(lane.position.x,lane.end.y)]
		for i in points.size():
			var at:=Plans.point(points[i])
			if lane.has_point(at):return true
			if i==0:continue
			for k in corners.size():
				if Geometry2D.segment_intersects_segment(Plans.point(points[i-1]),at,corners[k],corners[(k+1)%4])!=null:return true
	return false

static func replace_slots(old:Array,slots:Dictionary,field:String="") -> Array:
	var result:=[]
	for i in old.size():
		if slots.has(i):
			for line in slots[i]:result.append(line if field.is_empty() else line.get(field))
		else:result.append(old[i])
	return result
