extends RefCounted
## Read-only size and placement of a project's committed marks on the normal field view.
## The paper renderer and this observation use the same surviving water polygons.

const Space := preload("res://scripts/paper_space.gd")
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const Market := preload("res://scripts/architecture/market_sites.gd")
const NORMAL_PX_PER_M := 60.0
const MAX_RECENT_WORKS := 12

static func _pair(p: Vector2) -> Array:
	return [snappedf(p.x,.01),snappedf(p.y,.01)]

static func _bounds(id: String, kind: String, box: Rect2, feet: Vector2) -> Dictionary:
	return {"work_id":id,"kind":kind,"center_m":_pair(box.get_center()),"size_m":_pair(box.size),
		"normal_px":[roundi(box.size.x*NORMAL_PX_PER_M),roundi(box.size.y*NORMAL_PX_PER_M)],
		"relative_to_feet_m":_pair(box.get_center()-feet)}

static func _water(entry: Dictionary, feet: Vector2) -> Dictionary:
	var id: String = entry.record.work_id
	if entry.parts.is_empty():
		return {"work_id":id,"kind":"water","normal_px":[0,0],"surface_line_px":0,"painted_area_m2":0.0}
	var origin := Space.origin_for(entry.frame)
	var bounds := Rect2(origin+entry.parts[0][0],Vector2.ZERO)
	var area := 0.0
	for part: PackedVector2Array in entry.parts:
		for p in part:
			bounds = bounds.expand(origin+p)
		for i in range(2,part.size()):
			area += absf((part[i-1]-part[0]).cross(part[i]-part[0]))*.5
	var spans: Array[Vector2] = []
	for line in entry.lines:
		spans.append(Vector2(minf(line[0].x,line[1].x),maxf(line[0].x,line[1].x)))
	spans.sort_custom(func(a,b): return a.x < b.x)
	var longest := 0.0
	var connected := Vector2(INF,-INF)
	for span in spans:
		if span.x > connected.y + .001:
			connected = span
		else:
			connected.y = maxf(connected.y,span.y)
		longest = maxf(longest,connected.y-connected.x)
	var row := _bounds(id,"water",bounds,feet)
	row.surface_line_px = roundi(longest*NORMAL_PX_PER_M)
	row.painted_area_m2 = snappedf(area,.001)
	return row

static func measure(game, project: Dictionary, feet: Vector2) -> Dictionary:
	var team: Dictionary = game.team_slot
	var scope: Dictionary = project.get("scope",{})
	for key in ["team_id","world_id"]:
		if not scope.is_empty() and team.get(key,"") != scope.get(key,""):
			return {}
	var ids: Array = project.get("work_ids",[]).slice(-MAX_RECENT_WORKS)
	var subject: String = project.get("subject","")
	if not subject.is_empty() and not ids.has(subject):
		ids.push_front(subject)
	var rows := {}
	var world = game.medieval_world
	if world == null or not feet.is_finite(): return {}
	var space = world.paper_space
	for id in ids:
		if space == null or not space.entries.has(id): continue
		var entry: Dictionary = space.entries[id]
		var kind: String = entry.record.mode
		if kind == "water":
			rows[id] = _water(entry,feet)
		else:
			rows[id] = _bounds(id,kind,entry.box,feet)
	for object: Dictionary in game.objects:
		var id: String = object.get("work_id","")
		if not ids.has(id) or object.get("paths",[]).is_empty(): continue
		var kind := "building" if object.has("built_plan") else "drawing"
		var row := _bounds(id,kind,game.object_bounds(object),feet)
		row.strokes = object.paths.size()
		row.washes = object.paths.filter(func(path): return Brush.is_wash(path.get("brush","bold"))).size()
		rows[id] = row
	var ink = world.terrain.east_ink
	if ids.any(func(id): return ink.committed_ids.has(id)):
		for i in ink.segments.size():
			var id: String = ink.segments[i].get("work_id","")
			if not ids.has(id): continue
			var profile: PackedVector2Array = ink.drawings[i].contour
			var box := Rect2(profile[0],Vector2.ZERO)
			for p in profile: box = box.expand(p)
			rows[id] = _bounds(id,"ground_contour",box,feet)
	var marks := []
	for id in ids:
		if rows.has(id): marks.append(rows[id])
	return {"normal_frame_px":[1280,720],"pixels_per_m":NORMAL_PX_PER_M,"marks":marks,
		"spatial_relations":_relations(game,project,feet) if not scope.is_empty() or team.is_empty() else {}}

