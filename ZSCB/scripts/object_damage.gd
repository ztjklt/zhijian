class_name PaperObjectDamage
extends RefCounted
## Original paths stay intact for personal blueprints. All live geometry is
## derived from these bounded local cutouts, shared by display and collisions.
const MAX_CUTS := 16
const EPS := .000001
static func destructible(obj: Dictionary) -> bool:
	if obj.get("role","")=="weapon": return false
	if obj.get("role","")=="building": return true
	var physical_ladder:bool=obj.get("kind","")=="ladder" and obj.get("dynamic",true)
	for path in obj.get("paths",[]):
		if path.get("collision",true) or (physical_ladder and path.get("points",[]).size()>=2):return true
	return false
static func normalize(obj: Dictionary) -> void:
	if not destructible(obj):return
	obj.role="building"
	obj.dynamic=obj.get("dynamic",true)
	obj.max_health=obj.get("max_health",120.0)
	obj.health=obj.get("health",obj.max_health)
static func valid_cuts(value: Variant) -> bool:
	if not value is Array or value.size()>MAX_CUTS:return false
	for cut in value:
		if not cut is Dictionary:return false
		for key in ["x","y","r"]:
			var number:Variant=cut.get(key)
			if not (number is int or number is float) or not is_finite(float(number)):return false
		if absf(cut.x)>200 or absf(cut.y)>200 or cut.r<=0 or cut.r>.65:return false
	return true
static func add_cut(obj: Dictionary, world: Vector2, amount: float) -> void:
	var local:Vector2=(world-Vector2(obj.x,obj.y)).rotated(-float(obj.get("angle",0)))
	if not local.is_finite():return
	var cuts:Array=obj.get("damage_cuts",[]).duplicate(true)
	var radius:=clampf(.12+amount*.004,.14,.30)
	if cuts.size()<MAX_CUTS:cuts.append({"x":local.x,"y":local.y,"r":radius})
	else:
		var nearest:=0
		for i in cuts.size():
			if local.distance_squared_to(Vector2(cuts[i].x,cuts[i].y))<local.distance_squared_to(Vector2(cuts[nearest].x,cuts[nearest].y)):nearest=i
		cuts[nearest].r=minf(.65,cuts[nearest].r+radius*.35)
	obj.damage_cuts=cuts
static func _cutter(cut: Dictionary, index: int) -> PackedVector2Array:
	var polygon:=PackedVector2Array()
	for i in 12:polygon.append(Vector2(cut.x,cut.y)+Vector2.from_angle(TAU*i/12.0+index*.31)*cut.r)
	return polygon
static func _half(poly: PackedVector2Array, a: Vector2, b: Vector2, inside: bool) -> PackedVector2Array:
	var result:=PackedVector2Array()
	if poly.is_empty():return result
	var previous:Vector2=poly[-1]
	var previous_side:float=(b-a).cross(previous-a)*(1 if inside else -1)
	for point in poly:
		var side:float=(b-a).cross(point-a)*(1 if inside else -1)
		if (side>=-EPS)!=(previous_side>=-EPS):
			var divisor:=previous_side-side
			if absf(divisor)>EPS:result.append(previous.lerp(point,clampf(previous_side/divisor,0,1)))
		if side>=-EPS:result.append(point)
		previous=point;previous_side=side
	return result
static func _usable(poly: PackedVector2Array) -> bool:
	return poly.size()>=3 and PaperShapePhysics._polygon_properties(poly).area>.00001
static func _separated(a: PackedVector2Array,b: PackedVector2Array) -> bool:
	# Convex fixtures and cutters are counterclockwise. A separating edge
	# means no material intersects, so keep this fixture completely intact.
	for i in a.size():
		var edge:Vector2=a[(i+1)%a.size()]-a[i]
		var outside:=true
		for point in b:
			if edge.cross(point-a[i])>EPS:
				outside=false
				break
		if outside:return true
	return false
static func _subtract(poly: PackedVector2Array, cutter: PackedVector2Array) -> Array:
	if _separated(cutter,poly) or _separated(poly,cutter):return [poly]
	var result:Array=[]
	var remainder:=poly
	# Partition a convex polygon around each cutter half-plane. This supports
	# interior holes without mistaking a hole contour for a solid polygon.
	for i in cutter.size():
		var outside:=_half(remainder,cutter[i],cutter[(i+1)%cutter.size()],false)
		if _usable(outside):result.append(outside)
		remainder=_half(remainder,cutter[i],cutter[(i+1)%cutter.size()],true)
		if not _usable(remainder):break
	return result
