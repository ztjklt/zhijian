extends RefCounted
## Local plan paths, footings and access stations all share the same bottom origin.
const Palette := preload("res://scripts/pen_palette.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const VERSION := "building-plan-v2"
const FOOT_TOLERANCE := 0.16
const STATION_TOLERANCE := 0.22
const STATION_HALF_WIDTH := 0.30
const PAIRED_SHIFT := 0.33

static func pair(value: Variant) -> bool:
	return value is Array and value.size()==2 and typeof(value[0]) in [TYPE_INT,TYPE_FLOAT] and typeof(value[1]) in [TYPE_INT,TYPE_FLOAT] and is_finite(value[0]) and is_finite(value[1])

static func point(p: Array) -> Vector2:
	return Vector2(p[0],p[1])

static func coords(p: Vector2) -> Array:
	return [p.x,p.y]

static func bag_for(game, owner: String) -> Dictionary:
	if owner=="player": return game.bag
	if owner=="companion" and game.medieval_world!=null: return game.medieval_world.companion_blueprints
	return {}

static func valid_layout(layout: Variant, count: int) -> bool:
	if not layout is Dictionary: return false
	for field in ["supports","access"]:
		var points = layout.get(field)
		if not points is Array or points.is_empty() or points.size()>24: return false
		for p in points:
			if not pair(p) or maxf(absf(p[0]),absf(p[1]))>24: return false
	if layout.has("footprint") and (not pair(layout.footprint) or layout.footprint[0]>layout.footprint[1] or absf(layout.footprint[0])>24 or absf(layout.footprint[1])>24): return false
	var stations = layout.get("stations",[])
	if not stations is Array or stations.size()>24: return false
	for station in stations:
		if not station is Dictionary: return false
		if station.has("service"):
			if not preload("res://scripts/architecture/stall_goods.gd").is_counter(station) or typeof(station.get("x")) not in [TYPE_INT,TYPE_FLOAT]: return false
			if not layout.access.any(func(p): return absf(p[0]-station.x)<.001): return false
	if layout.has("stroke_sources"):
		var sources = layout.stroke_sources
		if not sources is Array or sources.size()!=count: return false
		for source in sources:
			if source == null: continue
			if not source is Dictionary or source.size()!=2: return false
			var work = source.get("source_work_id")
			var index = source.get("source_stroke")
			if not work is String or work.is_empty() or work.length()>120: return false
			if typeof(index) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(index) or index!=floor(index) or index<0 or index>=8192: return false
	var layers = layout.get("layers")
	if not layers is Array or layers.size()!=count: return false
	for name in layers:
		if not name is String or name.is_empty() or name.length()>48: return false
	return true

static func _source(game, owner: String, id: int) -> Dictionary:
	var bag := bag_for(game,owner)
	if bag.is_empty(): return {}
	var entry := BlueprintBag.find_entry(bag,id)
	return entry if entry.has("layout") else {}

static func list_plans(game, owner: String) -> Array:
	var plans := []
	for entry in bag_for(game,owner).get("entries",[]):
		if entry.has("layout"):
			plans.append({"id":int(entry.id),"name":entry.name,"strokes":entry.paths.size(),"parent_id":int(entry.get("parent_id",-1))})
	return plans

static func prepare_scenery(name: String, cmd: Dictionary, origin: Vector2) -> Dictionary:
	var strokes = cmd.get("strokes")
	if not origin.is_finite() or name.strip_edges().is_empty() or name.length()>64 or cmd.get("tool")!="draw_scenery" or cmd.get("style","ink") not in ["ink","pencil"]:
		return {"error":"建筑图纸缺少名称、定位点或景物笔"}
	if not strokes is Array or strokes.is_empty() or strokes.size()>128:
		return {"error":"请选择 1 至 128 笔景物笔迹"}
	if not Brush.valid_treatments(cmd,strokes.size()): return {"error":"每笔的墨色处理须与景物笔触相符"}
	for field in ["brushes","pigments"]:
		if cmd.has(field) and (not cmd[field] is Array or cmd[field].size()!=strokes.size()): return {"error":"笔触与图纸笔数不符"}
	var paths := []
	var total := 0
	for i in strokes.size():
		var stroke = strokes[i]
		if not stroke is Array or stroke.size()<2: return {"error":"建筑笔画过短"}
		total += stroke.size()
		if total>DrawingRules.MAX_POINTS: return {"error":"建筑图纸采样过多"}
		var brush = cmd.brushes[i] if cmd.has("brushes") else "bold"
		var pigment = cmd.pigments[i] if cmd.has("pigments") else "inherit"
		if not Brush.BRUSHES.has(brush) or not Palette.valid(pigment): return {"error":"建筑笔触或颜料不在色板内"}
		var points := []
		var length := 0.0
		for p in stroke:
			if not pair(p): return {"error":"建筑笔画坐标无效"}
			var relative := point(p)-origin
			if relative.length()>24: return {"error":"建筑笔画过远"}
			if not points.is_empty(): length += relative.distance_to(points.back())
			points.append(relative)
		if length < Brush.MIN_LENGTH or (Brush.is_wash(brush) and Brush.wash_polygon(PackedVector2Array(points)).is_empty()): return {"error":"建筑笔画太短或铺色未闭合"}
		var path := {"points":points,"collision":false,"brush":brush}
		if pigment!="inherit": path.pigment=pigment
		if cmd.has("ink_treatments") and cmd.ink_treatments[i] != "": path.ink_treatment = cmd.ink_treatments[i]
		paths.append(path)
	return {"name":name.strip_edges(),"source":"own","kind":"freehand","pen":"draw_scenery","ink_style":cmd.get("style","ink"),"paths":paths,"dynamic":false}

static func prepare(name: String, cmd: Dictionary, origin: Vector2, layout: Dictionary) -> Dictionary:
	var design := prepare_scenery(name,cmd,origin)
	if design.has("error"): return design
	if not valid_layout(layout,design.paths.size()): return {"error":"图纸需要逐笔图层、支点和门前或摊前使用位置"}
	var saved_layout := layout.duplicate(true)
	var bounds := ShapeMatcher.bounds(design.paths)
	saved_layout.footprint=[bounds.min_x,bounds.max_x]
	design.layout=saved_layout
	return design

static func store(game, owner: String, name: String, cmd: Dictionary, origin: Vector2, layout: Dictionary, parent_id := -1) -> Dictionary:
	var bag := bag_for(game,owner)
	if bag.is_empty() or (parent_id>=0 and _source(game,owner,parent_id).is_empty()): return {"ok":false,"error":"找不到本人的原图纸"}
	var design := prepare(name,cmd,origin,layout)
	if design.has("error"): return {"ok":false,"error":design.error}
	return collect(bag,design,parent_id)

static func collect(bag: Dictionary, design: Dictionary, parent_id := -1) -> Dictionary:
	var added := BlueprintBag.add_entry(bag,design)
	if added.entry.is_empty(): return {"ok":false,"error":added.error}
	var entry: Dictionary = added.entry
	entry.name=design.name
	entry.layout=design.layout.duplicate(true)
	if parent_id>=0: entry.parent_id=parent_id
	return {"ok":true,"id":int(entry.id)}

static func command_at(game, owner: String, id: int, origin: Vector2) -> Dictionary:
	var entry := _source(game,owner,id)
	if entry.is_empty() or not origin.is_finite(): return {}
	var strokes := []
	var brushes := []
	var pigments := []
	for path in entry.paths:
		var pts := []
		for p: Vector2 in path.points: pts.append(coords(origin+p))
		strokes.append(pts)
		brushes.append(path.get("brush","bold"))
		pigments.append(path.get("pigment","inherit"))
	var command := {"tool":"draw_scenery","name":entry.name,"style":entry.ink_style,"strokes":strokes,"brushes":brushes,"pigments":pigments,
		"plan":{"owner":owner,"id":id,"origin":coords(origin),"layout":entry.layout.duplicate(true)}}
	Brush.add_treatments(command,entry.paths)
	return command

static func preview(game, owner: String, id: int, origin: Vector2, within_draw_range := false) -> Dictionary:
	var entry := _source(game,owner,id)
	if entry.is_empty(): return {"ok":false,"error":"本人的建筑图纸不存在","conflicts":[],"alternatives":[]}
	var reachable := Callable()
	if within_draw_range:
		reachable = func(at: Vector2) -> bool:
			for path in entry.paths:
				for p: Vector2 in path.points:
					var target := p+at
					if target.distance_squared_to(game.player.position)>DrawingRules.BUILD_RANGE*DrawingRules.BUILD_RANGE: return false
			return true
	return preview_layout(game,entry.layout,origin,"",reachable)

static func _intervals(layout: Dictionary, origin: Vector2) -> Array:
	var left := INF
	var right := -INF
	var height := 0.0
	for p in layout.supports:
		left = minf(left,p[0]); right = maxf(right,p[0]); height+=float(p[1])
	if layout.has("footprint"):
		left=minf(left,layout.footprint[0])
		right=maxf(right,layout.footprint[1])
	var intervals := [{"x":origin.x+(left+right)*0.5,"width":maxf(0.28,right-left),"y":origin.y+height/layout.supports.size(),"reason":"footprint"}]
	for p in layout.access:
		var at := point(p)
		var width := 0.8 + (2.0*PAIRED_SHIFT if paired_station(layout,at.x) else 0.0)
		intervals.append({"x":origin.x+at.x,"width":width,"y":origin.y+at.y,"reason":"access"})
	return intervals

## The marked terrain profile and bridge decks are the same faces that build physics.
## A free-standing elevated foundation must be a fixed, drawn terrain or platform.
static func _load_bearing(game, at: Vector2, tolerance: float) -> bool:
	var world = game.medieval_world
	if world.paper_space==null:
		if at.x>=world.terrain.profile[0].x and at.x<=world.east_walk_limit() and absf(at.y-world.travel_height(at.x))<=tolerance: return true
	else:
		for surface in world.paper_surfaces(at.x,at.y-tolerance,at.y+tolerance):
			if surface.face=="floor" and not world.paper_space.solid_at(Vector2(at.x,surface.y+.04)): return true
	var up := Vector2(0,tolerance)
	var query := PhysicsRayQueryParameters2D.create(at+up,at-up,1)
	var hit := {}
	var space: PhysicsDirectSpaceState2D = game.get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	while true:
		hit = space.intersect_ray(query)
		if hit.is_empty(): return false
		var body = hit.collider
		if body is BuildObject and not body.data.get("dynamic",true) and (body.data.get("pen")=="draw_terrain" or body.data.get("kind") in ["platform","ramp"]):
			return hit.normal.y>=0.70
		exclude.append(hit.rid)
		query.exclude=exclude
	return false

static func paired_station(layout: Dictionary, x: float) -> bool:
	var stations = layout.get("stations",[])
	return stations is Array and stations.any(func(s): return s is Dictionary and int(s.get("workers",1))==2 and absf(float(s.get("x",INF))-x)<0.001)

static func _can_stand(game, at: Vector2) -> bool:
	for dx: float in [-STATION_HALF_WIDTH,0.0,STATION_HALF_WIDTH]:
		if not _load_bearing(game,at+Vector2(dx,0),STATION_TOLERANCE): return false
	return preload("res://scripts/companion_senses.gd").clear_circle(game,at+Vector2(0,0.40),0.27,9)

static func _conflicts(game, layout: Dictionary, origin: Vector2, built: Array, ignore_key := "", first_only := false) -> Array:
	var world = game.medieval_world
	var conflicts := []
	var seen := {}
	for i in layout.supports.size():
		var at := origin+point(layout.supports[i])
		if not _load_bearing(game,at,FOOT_TOLERANCE):
			conflicts.append({"id":"柱脚%d" % (i+1),"kind":"ground","reason":"unsupported","x":at.x,"y":at.y})
			if first_only: return conflicts
	for i in layout.access.size():
		var at := origin+point(layout.access[i])
		var clear := _can_stand(game,at)
		if paired_station(layout,float(layout.access[i][0])):
			clear = clear and _can_stand(game,at-Vector2(PAIRED_SHIFT,0)) and _can_stand(game,at+Vector2(PAIRED_SHIFT,0))
		if not clear:
			conflicts.append({"id":"使用位%d" % (i+1),"kind":"ground","reason":"unwalkable","x":at.x,"y":at.y})
			if first_only: return conflicts
	for interval in _intervals(layout,origin):
		for hit in interval_occupants(world,interval,built,ignore_key,first_only):
			if first_only: return [hit]
			var key := str(hit.id)+"/"+str(hit.reason)
			if not seen.has(key): seen[key]=true; conflicts.append(hit)
	return conflicts

## The same protected footprint and access lanes used for surveying and the final build.
static func interval_occupants(world, interval: Dictionary, built: Array, ignore_key := "", first_only := false) -> Array:
	var hits: Array = world.architecture_site(interval.x,interval.width,.12,interval.y).conflicts
	if first_only and not hits.is_empty(): return [hits[0]]
	var lane_height:=INF
	for other in built:
		if other.id == ignore_key or absf(interval.x-other.x) > (interval.width+other.width)*.5+.12: continue
		if lane_height==INF: lane_height=world.travel_height(interval.x)
		if absf((interval.y-lane_height)-(other.y-world.travel_height(other.x))) > 1: continue
		if first_only: return [other]
		hits.append(other)
	return hits

static func _built(game) -> Array:
	var built := []
	for obj in game.objects:
		var key: String = obj.get("structure_id","")
		if obj.has("built_plan"):
			var meta: Dictionary = obj.built_plan
			var origin: Vector2 = game.object_point(obj,point(meta.offset))
			for interval in _intervals(meta.layout,origin):
				interval.id=key
				interval.kind="building_plan"
				built.append(interval)
		elif obj.get("pen")=="draw_object" or (obj.get("role")=="building" and obj.get("pen")!="draw_terrain" and (obj.get("dynamic",true) or obj.get("kind") not in ["platform","ramp"])):
			var rect: Rect2 = game.object_bounds(obj)
			built.append({"id":key,"kind":"object","reason":"footprint","x":rect.get_center().x,"y":rect.position.y,"width":rect.size.x})
	return built

static func preview_layout(game, layout: Dictionary, origin: Vector2, ignore_key := "", reachable := Callable()) -> Dictionary:
	if game.medieval_world==null or not origin.is_finite():
		return {"ok":false,"error":"请在单人沙盒选择建筑落点","conflicts":[],"alternatives":[]}
	var layers=layout.get("layers")
	if not layers is Array or not valid_layout(layout,layers.size()):
		return {"ok":false,"error":"图纸缺少可用的支点、使用位或图层","conflicts":[],"alternatives":[]}
	var built := _built(game)
	var conflicts := _conflicts(game,layout,origin,built,ignore_key)
	if reachable.is_valid() and not reachable.call(origin):
		conflicts.append({"kind":"range","id":"图纸","reason":"range","x":origin.x,"y":origin.y})
	var result := {"ok":conflicts.is_empty(),"origin":coords(origin),"conflicts":conflicts,"alternatives":[]}
	if conflicts.is_empty(): return result
	var road: float = game.ground_height_at(origin.x)
	var level := origin.y-road
	# Unsupported aim points should suggest standable earth, not translate their gap.
	if conflicts.any(func(c): return c.reason in ["unsupported","unwalkable"]): level=0
	for step in range(0,25):
		for sign_x in ([1] if step==0 else [-1,1]):
			var x: float = origin.x+step*0.5*sign_x
			var candidate := Vector2(x,game.ground_height_at(x)+level)
			if candidate.distance_to(origin)<.02: continue
			if not _conflicts(game,layout,candidate,built,ignore_key,true).is_empty(): continue
			if result.alternatives.any(func(p): return absf(p[0]-x)<1.5): continue
			if reachable.is_valid() and not reachable.call(candidate): continue
			result.alternatives.append(coords(candidate))
			if result.alternatives.size()==2: break
		if result.alternatives.size()==2: break
	result.error=notice(result)
	return result

static func notice(result: Dictionary) -> String:
	var hit: Dictionary = result.conflicts[0]
	var reason: String = {"access":"挡住使用位置","footprint":"占地重叠","unsupported":"支点未落地","unwalkable":"使用位无法站立","range":"超过落笔距离"}.get(hit.reason,"此处被占")
	var options := PackedStringArray()
	for p in result.alternatives: options.append("%.1f 米" % p[0])
	return reason+" · "+str(hit.id)+(" · 可选 "+"/".join(options) if not options.is_empty() else " · 请另选落点")

## Final validation is repeated after any walking or animated brushwork.
static func inspect_command(game, cmd: Dictionary, artist: String) -> Dictionary:
	var meta = cmd.get("plan")
	var owner := "companion" if artist=="painter" else "player"
	if not meta is Dictionary or not pair(meta.get("origin")) or cmd.get("tool")!="draw_scenery":
		return {"error":"建筑图纸的落点无效"}
	var origin := point(meta.origin)
	var id: int = int(meta.get("id",-1))
	var design: Dictionary
	if id >= 0:
		if meta.get("owner") != owner: return {"error":"这张建筑图纸不在本人的背包"}
		design = _source(game,owner,id)
		if design.is_empty(): return {"error":"找不到所选的建筑图纸"}
		var original := command_at(game,owner,id,origin)
		for key in ["strokes","brushes","pigments","style","ink_treatments"]:
			if cmd.get(key) != original.get(key): return {"error":"图纸已经变动，请先另存改稿"}
	else:
		if not meta.get("layout") is Dictionary: return {"error":"建筑图纸缺少落地资料"}
		design = prepare(cmd.get("name","建筑"),cmd,origin,meta.layout)
		if design.has("error"): return design
		if bag_for(game,owner).entries.size()>=BlueprintBag.MAX_ENTRIES: return {"error":"本人的图纸包已满"}
	var site := preview_layout(game,design.layout,origin)
	if not site.ok: return site
	return {"ok":true,"id":id,"owner":owner,"origin":origin,"design":design}
