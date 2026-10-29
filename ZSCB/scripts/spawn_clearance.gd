class_name PaperSpawnClearance
extends RefCounted
## Nearest safe translation of the actual compound, without changing its art.
## Search the boundary of forbidden translations, not a capped radial grid.
const GAP := 0.006
const MASK := 1 | 2 | 8 | 16 | 64 | 128
const CURVE_STEPS := 32
const DEEP := -1000000.0

static func _contacts(game, node: RigidBody2D, offset: Vector2) -> Array:
	var result: Array = []
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = MASK
	query.margin = 0.001
	query.exclude = [node.get_rid()]
	for fixture in node.get_children():
		if not fixture is CollisionShape2D or fixture.disabled or fixture.shape == null: continue
		query.shape = fixture.shape
		query.transform = node.transform * fixture.transform
		query.transform.origin += offset
		# A full batch is not treated as proof of clearance. Newly discovered
		# blockers are queried again at each candidate until no actual hit remains.
		for hit in game.get_world_2d().direct_space_state.intersect_shape(query,64):
			hit["moving_fixture"] = fixture
			result.append(hit)
	return result

static func _box(rect:Rect2)->PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

static func _hull(points:PackedVector2Array)->PackedVector2Array:
	var polygon:=Geometry2D.convex_hull(points)
	if polygon.size()>1 and polygon[0].is_equal_approx(polygon[-1]):polygon.remove_at(polygon.size()-1)
	return polygon

static func _shape_parts(shape:Shape2D,pose:Transform2D)->Array:
	var points:=PackedVector2Array()
	if shape is ConvexPolygonShape2D: points=shape.points
	elif shape is RectangleShape2D:points=_box(shape.get_rect())
	elif shape is CircleShape2D or shape is CapsuleShape2D:
		# Circumscribed curves keep the real physics test conservative. At hero
		# scale the approximation is under 1.5mm; narrow polygon holes stay exact.
		var radius:float=shape.radius/cos(PI/CURVE_STEPS)
		var stem:float=maxf(0,shape.height*.5-shape.radius) if shape is CapsuleShape2D else 0.0
		for i in CURVE_STEPS:
			var a:=TAU*float(i)/CURVE_STEPS
			points.append(Vector2(cos(a)*radius,sin(a)*radius+stem))
			if stem>0:points.append(Vector2(cos(a)*radius,sin(a)*radius-stem))
		if stem>0:points=_hull(points)
	elif shape is SegmentShape2D:points=PackedVector2Array([shape.a,shape.b])
	elif shape is ConcavePolygonShape2D:
		var parts:Array=[]
		for i in range(0,shape.segments.size()-1,2):parts.append(pose*PackedVector2Array([shape.segments[i],shape.segments[i+1]]))
		return parts
	else:points=_box(shape.get_rect())
	return [pose*points]

static func _hit_parts(hit:Dictionary)->Array:
	var collider:CollisionObject2D=hit.collider
	var owner:=collider.shape_find_owner(hit.shape)
	for i in collider.shape_owner_get_shape_count(owner):
		if collider.shape_owner_get_shape_index(owner,i)==hit.shape:
			return _shape_parts(collider.shape_owner_get_shape(owner,i),collider.global_transform*collider.shape_owner_get_transform(owner))
	return []

static func _bounds(points:PackedVector2Array)->Rect2:
	var result:=Rect2(points[0],Vector2.ZERO)
	for p in points:result=result.expand(p)
	return result

static func _forbidden(moving:PackedVector2Array,obstacle:PackedVector2Array)->PackedVector2Array:
	var sums:=PackedVector2Array()
	for b in obstacle:
		for a in moving:sums.append(b-a)
	var hull:=_hull(sums)
	if hull.size()<3:return PackedVector2Array()
	var expanded:=Geometry2D.offset_polygon(hull,GAP,Geometry2D.JOIN_MITER)
	return _hull(expanded[0]) if not expanded.is_empty() else hull

static func _strictly_inside(point:Vector2,polygon:PackedVector2Array)->bool:
	if not Geometry2D.is_point_in_polygon(point,polygon):return false
	# Native clipping quantizes intersections. A 50-micrometre boundary
	# tolerance stays well inside the 6mm physical safety clearance.
	for i in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()]))<.00005:return false
	return true

static func _before(a:Vector2,b:Vector2)->bool:
	var difference:=a.length()-b.length()
	if absf(difference)>.00005:return difference<0
	if absf(a.y-b.y)>.00001:return a.y>b.y
	return a.x<b.x