static func _interval(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> Vector2:
	var lo:=0.0;var hi:=1.0
	for i in polygon.size():
		var edge:Vector2=polygon[(i+1)%polygon.size()]-polygon[i]
		var start:float=edge.cross(a-polygon[i])
		var slope:float=edge.cross(b-a)
		if absf(slope)<EPS:
			if start < -EPS:return Vector2.INF
		elif slope>0:lo=maxf(lo,-start/slope)
		else:hi=minf(hi,-start/slope)
		if lo>hi+EPS:return Vector2.INF
	return Vector2(clampf(lo,0,1),clampf(hi,0,1))
static func _outside(a: Vector2,b: Vector2,cutter: PackedVector2Array) -> Array:
	var interval:=_interval(a,b,cutter)
	if not interval.is_finite():return [[a,b]]
	var result:Array=[]
	if interval.x>EPS:result.append([a,a.lerp(b,interval.x)])
	if interval.y<1-EPS:result.append([a.lerp(b,interval.y),b])
	return result
static func _remaining(a: Vector2,b: Vector2,cutters: Array,skip: int=-1) -> Array:
	var pieces:Array=[[a,b]]
	for i in cutters.size():
		if i==skip:continue
		var next:Array=[]
		for piece in pieces:next.append_array(_outside(piece[0],piece[1],cutters[i]))
		pieces=next
	return pieces
static func _append_path(paths: Array,piece: Array) -> void:
	if piece[0].distance_squared_to(piece[1])<.000001:return
	if not paths.is_empty() and paths.back().points.back().is_equal_approx(piece[0]):paths.back().points.append(piece[1])
	else:paths.append({"points":[piece[0],piece[1]],"collision":true})
static func prepare(obj: Dictionary) -> Dictionary:
	var paths:Array=obj.get("paths",[])
	if obj.get("kind","")=="ladder" and obj.get("dynamic",true):
		paths=paths.duplicate(true)
		for path in paths:path.collision=true
	var physical:Array=paths
	if not obj.get("dynamic",true):
		physical=[]
		for path in paths:
			if not path.get("collision",true):continue
			for i in range(1,path.points.size()):physical.append({"points":[path.points[i-1],path.points[i]],"collision":true})
	var base:=PaperShapePhysics.prepare(physical)
	base.paths=paths
	var cuts:Array=obj.get("damage_cuts",[])
	if cuts.is_empty() or not valid_cuts(cuts):return base
	var cutters:Array=[]
	for i in cuts.size():cutters.append(_cutter(cuts[i],i))
	var shapes:Array=base.shapes
	for cutter in cutters:
		var next:Array=[]
		for shape in shapes:
			if shape.has("polygon"):
				for polygon in _subtract(shape.polygon,cutter):next.append({"polygon":polygon})
			else:
				for segment in _outside(shape.a,shape.b,cutter):
					if segment[0].distance_squared_to(segment[1])>.000001:next.append({"a":segment[0],"b":segment[1]})
		shapes=next
	var outlines:Array=[]
	for path in paths:
		if not path.get("collision",true):outlines.append(path);continue
		for i in range(1,path.points.size()):
			for piece in _remaining(path.points[i-1],path.points[i],cutters):_append_path(outlines,piece)
	# New cut rims are clipped to original solid material, then to the other
	# cutouts; no triangulation seams or lines across an original hollow appear.
	for index in cutters.size():
		var cutter:PackedVector2Array=cutters[index]
		for i in cutter.size():
			var a:Vector2=cutter[i];var b:Vector2=cutter[(i+1)%cutter.size()]
			for source in base.shapes:
				if not source.has("polygon"):continue
				var interval:=_interval(a,b,source.polygon)
				if not interval.is_finite():continue
				for piece in _remaining(a.lerp(b,interval.x),a.lerp(b,interval.y),cutters,index):_append_path(outlines,piece)
	var result:=_properties(shapes)
	result.paths=outlines
	return result
static func _properties(shapes: Array) -> Dictionary:
	var fills:Array=[];var parts:Array=[]
	for shape in shapes:
		if shape.has("polygon"):
			fills.append(shape.polygon)
			parts.append(PaperShapePhysics._polygon_properties(shape.polygon))
		else:
			var length:float=shape.a.distance_to(shape.b)
			var area:float=2*PaperShapePhysics.INK_RADIUS*length+PI*PaperShapePhysics.INK_RADIUS**2
			var mass:float=area*PaperShapePhysics.DENSITY
			parts.append({"mass":mass,"center":(shape.a+shape.b)*.5,"inertia":mass*length*length/12})
	var raw:=0.0;var weighted:=Vector2.ZERO
	for part in parts:raw+=part.mass;weighted+=part.center*part.mass
	var center:Vector2=weighted/maxf(raw,.00001)
	var moment:=0.0
	for part in parts:moment+=part.inertia+part.mass*part.center.distance_squared_to(center)
	var mass:=clampf(raw,.15,45)
	return {"shapes":shapes,"fills":fills,"center":center,"mass":mass,"inertia":maxf(.0001,moment*mass/maxf(raw,.00001))}