# The water renderer clips both fill and rim against later ground cuts and fills.
# Join adjacent fragments of one horizontal rim so a triangle seam is not reported as a bank.
static func _visible_rims(entry: Dictionary) -> Array:
	if entry.parts.is_empty(): return []
	var origin := Space.origin_for(entry.frame)
	var pieces: Array[Rect2] = []
	for line in entry.lines:
		var a: Vector2 = origin + line[0]
		var b: Vector2 = origin + line[1]
		pieces.append(Rect2(Vector2(minf(a.x,b.x),a.y),Vector2(absf(b.x-a.x),0)))
	pieces.sort_custom(func(a,b): return a.position.x < b.position.x)
	var result: Array = []
	for piece in pieces:
		if not result.is_empty() and piece.position.x <= result.back().end.x + 0.0001:
			result[-1] = result.back().merge(piece)
		elif piece.size.x > 0.0001:
			result.append(piece)
	return result

static func _feature(id:String, kind:String, at:Vector2, box:Rect2) -> Dictionary:
	return {"work_id":id,"kind":kind,"at":at,"box":box}

static func _usable_stations(game, ids:Dictionary) -> Array:
	var result := []
	for obj:Dictionary in game.objects:
		var id:String = obj.get("work_id","")
		if not ids.has(id) or not obj.has("built_plan") or obj.get("hp",1)<=0: continue
		var meta:Dictionary = obj.built_plan
		for station:Dictionary in meta.layout.get("stations",[]):
			for access in meta.layout.get("access",[]):
				if absf(access[0]-station.x)>.001: continue
				var at:Vector2 = game.object_point(obj,Vector2(meta.offset[0]+access[0],meta.offset[1]+access[1]))
				var kind := "use_place"
				if Market.Goods.is_counter(station):
					var hit := Market.counter_at(game,at+Vector2(0,.4))
					if hit.get("station") != obj.get("structure_id") or (hit.has("slot") and meta.layout.stations[int(hit.slot)].x!=station.x): continue
					kind = "counter"
				elif not Market._at_counter(game.medieval_world,at+Vector2(0,.4),at) or not Plans._load_bearing(game,at,.16):
					continue
				var row:=_feature(id,kind,at,game.object_bounds(obj))
				row.use=station.get("use","")
				result.append(row)
	return result

# Use the drawn segment which actually carries the sampled foot. Rock edges
# have already been clipped. A partially buried platform is conservatively
# represented by the confirmed point when its neighbouring floor is absent.
static func _support_feature(world,entry:Dictionary,at:Vector2) -> Dictionary:
	var origin:=Space.origin_for(entry.frame)
	var edges:Array=entry.lines
	if entry.record.mode=="platform":
		edges=[]
		for i in range(1,entry.path.size()):edges.append([entry.path[i-1],entry.path[i]])
	for edge in edges:
		var a:Vector2=origin+edge[0]
		var b:Vector2=origin+edge[1]
		if a.distance_squared_to(b)<.000001 or Geometry2D.get_closest_point_to_segment(at,a,b).distance_squared_to(at)>.000025:continue
		if entry.record.mode=="platform" and (world.paper_space.solid_at(a+Vector2(0,.04)) or world.paper_space.solid_at(b+Vector2(0,.04))):continue
		var part:=_feature(entry.record.work_id,"support_segment",at,Rect2(a,Vector2.ZERO).expand(b))
		part.ends=[_pair(a),_pair(b)]
		return part
	return _feature(entry.record.work_id,"support_point",at,Rect2(at,Vector2.ZERO))

