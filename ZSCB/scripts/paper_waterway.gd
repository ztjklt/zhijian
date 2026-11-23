extends RefCounted
## Measure a rectangular passage in a cross-section of the live world. The
## footprint and deck height are taken from a built crossing, in world metres.
const Ink := preload("res://scripts/paper_space.gd")
const Shapes := preload("res://scripts/spawn_clearance.gd")
const Plans := preload("res://scripts/architecture/building_plans.gd")
const Furniture := preload("res://scripts/priest_obstacles.gd")
const WIDTH := 1.80
const DRAFT := 0.12
const HEADROOM := 1.25
const EPS := 0.0001

static func _span(points: PackedVector2Array, bottom: float, top: float) -> Vector2:
	# Project only the part of this convex fixture inside the specified band.
	# This also works for the zero-thickness segments of a concave shape.
	var left := INF
	var right := -INF
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		if bottom<=a.y and a.y<=top:
			left=minf(left,a.x)
			right=maxf(right,a.x)
		for y:float in [bottom,top]:
			if (a.y<y and y<b.y) or (b.y<y and y<a.y):
				var x:=lerpf(a.x,b.x,(y-a.y)/(b.y-a.y))
				left=minf(left,x)
				right=maxf(right,x)
	return Vector2(left,right)

static func _union(intervals: Array) -> Array:
	intervals.sort_custom(func(a:Vector2,b:Vector2):return a.x<b.x)
	var merged := []
	for span:Vector2 in intervals:
		if merged.is_empty() or span.x>merged[-1].y+EPS:
			merged.append(span)
		else:
			merged[-1]=Vector2(merged[-1].x,maxf(merged[-1].y,span.y))
	return merged

static func _fixtures(world, area:Rect2) -> Array:
	var shape:=RectangleShape2D.new()
	shape.size=area.size
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape
	query.transform=Transform2D(0,area.get_center())
	query.collision_mask=1|128
	var state:PhysicsDirectSpaceState2D=world.get_world_2d().direct_space_state
	var limit:=32
	var hits:=state.intersect_shape(query,limit)
	while hits.size()==limit:
		limit*=2
		hits=state.intersect_shape(query,limit)
	# Distant paper cells can be asleep in the physics server.
	var result:=[]
	for polygon:PackedVector2Array in world.paper_geometry(area):
		if area.intersects(Shapes._bounds(polygon),true):result.append(polygon)
	for item:Dictionary in Furniture.nearby(world,area):
		result.append(item.points)
	for hit:Dictionary in hits:
		var body=hit.collider
		if body is MedievalEntity and body.kind not in Furniture.FURNITURE:
			continue
		result.append_array(Shapes._hit_parts(hit))
	return result

static func at_building(game, project:Dictionary, access:Vector2) -> Dictionary:
	var ids:Array=project.get("work_ids",[])
	for obj:Dictionary in game.objects:
		if not obj.get("work_id","") in ids or not obj.has("built_plan") or obj.get("hp",1)<=0:continue
		var built:Dictionary=obj.built_plan
		var origin:Vector2=game.object_point(obj,Plans.point(built.offset))
		if not built.layout.access.any(func(p):return (origin+Plans.point(p)).distance_to(access)<=Plans.STATION_TOLERANCE):continue
		var base:Dictionary=Plans._intervals(built.layout,origin)[0]
		var left:float=base.x-base.width*.5
		var width:=Vector2(left,left+float(base.width))
		var measurement:=measure(game.medieval_world,ids,width,access.y)
		measurement.building_work_id=obj.work_id
		measurement.frontage=[width.x,width.y]
		return measurement
	return {"passable":false,"clear_width_m":0.0,"error":"此处没有本工程已经建好的使用位"}

static func water_parts(entry: Dictionary) -> Array:
	var pose:=Transform2D(0,Ink.origin_for(entry.frame))
	var result: Array=[]
	for part: PackedVector2Array in entry.parts:
		result.append(pose*part)
	return result

