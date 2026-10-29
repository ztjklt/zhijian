class_name MedievalWalkSurfaces
extends RefCounted
## Walkable ink is deliberately separate from a building's damage silhouette.
const Castle := preload("res://scripts/medieval_castle_layout.gd")
const Catalog := preload("res://scripts/medieval_catalog.gd")
const CollisionLifetime := preload("res://scripts/collision_lifetime.gd")
static func authored(entity) -> Array:
	var w: float = entity.size.x
	var h: float = entity.size.y
	var edges: Array = []
	if Catalog.has_kind(entity.kind):
		for e in Catalog.walk_edges(entity.kind):
			var a := Vector2(e[0]*w,e[1]*h)
			var b := Vector2(e[2]*w,e[3]*h)
			edges.append([a,b])
		return edges
	match entity.kind:
		"house":
			edges = [[Vector2(-1.15,.58),Vector2(-.5,.58)],[Vector2(-1.75,1.37),Vector2(1.8,1.37)],[Vector2(.32,1.5),Vector2(1.18,1.5)],[Vector2(-2.1,1.42),Vector2(.95,3.4)],[Vector2(.95,3.4),Vector2(2.1,1.42)]]
		"oak": edges = [[Vector2(-1.45,2.1),Vector2(-.7,2.7)],[Vector2(-.7,2.7),Vector2(.65,2.7)],[Vector2(.65,2.7),Vector2(1.45,2.1)]]
		"pine": edges = [[Vector2(-1,1.98),Vector2(1,1.98)],[Vector2(-.76,2.95),Vector2(.76,2.95)],[Vector2(-.43,3.87),Vector2(.43,3.87)]]
		"market": edges = [[Vector2(-1.6,.9),Vector2(1.6,.9)],[Vector2(-1.75,2.1),Vector2(-1.3,2.54)],[Vector2(-1.3,2.54),Vector2(1.3,2.54)],[Vector2(1.3,2.54),Vector2(1.75,2.1)]]
		"tower": edges = [[Vector2(-w*.5,1.15),Vector2(w*.5,1.15)],[Vector2(-w*.5,2.4),Vector2(w*.5,2.4)],[Vector2(-w*.5,3.65),Vector2(w*.5,3.65)],[Vector2(-w*.5,h),Vector2(w*.5,h)]]
		"castle_piece": return castle_edges(entity)
		"wall","gate","barrel","crate","wagon": edges = [[Vector2(-w*.48,h),Vector2(w*.48,h)]]
	return edges
static func castle_edges(entity) -> Array:
	var result: Array = []
	# These lines trace the master concept's base mouldings, window sills,
	# balconies, battlements and roofs; no tile seam becomes an invisible floor.
	var routes := [
		[22,854,305,854],[39,720,291,720],[48,622,291,622],[48,496,291,496],[32,420,313,420],[31,329,313,329],[48,310,275,310],
		[1230,854,1510,854],[1245,720,1498,720],[1245,622,1494,622],[1245,496,1481,496],[1217,420,1503,420],[1217,329,1503,329],[1255,311,1486,311],
		[282,836,533,836],[999,836,1253,836],[291,668,535,668],[1000,668,1245,668],[291,590,535,590],[1000,591,1245,591],
		[535,800,650,800],[885,800,1000,800],[535,666,650,666],[885,666,1000,666],[518,559,1017,559],[519,513,1017,513],
		[583,466,952,466],[584,420,952,420],[584,402,659,402],[875,402,952,402],[578,316,667,316],[870,315,961,315],
		[678,302,858,302],[698,257,768,96],[768,96,839,257],[578,316,622,215],[622,215,667,316],[870,315,915,215],[915,215,961,317]]
	var bounds := Rect2(Vector2(-entity.size.x*.5,0),entity.size)
	for route in routes:
		var a: Vector2 = Castle.project_pixel(Vector2(route[0],route[1]))-entity.position
		var b: Vector2 = Castle.project_pixel(Vector2(route[2],route[3]))-entity.position
		var delta := b-a
		var lo := 0.0
		var hi := 1.0
		for axis in 2:
			if absf(delta[axis]) < .00001:
				if a[axis] < bounds.position[axis]-.001 or a[axis] > bounds.end[axis]+.001: hi = -1
			else:
				var first: float = (bounds.position[axis]-a[axis])/delta[axis]
				var last: float = (bounds.end[axis]-a[axis])/delta[axis]
				lo = maxf(lo,minf(first,last)); hi = minf(hi,maxf(first,last))
		if hi-lo > .0001: result.append([a+delta*lo,a+delta*hi])
	return result
static func remaining(entity) -> Array:
	if not entity.alive or entity.is_actor(): return []
	var result: Array = []
	for edge in authored(entity):
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var delta := b-a
		var breaks: Array[float] = [0.0,1.0]
		for cut in entity.cuts:
			var chip: PackedVector2Array = entity._cut_polygon(cut)
			for i in chip.size():
				var hit = Geometry2D.segment_intersects_segment(a,b,chip[i],chip[(i+1)%chip.size()])
				if hit != null: breaks.append(clampf((hit-a).dot(delta)/delta.length_squared(),0,1))
		breaks.sort()
		for i in range(breaks.size()-1):
			var start: Vector2 = a+delta*breaks[i]
			var end: Vector2 = a+delta*breaks[i+1]
			if start.distance_to(end) < .025: continue
			var removed := false
			for cut in entity.cuts:
				if Geometry2D.is_point_in_polygon((start+end)*.5,entity._cut_polygon(cut)): removed = true; break
			if not removed: result.append([start,end])
	return result
static func rebuild(entity) -> void:
	for child in entity.get_children():
		if child is StaticBody2D and child.has_meta("medieval_owner"):
			entity.remove_child(child)
			child.queue_free()
	for edge in remaining(entity):
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		if a.x > b.x:
			var swap := a; a = b; b = swap
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("map_drop_allowed",true)
		body.set_meta("medieval_owner",entity)
		body.set_meta("walk_edge_a",a)
		body.set_meta("walk_edge_b",b)
		var fixture := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(a.distance_to(b),.06)
		fixture.shape = shape
		fixture.rotation = (b-a).angle()+PI
		var normal := Vector2(-(b-a).y,(b-a).x).normalized()
		fixture.position = (a+b)*.5-normal*.03
		fixture.one_way_collision = true
		fixture.one_way_collision_margin = .06
		body.add_child(fixture)
		entity.add_child(body)
		var world = entity.get_parent()
		if world != null and world.get("entities") is Array:
			for actor in world.entities:
				if is_instance_valid(actor) and actor.is_actor() and actor.kind not in ["king","queen"]:
					CollisionLifetime.add(actor,body)

static func configure_actor(actor) -> void:
	if not actor.is_actor() or actor.kind in ["king","queen"]: return
	var world = actor.get_parent()
	if world == null or not world.get("entities") is Array: return
	for entity in world.entities:
		if not is_instance_valid(entity): continue
		for body in entity.get_children():
			if body is StaticBody2D and body.has_meta("medieval_owner"): CollisionLifetime.add(actor,body)

static func register_surfaces(entity) -> void:
	# setup() runs before the entity is parented; register existing patrols after
	# entering the world as well as during later damage rebuilds.
	var world = entity.get_parent()
	if world == null or not world.get("entities") is Array: return
	for body in entity.get_children():
		if not body is StaticBody2D or not body.has_meta("medieval_owner"): continue
		for actor in world.entities:
			if is_instance_valid(actor) and actor.is_actor() and actor.kind not in ["king","queen"]:
				CollisionLifetime.add(actor,body)