static func _local_support(world, entries:Array, near:Vector2) -> Dictionary:
	var chosen := {}
	var distance := INF
	# Reject erased rock and buried one-way platforms. At each tested x the
	# current floor query returns the actual face and its work ID.
	for entry:Dictionary in entries:
		var box:Rect2=entry.box
		if entry.record.mode=="rock" and entry.parts.is_empty():continue
		for x:float in [clampf(near.x,box.position.x,box.end.x),box.get_center().x,lerpf(box.position.x,box.end.x,.1),lerpf(box.position.x,box.end.x,.9)]:
			for floor_hit:Dictionary in world.paper_surfaces(x,box.position.y-.02,box.end.y+.02):
				if floor_hit.face!="floor" or floor_hit.work_id!=entry.record.work_id: continue
				var at:=Vector2(x,floor_hit.y)
				if world.paper_space.solid_at(at+Vector2(0,.05)) or at.distance_squared_to(near)>=distance: continue
				distance=at.distance_squared_to(near)
				chosen=_support_feature(world,entry,at)
	return chosen

static func _public_feature(f:Dictionary) -> Dictionary:
	if f.is_empty(): return {}
	var entry := {"work_id":f.work_id,"kind":f.kind,"at_m":_pair(f.at)}
	if f.has("use"): entry.use=f.use
	if f.has("ends"):entry.ends_m=f.ends
	if f.kind=="water_rim": entry.ends_m=[_pair(f.box.position),_pair(f.box.end)]
	return entry

static func _frame_box(at:Vector2, viewport:Vector2, ppu:float) -> Rect2:
	# The follow camera places the actor centre (.29 m above its feet) at 66% of screen height.
	var size:=viewport/ppu
	return Rect2(at+Vector2(-size.x*.5,.29-size.y*.34),size)

static func _coverage(box:Rect2, frame:Rect2) -> float:
	var overlap:=Vector2(maxf(0,minf(box.end.x,frame.end.x)-maxf(box.position.x,frame.position.x)),
		maxf(0,minf(box.end.y,frame.end.y)-maxf(box.position.y,frame.position.y)))
	var x:=overlap.x/box.size.x if box.size.x>.00001 else float(box.position.x>=frame.position.x and box.position.x<=frame.end.x)
	var y:=overlap.y/box.size.y if box.size.y>.00001 else float(box.position.y>=frame.position.y and box.position.y<=frame.end.y)
	return x*y

static func _frame_items(parts:Array,frame:Rect2) -> Array:
	var items:=[]
	for part:Dictionary in parts:
		var fraction:=_coverage(part.box,frame)
		items.append({"work_id":part.work_id,"in_frame":"full" if fraction>=.9999 else "partial" if fraction>0 else "outside"})
	return items

static func _best_view(world, feet:Vector2, parts:Array, viewport:Vector2, ppu:float) -> Dictionary:
	var union:Rect2=parts[0].box
	for part:Dictionary in parts: union=union.merge(part.box)
	var middle:=union.get_center()
	var xs:Array=[middle.x,middle.x-.6,middle.x+.6,middle.x-1.8,middle.x+1.8,feet.x]
	for part:Dictionary in parts: xs.append(part.at.x)
	var placements := []
	var candidates := {}
	for x:float in xs:
		for hit in world.paper_surfaces(x,union.position.y-3.5,union.end.y+2):
			if hit.face!="floor": continue
			var at:=Vector2(x,hit.y)
			if candidates.has(at) or world.paper_space.solid_at(at+Vector2(0,.12)):continue
			candidates[at]=true
			var frame:=_frame_box(at,viewport,ppu)
			var minimum:=1.0
			var total:=0.0
			for part:Dictionary in parts:
				var fraction:=_coverage(part.box,frame)
				minimum=minf(minimum,fraction)
				total+=fraction
			placements.append({"at":at,"support":hit.work_id,"min":minimum,"sum":total,"centre_error":absf(x-middle.x)})
	placements.sort_custom(func(a,b):
		if not is_equal_approx(a.min,b.min):return a.min>b.min
		if not is_equal_approx(a.sum,b.sum):return a.sum>b.sum
		if not is_equal_approx(a.centre_error,b.centre_error):return a.centre_error<b.centre_error
		return a.at.distance_squared_to(feet)<b.at.distance_squared_to(feet))
	for choice:Dictionary in placements:
		var route:Dictionary=world.paper_nav_route(feet,choice.at)
		if not route.get("ok",false): continue
		var goal:=Vector2(route.goal[0],route.goal[1])
		if goal.distance_to(choice.at)>.065:continue
		var frame:=_frame_box(goal,viewport,ppu)
		return {"feet_m":_pair(goal),"support_work_id":choice.support,"items":_frame_items(parts,frame)}
	return {}