static func _enqueue(state:Dictionary,point:Vector2)->void:
	point.x=clampf(point.x,state.min_x,state.max_x)
	if not point.is_finite():return
	# int64 text keys also cover deep-soil candidates without Vector2i overflow.
	var key:=str(roundi(point.x*100000))+":"+str(roundi(point.y*100000))
	if state.visited.has(key):return
	state.visited[key]=true
	var heap:Array=state.heap
	heap.append(point)
	var at:=heap.size()-1
	while at>0:
		var parent: int=(at-1)/2
		if not _before(heap[at],heap[parent]):break
		var swap:Vector2=heap[parent];heap[parent]=heap[at];heap[at]=swap;at=parent

static func _pop(state:Dictionary)->Vector2:
	var heap:Array=state.heap
	var result:Vector2=heap[0]
	var last:Vector2=heap.pop_back()
	if heap.is_empty():return result
	heap[0]=last
	var at:=0
	while at*2+1<heap.size():
		var child:=at*2+1
		if child+1<heap.size() and _before(heap[child+1],heap[child]):child+=1
		if not _before(heap[child],heap[at]):break
		var swap:Vector2=heap[at];heap[at]=heap[child];heap[child]=swap;at=child
	return result

static func _add_region(state:Dictionary,polygon:PackedVector2Array)->void:
	if polygon.size()<3:return
	var bounds:=_bounds(polygon)
	for i in polygon.size():
		var a:=polygon[i];var b:=polygon[(i+1)%polygon.size()]
		_enqueue(state,Geometry2D.get_closest_point_to_segment(Vector2.ZERO,a,b))
		_enqueue(state,a)
		# World-edge constraints can make the closest exit an intersection with
		# the permitted x interval rather than an unconstrained edge projection.
		for x:float in [state.min_x,state.max_x]:
			if is_finite(x) and absf(b.x-a.x)>.00001 and x>=minf(a.x,b.x) and x<=maxf(a.x,b.x):
				_enqueue(state,Vector2(x,lerpf(a.y,b.y,(x-a.x)/(b.x-a.x))))
	for region in state.regions:
		if not bounds.intersects(region.bounds,true):continue
		var other:PackedVector2Array=region.polygon
		# Intersection outlines contain all boundary crossings, including
		# nonconvex batch unions, without quadratic per-edge script loops.
		for overlap in Geometry2D.intersect_polygons(polygon,other):
			for point in overlap:_enqueue(state,point)
	state.regions.append({"polygon":polygon,"bounds":bounds})

static func _collect_region(state:Dictionary,batch:Array,moving:PackedVector2Array,obstacle:PackedVector2Array,key:String)->void:
	if state.seen.has(key):return
	state.seen[key]=true
	var polygon:=_forbidden(moving,obstacle)
	if polygon.size()>=3:batch.append(polygon)

static func _add_batch(state:Dictionary,batch:Array)->void:
	# Every new forbidden region contains the candidate that discovered it.
	# Their exact union is star-shaped around that point and cannot close a
	# real hole. Merge internal boundaries in native geometry before finding
	# the nearest exposed features (important for hundreds of ink fixtures).
	var components:Array=[]
	for source in batch:
		var polygon:PackedVector2Array=source
		var i:=0
		while i<components.size():
			var united:=Geometry2D.merge_polygons(polygon,components[i])
			if united.size()==1:
				polygon=united[0];components.remove_at(i);i=0
			else:i+=1
		components.append(polygon)
	for polygon in components:_add_region(state,polygon)

static func _soil(a:Vector2,b:Vector2)->PackedVector2Array:
	return _hull(PackedVector2Array([a,b,Vector2(b.x,DEEP),Vector2(a.x,DEEP)]))

