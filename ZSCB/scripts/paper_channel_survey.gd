extends RefCounted
## Horizontal sections at one water level in the artist's current world. No ink,
## route, save or project state is changed here. Coordinates are world metres.
const Way := preload("res://scripts/paper_waterway.gd")
const Ink := preload("res://scripts/paper_space.gd")
const Shapes := preload("res://scripts/spawn_clearance.gd")
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Reach := preload("res://scripts/companion_pen_reach.gd")
const Furniture := preload("res://scripts/priest_obstacles.gd")
const RANGE := 16.0

static func _intersection(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(maxf(a.x,b.x),minf(a.y,b.y))

static func _clip(spans: Array, window: Vector2) -> Array:
	var clipped := []
	for span: Vector2 in spans:
		var part := _intersection(span,window)
		if part.y-part.x > Way.EPS: clipped.append(part)
	return Way._union(clipped)

static func _gaps(window: Vector2, spans: Array) -> Array:
	var open := []
	var left := window.x
	for span: Vector2 in _clip(spans,window):
		if span.x-left > Way.EPS: open.append(Vector2(left,span.x))
		left=span.y
	if window.y-left > Way.EPS: open.append(Vector2(left,window.y))
	return open

static func _band(parts: Array, bottom: float, top: float, window: Vector2, barriers:=false) -> Array:
	var spans := []
	for part: PackedVector2Array in parts:
		var hit := Way._span(part,bottom,top)
		if hit.x>hit.y: continue
		if barriers and hit.y-hit.x<Way.EPS:
			hit+=Vector2(-Way.EPS,Way.EPS)
		spans.append(hit)
	return _clip(spans,window)

static func _pairs(spans: Array) -> Array:
	var pairs := []
	for s: Vector2 in spans: pairs.append([s.x,s.y])
	return pairs

static func _widest(spans: Array) -> float:
	var width := 0.0
	for s: Vector2 in spans: width=maxf(width,s.y-s.x)
	return width

static func _building(game, project: Dictionary, feet: Vector2) -> Dictionary:
	var best := {}
	var distance := INF
	for obj: Dictionary in game.objects:
		if not obj.has("built_plan") or obj.get("hp",1)<=0 or not obj.get("work_id","") in project.get("work_ids",[]): continue
		if not project.get("trade_targets",[]).is_empty() and not obj.get("structure_id","") in project.trade_targets: continue
		var meta: Dictionary=obj.built_plan
		var origin: Vector2=game.object_point(obj,Plans.point(meta.offset))
		var layout: Dictionary=meta.layout
		if layout.get("access",[]).is_empty() or layout.get("supports",[]).is_empty(): continue
		var base: Dictionary=Plans._intervals(layout,origin)[0]
		var interval := Vector2(base.x-base.width*.5,base.x+base.width*.5)
		for offset in layout.access:
			var access:=origin+Plans.point(offset)
			var d:=feet.distance_to(access)
			if d>RANGE or d>=distance: continue
			distance=d
			var pins: Array=[]
			for pin in layout.supports:
				var at:=origin+Plans.point(pin)
				pins.append({"at":[at.x,at.y],"bearing":Plans._load_bearing(game,at,Plans.FOOT_TOLERANCE),
					"faces":game.medieval_world.paper_surfaces(at.x,at.y-Plans.FOOT_TOLERANCE,at.y+Plans.FOOT_TOLERANCE)})
			best={"work_id":obj.work_id,"structure_id":obj.get("structure_id",""),"frontage":interval,"access":access,
				"access_clear":Plans._can_stand(game,access),"supports":pins}
	return best

static func _level(groups: Dictionary, y: float) -> Dictionary:
	for key: float in groups:
		if absf(key-y)<=Way.EPS: return groups[key]
	groups[y]={"parts":[],"river":[],"sources":[]}
	return groups[y]

## The old river tests against its original riverbed even after newer ink carves
## the soil. Clip its wet band to the same lower bound as Terrain.water_surface.
static func _old_river(terrain, zone: Dictionary, window: Vector2) -> Array:
	var span:=_intersection(window,Vector2(zone.left,zone.right))
	var water: Array=[]
	if span.y<=span.x: return water
	var xs: Array[float]=[span.x]
	for i in range(terrain.profile_span(terrain.profile,span.x),terrain.profile_span(terrain.profile,span.y)+1):
		var x:float=terrain.profile[i].x
		if x>span.x and x<span.y: xs.append(x)
	xs.append(span.y)
	var y:=float(zone.height)
	for i in range(1,xs.size()):
		var a:=Vector2(xs[i-1],terrain.surface_height(xs[i-1])-.4)
		var b:=Vector2(xs[i],terrain.surface_height(xs[i])-.4)
		if minf(a.y,b.y)>=y: continue
		if a.y>y: a=a.lerp(b,(y-a.y)/(b.y-a.y))
		if b.y>y: b=b.lerp(a,(y-b.y)/(a.y-b.y))
		var part:=Ink.clean_part(PackedVector2Array([Vector2(a.x,y),Vector2(b.x,y),b,a]))
		if not part.is_empty(): water.append(part)
	return water

static func _waters(world, area: Rect2) -> Dictionary:
	var groups: Dictionary={}
	for e: Dictionary in world.paper_space.nearby(area):
		if e.record.mode!="water" or e.parts.is_empty() or e.box.end.y<area.position.y: continue
		var group:=_level(groups,e.box.end.y)
		group.sources.append(e.record.work_id)
		group.parts.append_array(Way.water_parts(e))
	for zone: Dictionary in world.terrain.WATER_ZONES:
		if zone.height<area.position.y: continue
		var parts:=_old_river(world.terrain,zone,Vector2(area.position.x,area.end.x))
		if not parts.is_empty():
			var group:=_level(groups,zone.height)
			group.river.append_array(parts)
			group.sources.append("legacy:water")
	# Terrain.water_surface gives paper water priority over a village river,
	# and overlapping paper water uses the higher of the two real surfaces.
	var higher: Array=[]
	var heights:=groups.keys()
	heights.sort()
	heights.reverse()
	var paper: Array=[]
	for liquid:Dictionary in groups.values():paper.append_array(liquid.parts)
	for height:float in heights:
		var group:Dictionary=groups[height]
		var raw: Array=group.parts
		group.parts=Way.uncovered_water(raw,higher)
		group.parts.append_array(Way.uncovered_water(group.river,paper))
		higher.append_array(raw)
	return groups

## The artist sees the extent of existing water along the surrounding bank.
## Connected strokes at the same level describe one visible waterline.
static func nearby_waterlines(world, at: Vector2) -> Dictionary:
	var area := Rect2(at - Vector2(24, 6), Vector2(48, 12))
	var window := Vector2(area.position.x, area.end.x)
	var groups := _waters(world, area)
	var lines := []
	for level: float in groups:
		if level < area.position.y or level > area.end.y:
			continue
		var wet := preload("res://scripts/paper_water_sections.gd")._intervals(groups[level].parts, level, false)
		for span: Vector2 in _clip(wet, window):
			# Subpixel slivers in the cross-section do not read as separate pools.
			if (span.y - span.x) * 60.0 < 1.0:
				continue
			var nearest := Vector2(clampf(at.x, span.x, span.y), level)
			lines.append({"left_x":snappedf(span.x, .001), "right_x":snappedf(span.y, .001),
				"water_y":snappedf(level, .001), "width_in_view_m":snappedf(span.y - span.x, .001),
				"distance_m":snappedf(at.distance_to(nearest), .01)})
	lines.sort_custom(func(a, b): return a.distance_m < b.distance_m)
	return {"window_x_m":[window.x, window.y], "count":lines.size(), "nearest":lines.slice(0, 6)}

static func _hand_span(brush: Dictionary, y: float, window: Vector2) -> Array:
	var grip:=Plans.point(brush.hand)
	# The public hand reading is rounded to centimetres. Keep the reported
	# span inside the disc for every hand position with that reading.
	var radius:=maxf(0,minf(Reach.PLAN_RADIUS,float(brush.get("radius",Reach.PLAN_RADIUS)))-.008)
	var dy:=absf(grip.y-y)
	if not brush.get("grounded",false) or dy>=radius: return []
	var dx:=sqrt(radius*radius-dy*dy)
	return _pairs(_clip([Vector2(grip.x-dx,grip.x+dx)],window))

## For the actor's local active cells, query the actual bodies once. In
## particular an original fence or a one-way floor cannot be excavated as soil.
static func _fixtures(world, area: Rect2) -> Dictionary:
	var shape:=RectangleShape2D.new()
	shape.size=area.size
	var q:=PhysicsShapeQueryParameters2D.new()
	q.shape=shape
	q.transform=Transform2D(0,area.get_center())
	q.collision_mask=1|128
	var space: PhysicsDirectSpaceState2D=world.get_world_2d().direct_space_state
	var count:=64
	var hits:=space.intersect_shape(q,count)
	while hits.size()==count:
		count*=2
		hits=space.intersect_shape(q,count)
	var all: Array=[]
	var soil: Array=[]
	var fixtures: Dictionary={}
	var platforms: Array=[]
	for h: Dictionary in hits:
		var body=h.collider
		if body is MedievalEntity and body.kind not in Furniture.FURNITURE: continue
		var parts:=Shapes._hit_parts(h)
		all.append_array(parts)
		var paper_id:=str(body.get_meta("paper_work_id",""))
		if body.has_meta("terrain_profile") or (body.get_parent()==world.paper_space and (paper_id=="" or world.paper_space.entries.get(paper_id,{}).get("record",{}).get("mode")=="rock")):
			soil.append_array(parts)
		else:
			var id:=paper_id
			if body.get_meta("map_drop_allowed",false):
				platforms.append_array(parts)
				if id.is_empty(): id="fixed_platform"
			if body is MedievalEntity: id=str(body.entity_id)
			elif body.has_meta("medieval_owner"): id=str(body.get_meta("medieval_owner").entity_id)
			elif body is BuildObject: id=str(body.data.get("work_id",body.data.get("structure_id","")))
			fixtures.get_or_add(id if not id.is_empty() else "fixed_fixture",[]).append_array(parts)
	for item in Furniture.nearby(world,area):
		fixtures.get_or_add(item.id,[]).append(item.points)
		all.append(item.points)
	return {"all":all,"soil":soil,"platforms":platforms,"fixtures":fixtures}

static func _bank_faces(outside: Array, soil: Array, wet: Array, deck:Vector2) -> Array:
	var faces: Array=[]
	for air: Vector2 in outside:
		for side: int in [-1,1]:
			var x:=air.x if side<0 else air.y
			if x>=deck.x and x<=deck.y: continue
			if not soil.any(func(s):return absf(x-(s.y if side<0 else s.x))<=Way.EPS): continue
			var liquid:=_clip(wet,air)
			var wet_at_edge:=liquid.any(func(s):return absf(x-(s.x if side<0 else s.y))<=Way.EPS)
			faces.append({"x":x,"toward_soil":side,"wet_at_face":wet_at_edge,"open_side":[air.x,air.y]})
	return faces

## At the current foot and hand a shallow new cut is visible before it is
## tall enough for a vessel. These are measured spans, never a drawing path.
static func _working_layers(brush:Dictionary, gauge:float, geometry:Dictionary, volumes:Array, window:Vector2) -> Dictionary:
	var hand:=Plans.point(brush.hand)
	var feet:=Plans.point(brush.feet)
	var local:=_intersection(window,Vector2(hand.x-3.6,hand.x+3.6))
	var rows: Array=[]
	for y:float in [feet.y+.035,hand.y,gauge-Way.DRAFT,gauge,gauge+Way.HEADROOM]:
		if rows.any(func(row):return absf(row.y-y)<.01): continue
		var solid:=_band(geometry.soil,y,y,local,true)
		var blocked:=_band(geometry.all,y,y,local,true)
		var wet: Array=[]
		for gap:Vector2 in _gaps(local,blocked):
			wet.append_array(_band(volumes,y,y,gap))
		rows.append({"y":y,"soil":_pairs(solid),"free":_pairs(_gaps(local,blocked)),
			"wet":_pairs(wet),"hand_span":_hand_span(brush,y,local)})
	return {"window":[local.x,local.y],"rows":rows}

static func _section(level: float, water: Dictionary, window: Vector2, deck: Vector2, top: float,
		geometry: Dictionary, volumes: Array, brush: Dictionary, width: float) -> Dictionary:
	var low:=level-Way.DRAFT
	var high:=level+Way.HEADROOM
	var strip:=Rect2(Vector2(window.x,low),Vector2(window.y-window.x,Way.DRAFT))
	var obstacles:=_band(geometry.all,low+Way.EPS,high-Way.EPS,window,true)
	var earth:=_band(geometry.soil,low+Way.EPS,high-Way.EPS,window,true)
	var overhead:=_band(geometry.all,high-Way.EPS,maxf(top,high+.01),window,true)
	var dry_gaps: Array=[]
	for dry: PackedVector2Array in Ink.subtract([Shapes._box(strip)],water.parts):
		var box:=Shapes._bounds(dry)
		dry_gaps.append(Vector2(box.position.x,box.end.x))
	var wet:=_gaps(window,obstacles+dry_gaps)
	var wet_here:=_band(water.parts,low+Way.EPS,level-Way.EPS,window)
	var any_water:=_band(volumes,low+Way.EPS,level-Way.EPS,window)
	var dry_air:=_gaps(window,obstacles+any_water)
	var open_air:=_gaps(window,obstacles+overhead)
	var covered_wet: Array=[]
	for roof: Vector2 in _clip(overhead,deck): covered_wet.append_array(_clip(wet,roof))
	var mouths: Array=[]
	var through: Array=[]
	for run: Vector2 in wet:
		var sides: Array=[[],[]]
		var under:=_clip(covered_wet,run)
		for daylight: Vector2 in _clip(open_air,run):
			for index in 2:
				var side:=Vector2(window.x,deck.x) if index==0 else Vector2(deck.y,window.y)
				var outside:=_intersection(daylight,side)
				if outside.y-outside.x<=Way.EPS: continue
				sides[index].append(outside)
				mouths.append({"open_water":[outside.x,outside.y],"wet_run":[run.x,run.y],
					"covered_under_building":_pairs(under),"fits_from_outside":outside.y-outside.x+Way.EPS>=width and _widest(under)+Way.EPS>=width})
		if _widest(under)+Way.EPS>=width and _widest(sides[0])+Way.EPS>=width and _widest(sides[1])+Way.EPS>=width:
			through.append({"run":[run.x,run.y],"west":_pairs(sides[0]),"under":_pairs(under),"east":_pairs(sides[1])})
	var objects: Dictionary={}
	for id in geometry.fixtures:
		var at_height:=_band(geometry.fixtures[id],low+Way.EPS,high-Way.EPS,window,true)
		if not at_height.is_empty(): objects[id]=_pairs(at_height)
	return {"level":level,"water_sources":water.sources,"ground_or_platform":_pairs(Way._union(earth+_band(geometry.platforms,low+Way.EPS,high-Way.EPS,window,true))),"solid_earth":_pairs(earth),"all_obstructions":_pairs(obstacles),
		"furniture":objects,"dry_clear":_pairs(dry_air),"same_level_water_present":_pairs(wet_here),"open_to_sky_in_window":_pairs(open_air),"wet_clear":_pairs(wet),
		"under_building_wet":_pairs(covered_wet),"clear_width_m":_widest(covered_wet),"meets_width_under_building":_widest(covered_wet)+Way.EPS>=width,
		"bank_faces":_bank_faces(open_air,earth,wet_here,deck),"open_water_mouths":mouths,"through_both_open_sides":through,
		"hand_at_keel":_hand_span(brush,low,window),"hand_at_waterline":_hand_span(brush,level,window),"hand_at_crown":_hand_span(brush,high,window)}

static func observe(game, project: Dictionary, brush: Dictionary, required_width_m: float=Way.WIDTH, preferred_level: Variant=null) -> Dictionary:
	if not Plans.pair(brush.get("feet")) or not Plans.pair(brush.get("hand")) or not is_finite(required_width_m) or required_width_m<=0: return {}
	var feet:=Plans.point(brush.feet)
	if game==null or game.medieval_world==null or game.medieval_world.paper_space==null: return {}
	var target:=_building(game,project,feet)
	if target.is_empty(): return {}
	var deck: Vector2=target.frontage
	var access: Vector2=target.access
	var window:=Vector2(maxf(feet.x-RANGE,deck.x-RANGE),minf(feet.x+RANGE,deck.y+RANGE))
	var top:=maxf(access.y,feet.y)+6.0
	var area:=Rect2(Vector2(window.x,minf(feet.y,access.y)-RANGE),Vector2(window.y-window.x,0))
	area.size.y=top-area.position.y
	var world=game.medieval_world
	var waters:=_waters(world,area)
	var gauge:=float(feet.y)+Way.DRAFT
	if preferred_level is float or preferred_level is int:
		if not is_finite(float(preferred_level)) or float(preferred_level)<area.position.y or float(preferred_level)>top: return {}
		gauge=float(preferred_level)
	else:
		gauge=minf(gauge,access.y-Way.HEADROOM-Plans.FOOT_TOLERANCE)
	_level(waters,gauge)
	var geometry:=_fixtures(world,area)
	var volumes: Array=[]
	for liquid: Dictionary in waters.values(): volumes.append_array(liquid.parts)
	# A higher surface can lie above the view while its water reaches the keel.
	# Keep that volume for occupancy, but offer only levels within this window.
	var levels:=waters.keys().filter(func(y):return y>=area.position.y and y<=top)
	levels.sort_custom(func(a,b):return absf(a-gauge)<absf(b-gauge))
	var rows: Array=[]
	for y: float in levels.slice(0,4):
		rows.append(_section(y,waters[y],window,deck,top,geometry,volumes,brush,required_width_m))
	target.frontage=[deck.x,deck.y]
	target.access=[access.x,access.y]
	return {"building":target,"window":[window.x,window.y],"full_frontage_in_view":window.x<=deck.x and window.y>=deck.y,"sky_checked_to_y":top,"feet":brush.feet,"hand":brush.hand,
		"required_width_m":required_width_m,"draft_m":Way.DRAFT,"headroom_m":Way.HEADROOM,"levels_in_window":levels,
		"sections":rows,"workface":_working_layers(brush,gauge,geometry,volumes,window)}