static func _relations(game,project:Dictionary,feet:Vector2) -> Dictionary:
	var ids:={}
	for id in project.get("work_ids",[]): ids[id]=true
	var subject:String=project.get("subject","")
	if not subject.is_empty():ids[subject]=true
	var world=game.medieval_world
	if world.paper_space==null:return {}
	var stations:=_usable_stations(game,ids)
	var rims:=[]
	var ground:=[]
	for id in ids:
		var e:Dictionary=world.paper_space.entries.get(id,{})
		if e.is_empty():continue
		if e.record.mode=="water":
			for rim:Rect2 in _visible_rims(e):rims.append(_feature(id,"water_rim",rim.get_center(),rim))
		elif e.record.mode in ["rock","platform"]:ground.append(e)
		if e.record.get("service",{}).get("kind")=="fruit_market":
			var p:Array=e.record.service.at
			var at:=Vector2(p[0],p[1])
			if Market.station_id(game,at+Vector2(0,.4))==id:stations.append(_feature(id,"counter",at,e.box))
	stations.sort_custom(func(a,b):
		if a.kind!=b.kind:return a.kind=="counter"
		return a.at.distance_squared_to(feet)<b.at.distance_squared_to(feet))
	var station:Dictionary={} if stations.is_empty() else stations.front()
	var anchor:Vector2=station.get("at",feet)
	var wet:Dictionary={}
	var bank:=Vector2.INF
	for rim:Dictionary in rims:
		for end:Vector2 in [rim.box.position,rim.box.end]:
			if end.distance_squared_to(anchor)<bank.distance_squared_to(anchor):
				bank=end
				wet=rim
	var support:=_local_support(world,ground,bank if bank.is_finite() else anchor)
	var summary:={"station":_public_feature(station),"visible_water":_public_feature(wet),"local_support":_public_feature(support)}
	if not station.is_empty() and not wet.is_empty():
		summary.station_to_nearest_bank={"at_m":_pair(bank),"dx_dy_m":_pair(bank-anchor),"straight_m":snappedf(bank.distance_to(anchor),.01)}
	var parts:Array=[]
	for part:Dictionary in [station,wet,support]:
		if not part.is_empty() and parts.size()<2 and (parts.is_empty() or part.work_id!=parts[0].work_id):parts.append(part)
	if parts.size()==1 and not support.is_empty() and parts[0].work_id==support.work_id:
		var other:=_local_support(world,ground.filter(func(entry):return entry.record.work_id!=support.work_id),support.at)
		if not other.is_empty():
			summary.second_support=_public_feature(other)
			parts.append(other)
	if parts.size()<2:return summary
	var span:Rect2=parts[0].box
	for part:Dictionary in parts:span=span.merge(part.box)
	var viewport:Vector2=game.get_viewport_rect().size
	var measured_ppu:float=game.PIXELS_PER_UNIT
	var physical_view:=viewport.x>=320 and viewport.y>=180
	if not physical_view:
		# A background desktop simulation has only a 64x64 dummy viewport.
		viewport=Vector2(1280,720)
		measured_ppu=NORMAL_PX_PER_M
	summary.framing={"frame_source":"current" if physical_view else "normal_background_reference","work_ids":parts.map(func(p):return p.work_id),"required_width_m":snappedf(span.size.x,.001),
		"required_px_at_60":ceili(snappedf(span.size.x*NORMAL_PX_PER_M,.001)),"viewport_px":[roundi(viewport.x),roundi(viewport.y)],
		"active_px_per_m":snappedf(measured_ppu,.01),"active_width_m":snappedf(viewport.x/measured_ppu,.001),
		"fits_horizontally":span.size.x<=viewport.x/measured_ppu,
		"fits_640x360_at_48":span.size.x<=640.0/48.0,"fits_1280x720_at_60":span.size.x<=1280.0/60.0,
		"best_sampled_reachable_view":_best_view(world,feet,parts,viewport,measured_ppu)}
	if physical_view:
		var bottom_left:Vector2=game.screen_to_world(Vector2(0,viewport.y))
		var top_right:Vector2=game.screen_to_world(Vector2(viewport.x,0))
		summary.framing.current_camera_items=_frame_items(parts,Rect2(bottom_left,top_right-bottom_left))
	return summary