static func _world_geometry(game)->Dictionary:
	var result:Dictionary={"left":-INF,"right":INF,"polygons":[]}
	var world=game.get("medieval_world")
	if world!=null:
		var profile:PackedVector2Array=world.terrain.profile
		result.left=profile[0].x;result.right=profile[-1].x
		for i in range(1,profile.size()):result.polygons.append(_soil(profile[i-1],profile[i]))
		return result
	world=game.get("knowledge_world")
	if world!=null:
		result.left=INF;result.right=-INF
		var ground=world.get("ground_shapes")
		if ground is Array:
			for polygon in ground:
				result.polygons.append(_soil(polygon[3],polygon[2]))
		else:
			for rect in world.terrain_rects:result.polygons.append(_soil(Vector2(rect.position.x,rect.end.y),rect.end))
		for rect in world.terrain_rects:
			result.left=minf(result.left,rect.position.x);result.right=maxf(result.right,rect.end.x)
		# Include unloaded chapter geometry: an automatic displacement beyond
		# the current chunks must not become embedded when its chunk loads.
		for rect in world.raised_tiers:result.polygons.append(_box(rect))
		for path in world.paths:
			for i in range(1,path.points.size()):
				var a:Vector2=path.points[i-1];var b:Vector2=path.points[i]
				if a.distance_to(b)<.02:continue
				var chunk:=int(floor((a.x+b.x)*.5/world.CHUNK))
				if world.chunks.has(chunk):continue
				result.polygons.append(Transform2D((b-a).angle(),(a+b)*.5)*_box(Rect2(Vector2(-(a.distance_to(b)+.025)*.5,-.035),Vector2(a.distance_to(b)+.025,.07))))
		return result
	# Flat legacy worlds have an unbounded baseline, even past the finite
	# physical ground fixture used by the renderer/test scene.
	var floor_y:float=game.get("GROUND_Y") if game.get("GROUND_Y")!=null else -2.8
	result.polygons.append(_soil(Vector2(-100000,floor_y),Vector2(100000,floor_y)))
	return result

static func resolve(game,node:RigidBody2D,object:Dictionary)->Dictionary:
	if not Vector2(float(object.get("x",NAN)),float(object.get("y",NAN))).is_finite() or not is_finite(float(object.get("angle",0))):return {"valid":false}
	var moving:Array=[]
	var by_fixture:Dictionary={}
	var footprint:=Rect2()
	var has_bounds:=false
	for fixture in node.get_children():
		if not fixture is CollisionShape2D or fixture.disabled or fixture.shape==null:continue
		var parts:=_shape_parts(fixture.shape,node.transform*fixture.transform)
		by_fixture[fixture.get_instance_id()]=parts
		for polygon in parts:
			if polygon.size()<3:continue
			for p in polygon:
				if not p.is_finite():return {"valid":false}
			var bounds:=_bounds(polygon)
			footprint=footprint.merge(bounds) if has_bounds else bounds;has_bounds=true
			moving.append({"polygon":polygon,"bounds":bounds})
	if moving.is_empty():return {"valid":false}
	var geometry:=_world_geometry(game)
	var min_x:float=geometry.left-footprint.position.x
	var max_x:float=geometry.right-footprint.end.x
	if min_x>max_x:return {"valid":false,"reason":"shape_wider_than_world"}
	var state:Dictionary={"heap":[],"visited":{},"seen":{},"regions":[],"min_x":min_x,"max_x":max_x}
	var virtual:Array=[]
	for polygon in geometry.polygons:virtual.append({"polygon":polygon,"bounds":_bounds(polygon)})
	_enqueue(state,Vector2.ZERO)
	var queries:=0
	while not state.heap.is_empty():
		var offset:=_pop(state)
		var blocked:=false
		for region in state.regions:
			if region.bounds.has_point(offset) and _strictly_inside(offset,region.polygon):blocked=true;break
		if blocked:continue
		queries+=1
		var count:int=state.seen.size()
		var batch:Array=[]
		var hits:=_contacts(game,node,offset)
		for hit in hits:
			var id:=str(hit.collider_id)+":"+str(hit.shape)+":"+str(hit.moving_fixture.get_instance_id())
			var parts:Array=by_fixture[hit.moving_fixture.get_instance_id()]
			var obstacles:=_hit_parts(hit)
			for a in parts.size():
				for b in obstacles.size():_collect_region(state,batch,parts[a],obstacles[b],id+":"+str(a)+":"+str(b))
		for i in moving.size():
			var part:Dictionary=moving[i]
			var moved_bounds:=Rect2(part.bounds.position+offset,part.bounds.size)
			for j in virtual.size():
				var obstacle:Dictionary=virtual[j]
				if not moved_bounds.intersects(obstacle.bounds):continue
				var translated:PackedVector2Array=part.polygon.duplicate()
				for k in translated.size():translated[k]+=offset
				if Geometry2D.intersect_polygons(translated,obstacle.polygon).is_empty():continue
				blocked=true
				_collect_region(state,batch,part.polygon,obstacle.polygon,"soil:"+str(i)+":"+str(j))
		if hits.is_empty() and not blocked:return {"valid":true,"offset":offset,"queries":queries}
		_add_batch(state,batch)
		# No arbitrary search radius, build-range filter, or attempt count. Every
		# collision adds finite boundary candidates; invalid geometry alone fails.
		if state.seen.size()==count and state.heap.is_empty():break
	return {"valid":false,"reason":"no_geometric_exit"}
