extends RefCounted
## Closed ink on solid village furniture. Missing ink after a cut is passable.
const FURNITURE := ["crate","barrel","fence","bench","haystack","cart_goods","wagon"]

static func nearby(world, area:Rect2) -> Array:
	var shapes:=[]
	for item in world.entities:
		if not item.alive or item.kind not in FURNITURE:continue
		if not area.grow(item.size.length()).has_point(item.position):continue
		for poly in item.world_polygons():
			if poly.size()>=3 and area.intersects(_bounds(poly),true):
				shapes.append({"id":item.entity_id,"points":poly})
	return shapes

static func _bounds(poly:PackedVector2Array) -> Rect2:
	var box:=Rect2(poly[0],Vector2.ZERO)
	for p in poly:box=box.expand(p)
	return box

static func contact(world,from:Vector2,to:Vector2) -> bool:
	var area:=Rect2(from,Vector2.ZERO).expand(to).grow(.01)
	for row in nearby(world,area):
		var p:PackedVector2Array=row.points
		if Geometry2D.is_point_in_polygon(from,p) or Geometry2D.is_point_in_polygon(to,p):return false
		for i in p.size():
			if Geometry2D.segment_intersects_segment(from,to,p[i],p[(i+1)%p.size()])!=null:return false
	return true

static func _area(poly:PackedVector2Array) -> float:
	var sum:=0.0
	for i in poly.size():sum+=poly[i].cross(poly[(i+1)%poly.size()])
	return absf(sum)*.5

static func _overlap(a,foot:Vector2,slope:float,facing:int,solid:PackedVector2Array) -> float:
	var transform:=Transform2D(slope,foot).scaled_local(Vector2(facing,1))
	var total:=0.0
	for rest:PackedVector2Array in a.form.occupancy:
		var shape:=transform*rest
		for poly in Geometry2D.intersect_polygons(shape,solid): total+=_area(poly)
	return total

static func fits(a,at:Vector2,slope:float,facing:int) -> bool:
	return blocking_prop(a,at,slope,facing).is_empty()

static func blocking_prop(a,at:Vector2,slope:float,facing:int) -> String:
	var radius:float=a.form.body_bounds.size.length()+.2
	for row in nearby(a.world,Rect2(at,Vector2.ZERO).grow(radius)):
		if _overlap(a,at,slope,facing,row.points)>.00008:return row.id
	return ""

static func permits(a,from:Vector2,to:Vector2,slope:float,facing:int) -> bool:
	return movement_blocker(a,from,to,slope,facing).is_empty()

# Both real and trial steps can back away in the old pose until the body fits a turn.
static func walking_pose(a,from:Vector2,to:Vector2,slope:float,current_face:int,wanted:int) -> Dictionary:
	var blocker:=movement_blocker(a,from,to,slope,wanted,current_face)
	if blocker.is_empty():return {"face":wanted,"blocker":""}
	if wanted!=current_face and movement_blocker(a,from,to,slope,current_face,current_face).is_empty():
		return {"face":current_face,"blocker":""}
	return {"face":current_face,"blocker":blocker}

static func movement_blocker(a,from:Vector2,to:Vector2,slope:float,facing:int,from_face:int=0) -> String:
	var radius:float=a.form.body_bounds.size.length()+.2
	var path:=Rect2(from,Vector2.ZERO).expand(to).grow(radius)
	for row in nearby(a.world,path):
		var after:=_overlap(a,to,slope,facing,row.points)
		if after<.00008:continue
		# Historical saves can start intersecting furniture. Only retreat may reduce overlap.
		if after>=_overlap(a,from,slope,a.face if from_face==0 else from_face,row.points)-.00001:return row.id
	return ""

static func clearance(a,foot:Vector2,slope:float,facing:int) -> float:
	var radius:float=a.form.body_bounds.size.length()+.2
	var result:=0.0
	for row in nearby(a.world,Rect2(foot,Vector2.ZERO).grow(radius)):
		result+=_overlap(a,foot,slope,facing,row.points)
	return result