static func uncovered_water(parts:Array, cover:Array) -> Array:
	if cover.is_empty():return parts.duplicate()
	var result: Array=[]
	for part:PackedVector2Array in parts:
		var box:=Shapes._bounds(part)
		var cuts:=cover.filter(func(poly):return box.intersects(Shapes._bounds(poly)))
		if cuts.is_empty():result.append(part)
		else:result.append_array(Ink.subtract([part],cuts))
	return result

static func measure(world, ids:Array, footprint:Vector2, deck_height:float) -> Dictionary:
	var report:={"passable":false,"clear_width_m":0.0,"span":[],"levels":[],"required_width_m":WIDTH,"draft_m":DRAFT,"headroom_m":HEADROOM}
	if world==null or world.paper_space==null or not footprint.is_finite() or footprint.y<=footprint.x or not is_finite(deck_height):
		return report
	var by_level:={}
	var heights:Array[float]=[]
	for id in ids:
		var entry:Dictionary=world.paper_space.entries.get(id,{})
		if entry.is_empty() or entry.record.mode!="water" or entry.parts.is_empty():continue
		if entry.box.end.x<=footprint.x or entry.box.position.x>=footprint.y:continue
		var level:float=entry.box.end.y
		if deck_height-level<HEADROOM-EPS:continue
		# Endpoint snapping remains local to a drawn page. Treat matching
		# levels across page boundaries the same way as matching x endpoints.
		var index:=heights.find_custom(func(h):return absf(h-level)<=EPS)
		if index>=0:
			level=heights[index]
		else:
			heights.append(level)
			by_level[level]=[]
		by_level[level].append_array(water_parts(entry))
	for level:float in by_level:
		var band:=Rect2(Vector2(footprint.x,level-DRAFT),Vector2(footprint.y-footprint.x,DRAFT))
		# All overlapping water can supersede the credited surface at the keel,
		# even when its author or height makes it ineligible for this project.
		var higher: Array=[]
		for entry: Dictionary in world.paper_space.nearby(band):
			if entry.record.mode=="water" and entry.box.end.y>level+EPS:
				higher.append_array(water_parts(entry))
		var wet:=uncovered_water(by_level[level],higher)
		# Removing all wet polygons from the hull strip leaves every dry gap,
		# including an island between two pieces that meet along the top edge.
		var gaps:=[]
		for dry:PackedVector2Array in Ink.subtract([Shapes._box(band)],wet):
			var box:=Shapes._bounds(dry)
			gaps.append(Vector2(box.position.x,box.end.x))
		var overhangs:=[]
		var area:=Rect2(band.position,Vector2(band.size.x,deck_height+.22-band.position.y))
		for polygon:PackedVector2Array in _fixtures(world,area):
			var obstacle:=_span(polygon,band.position.y+EPS,level+HEADROOM-EPS)
			if obstacle.x<=obstacle.y:gaps.append(obstacle)
			var above:=_span(polygon,level+HEADROOM-EPS,area.end.y)
			if above.x<=above.y:overhangs.append(above)
		var openings:=[]
		var blocked:=_union(gaps)
		for roof:Vector2 in _union(overhangs):
			var start:=maxf(footprint.x,roof.x)
			var end:=minf(footprint.y,roof.y)
			for stop:Vector2 in blocked:
				if stop.y<=start or stop.x>=end:continue
				if stop.x>start:openings.append(Vector2(start,stop.x))
				start=maxf(start,stop.y)
			if start<end:openings.append(Vector2(start,end))
		var intervals:=[]
		for span:Vector2 in openings:
			intervals.append([span.x,span.y])
			if span.y-span.x>report.clear_width_m:
				report.clear_width_m=span.y-span.x
				report.span=[span.x,span.y]
				report.water_level=level
		report.levels.append({"water_level":level,"spans":intervals})
	report.passable=report.clear_width_m+EPS>=WIDTH
	return report
