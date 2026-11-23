class_name MedievalTerrain
extends RefCounted
## One world-space profile drives paper ink, solid soil, spawns and weapon contacts.
const EastInk := preload("res://scripts/medieval_east_ink.gd")
const VERSION := 3
const LEGACY_FLOOR := -2.8
const BOTTOM := -14.0
const WATER_Y := -1.6
const WATER_LEFT := 55.5
const WATER_RIGHT := 63.9
const BRIDGE_LEFT := Vector2(54,-0.6)
const BRIDGE_RIGHT := Vector2(68,3.4)
const MILL_WATER_Y := 0.6
const MILL_WATER_LEFT := 129.0
const MILL_WATER_RIGHT := 139.0
const ROAD_DECKS := [[BRIDGE_LEFT,BRIDGE_RIGHT],[Vector2(128,2.8),Vector2(140,1.8)]]
const WATER_ZONES := [{"left":WATER_LEFT,"right":WATER_RIGHT,"height":WATER_Y},{"left":MILL_WATER_LEFT,"right":MILL_WATER_RIGHT,"height":MILL_WATER_Y}]
const INK := Color(0.055,0.045,0.035,0.88)
static var VERSION2_PROFILE := PackedVector2Array([Vector2(-5,-2.8),Vector2(0,-2.8),Vector2(3,-2.2),Vector2(7,-0.2),Vector2(10,0.4),Vector2(14,-1.2),Vector2(18,-2.0),Vector2(20,-1.2),Vector2(37,-1.2),Vector2(40,-0.6),Vector2(54,-0.6),Vector2(55,-1),Vector2(57,-3.4),Vector2(59,-4.3),Vector2(61,-4.3),Vector2(63,-3.4),Vector2(64,-1.4),Vector2(68,3.4),Vector2(88,3.4),Vector2(92,4.3),Vector2(97,6.2),Vector2(104,5.2),Vector2(108,2.8),Vector2(124,2.8),Vector2(128,2.8),Vector2(130,-0.8),Vector2(134,-1.4),Vector2(138,-0.8),Vector2(140,1.8),Vector2(144,2.8),Vector2(147,4.6),Vector2(160,4.6),Vector2(164,2.4),Vector2(180,2.4),Vector2(185,2.4)])
var profile := PackedVector2Array([Vector2(-5,13),Vector2(0,10),Vector2(3,8.2),Vector2(6,6.4),Vector2(9,6.0),Vector2(12,4.5),Vector2(15,1.8),Vector2(18,-0.2),Vector2(20,-1.2),Vector2(37,-1.2),Vector2(40,-0.6),Vector2(54,-0.6),Vector2(55,-1),Vector2(57,-3.4),Vector2(59,-4.3),Vector2(61,-4.3),Vector2(63,-3.4),Vector2(64,-1.4),Vector2(68,3.4),Vector2(88,3.4),Vector2(91,4.4),Vector2(94,6.8),Vector2(97,6.2),Vector2(101,7.4),Vector2(104,5.2),Vector2(108,2.8),Vector2(124,2.8),Vector2(128,2.8),Vector2(130,-0.8),Vector2(134,-1.4),Vector2(138,-0.8),Vector2(140,1.8),Vector2(144,2.8),Vector2(147,4.6),Vector2(160,4.6),Vector2(164,8.4),Vector2(179,8.4),EastInk.ORIGINAL_EDGE])
var collision_geometry: Array = []
var paper_space
var ripples: Array = []
var _wet_bodies := {}
var _physics_built := false
var _soil_count := 0
var _base_profile_size := 0
var _east_soil: StaticBody2D
var east_ink := EastInk.new()
var elapsed := 0.0
var bridge_ink := {}
var east_ground_wash := preload("res://scripts/east_ground_wash.gd").new()

func _init() -> void:
	_base_profile_size = profile.size()
	for i in range(1,profile.size()):
		var a:=profile[i-1]; var b:=profile[i]
		collision_geometry.append(PackedVector2Array([a,b,Vector2(b.x,BOTTOM),Vector2(a.x,BOTTOM)]))
	_soil_count = collision_geometry.size()
	# Both crossings share the same road/physics/drawing coordinates.
	for deck in ROAD_DECKS:
		var a:Vector2=deck[0];var b:Vector2=deck[1]
		var normal:=Vector2(-(b-a).y,(b-a).x).normalized()
		collision_geometry.append(PackedVector2Array([a,b,b-normal*0.18,a-normal*0.18]))

static func profile_height(points:PackedVector2Array,x:float)->float:
	x=clampf(x,points[0].x,points[-1].x)
	var i:=profile_span(points,x)
	var a:=points[i-1]
	var b:=points[i]
	return lerpf(a.y,b.y,(x-a.x)/(b.x-a.x))

static func profile_span(points:PackedVector2Array,x:float) -> int:
	var lo:=1
	var hi:=points.size()-1
	while lo<hi:
		var mid:int=(lo+hi)/2
		if points[mid].x<x:lo=mid+1
		else:hi=mid
	return lo

func surface_height(x: float) -> float:
	return profile_height(profile,x)

func upgrade_position(at:Vector2,from_version:int)->Vector2:
	if from_version>=VERSION:return at
	var before:=LEGACY_FLOOR if from_version==1 else profile_height(VERSION2_PROFILE,at.x)
	if from_version==2:
		for deck in ROAD_DECKS:
			var a:Vector2=deck[0];var b:Vector2=deck[1]
			if at.x>=a.x and at.x<=b.x:before=maxf(before,lerpf(a.y,b.y,(at.x-a.x)/(b.x-a.x)))
	return at+Vector2(0,travel_height(at.x)-before)

func travel_height(x: float) -> float:
	var height:=surface_height(x)
	for deck in ROAD_DECKS:
		var a:Vector2=deck[0];var b:Vector2=deck[1]
		if x>=a.x and x<=b.x: height=maxf(height,lerpf(a.y,b.y,(x-a.x)/(b.x-a.x)))
	return height

# Ground-root placement follows actual transformed lower contacts. Buildings
# are authored only on level plots; small props use this full footprint pose.
func prop_pose(x: float,half_width: float,contact_y: float=0.0) -> Dictionary:
	return support_pose(x,half_width,contact_y)

func _ink_contact_height(x:float,angle:float,contacts:PackedVector2Array) -> float:
	var height:=-INF
	for point in contacts:
		var p:=point.rotated(angle)
		height=maxf(height,travel_height(x+p.x)-p.y)
	return height

func ink_prop_pose(x:float,contacts:PackedVector2Array,half_width:float) -> Dictionary:
	if contacts.size()<2:return prop_pose(x,half_width)
	var left:=PackedVector2Array();var right:=PackedVector2Array()
	for point in contacts:
		if point.x<=0:left.append(point)
		else:right.append(point)
	var angle:float=prop_pose(x,half_width).rotation
	if not left.is_empty() and not right.is_empty():
		var low:=-1.1;var high:=1.1
		var low_gap:=_ink_contact_height(x,low,left)-_ink_contact_height(x,low,right)
		var high_gap:=_ink_contact_height(x,high,left)-_ink_contact_height(x,high,right)
		if low_gap*high_gap<=0:
			for iteration in 18:
				var middle:float=(low+high)*0.5
				var gap:=_ink_contact_height(x,middle,left)-_ink_contact_height(x,middle,right)
				if gap*low_gap<=0:high=middle
				else:low=middle;low_gap=gap
			angle=(low+high)*0.5
	return {"position_y":_ink_contact_height(x,angle,contacts),"rotation":angle}

func support_height(x: float, half_width: float = 0.0, travel: bool = true) -> float:
	var height := travel_height(x) if travel else surface_height(x)
	for offset in [-half_width,half_width]:
		height=maxf(height,travel_height(x+offset) if travel else surface_height(x+offset))
	return height

func support_pose(x: float,half_width: float,feet_height: float=0.0) -> Dictionary:
	var angle:=0.0
	var left:=0.0
	var right:=0.0
	for i in 5:
		var dx:=half_width*cos(angle)
		var offset:float=-feet_height*sin(angle)
		left=travel_height(x-dx+offset)
		right=travel_height(x+dx+offset)
		angle=atan2(right-left,maxf(0.001,2*dx))
	var y:float=(left+right)*0.5-feet_height*cos(angle)
	# A rigid cart can rock over a ridge; its actual lower edge never buries in it.
	for i in 7:
		var local:=Vector2(lerpf(-half_width,half_width,float(i)/6),feet_height).rotated(angle)
		y=maxf(y,travel_height(x+local.x)-local.y)
	return {"position_y":y,"rotation":angle}

# Measured outer lower arcs in the original 1774×887 wagon PNG. Unlike the
# 3m image rectangle, these contacts exclude the long raised towing shaft.
const WAGON_WHEEL_ROWS := [
	[[611,962,600],[643,928,700],[680,887,740],[714,850,760],[745,817,770],[762,798,773]],
	[[1349,1711,600],[1379,1677,700],[1417,1638,740],[1450,1606,760],[1475,1581,770],[1495,1561,775],[1524,1533,778]]]
static var _wagon_shapes := {}

static func _wagon_pixel(pixel: Vector2,source: Rect2,size: Vector2,facing: int) -> Vector2:
	var uv:Vector2=(pixel-source.position)/source.size
	return Vector2((0.5-uv.x if facing>0 else uv.x-0.5)*size.x,(1-uv.y)*size.y)

static func _wagon_polygon(pixels: Array,source: Rect2,size: Vector2,facing: int) -> PackedVector2Array:
	var polygon:=PackedVector2Array()
	for pixel in pixels: polygon.append(_wagon_pixel(pixel,source,size,facing))
	if Geometry2D.is_polygon_clockwise(polygon):polygon.reverse()
	return polygon

static func wagon_geometry(source: Rect2,size: Vector2,facing: int) -> Array:
	var key:=str(source)+str(size)+str(facing)
	if _wagon_shapes.has(key):return _wagon_shapes[key].duplicate()
	var shapes:Array=[]
	for rows in WAGON_WHEEL_ROWS:
		var pixels:Array=[]
		for row in rows:pixels.append(Vector2(row[0],row[2]))
		for i in range(rows.size()-1,-1,-1):pixels.append(Vector2(rows[i][1],rows[i][2]))
		shapes.append(_wagon_polygon(pixels,source,size,facing))
	shapes.append(_wagon_polygon([Vector2(610,190),Vector2(1740,190),Vector2(1740,580),Vector2(610,580)],source,size,facing))
	shapes.append(_wagon_polygon([Vector2(38,430),Vector2(160,446),Vector2(620,457),Vector2(635,510),Vector2(160,478),Vector2(38,456)],source,size,facing))
	_wagon_shapes[key]=shapes
	# Entity destruction clears its own polygons; it must not clear this cache.
	return shapes.duplicate()

func _wheel_support_y(x: float,angle: float,polygon: PackedVector2Array,knots: Array) -> float:
	var required:=-INF
	for i in polygon.size():
		var a:Vector2=polygon[i].rotated(angle)
		var b:Vector2=polygon[(i+1)%polygon.size()].rotated(angle)
		required=maxf(required,travel_height(x+a.x)-a.y)
		if absf(b.x-a.x)<0.000001:continue
		# A ridge may touch the middle of a wheel edge rather than a vertex.
		for knot:float in knots:
			var t:float=(knot-x-a.x)/(b.x-a.x)
			if t>0 and t<1:
				required=maxf(required,travel_height(knot)-lerpf(a.y,b.y,t))
	return required

func wagon_pose(x: float,source: Rect2,size: Vector2,facing: int) -> Dictionary:
	var wheels:=wagon_geometry(source,size,facing)
	var knots:Array=[]
	for p in profile:
		if absf(p.x-x)<size.x:knots.append(p.x)
	for edge in [BRIDGE_LEFT.x,BRIDGE_RIGHT.x,128.0,140.0]:
		if absf(edge-x)<size.x and not knots.has(edge):knots.append(edge)
	var low:=-1.1
	var high:=1.1
	var low_gap:=_wheel_support_y(x,low,wheels[0],knots)-_wheel_support_y(x,low,wheels[1],knots)
	for i in 18:
		var angle:float=(low+high)*0.5
		var gap:=_wheel_support_y(x,angle,wheels[0],knots)-_wheel_support_y(x,angle,wheels[1],knots)
		if gap*low_gap<=0:high=angle
		else:low=angle;low_gap=gap
	var angle:float=(low+high)*0.5
	return {"position_y":maxf(_wheel_support_y(x,angle,wheels[0],knots),_wheel_support_y(x,angle,wheels[1],knots)),"rotation":angle}

func _add_east_fixture(polygon: PackedVector2Array) -> void:
	var fixture := CollisionPolygon2D.new()
	fixture.polygon = polygon
	_east_soil.add_child(fixture)

func _append_east_contour(contour: PackedVector2Array) -> void:
	# Start on the actual committed endpoint. One pair of points supplies the
	# visible line, the physical top edge and all height/contact queries.
	for i in range(1, contour.size()):
		var a := profile[-1]
		var b := contour[i]
		_extend_face(a, b, true)

func _extend_face(a: Vector2, b: Vector2, new_face: bool) -> void:
	var face := PackedVector2Array([a, b, Vector2(b.x, BOTTOM), Vector2(a.x, BOTTOM)])
	if new_face:
		profile.append(b)
		collision_geometry.append(face)
		if _east_soil != null:
			_add_east_fixture(face)
	else:
		# Grow the current soil face under the pen. There is one physics shape
		# per authored span, independent of rendering or simulation frame rate.
		profile[-1] = b
		collision_geometry[-1] = face
		if _east_soil != null:
			var fixture := _east_soil.get_child(-1) as CollisionPolygon2D
			fixture.polygon = face

	if paper_space!=null:paper_space.legacy_changed(Rect2(Vector2(a.x,BOTTOM),Vector2(b.x-a.x,maxf(a.y,b.y)-BOTTOM)))

func advance_east_nib(nib: Vector2, hand: Vector2, reach: float) -> bool:
	var update := east_ink.advance_nib(nib, hand, reach)
	if update.is_empty():
		return false
	if update.ground:
		_extend_face(update.start, update.tip, update.new_face)
	return true

func restore_east_segments(saved: Array) -> void:
	if saved == east_ink.segments and east_ink.pending.is_empty():
		return
	if _east_soil != null:
		for fixture in _east_soil.get_children():
			_east_soil.remove_child(fixture)
			fixture.queue_free()
	east_ground_wash.clear()
	profile.resize(_base_profile_size)
	collision_geometry.resize(_soil_count + ROAD_DECKS.size())
	east_ink.restore(saved)
	for drawing in east_ink.drawings:
		_append_east_contour(drawing.contour)
	_append_east_contour(east_ink.worked_contour())

func build_physics(parent: Node2D) -> void:
	if _physics_built: return
	_physics_built=true
	var soil:=StaticBody2D.new()
	soil.name="MountainRiverSoil"
	soil.set_meta("terrain_profile", get_instance_id())
	soil.collision_layer=1
	soil.collision_mask=3
	soil.set_meta("map_drop_allowed",false)
	for polygon in collision_geometry.slice(0,_soil_count):
		var fixture:=CollisionPolygon2D.new()
		fixture.polygon=polygon
		soil.add_child(fixture)
	parent.add_child(soil)
	_east_soil = StaticBody2D.new()
	_east_soil.name = "EastInkSoil"
	_east_soil.set_meta("terrain_profile", get_instance_id())
	_east_soil.collision_layer = 1
	_east_soil.collision_mask = 3
	_east_soil.set_meta("map_drop_allowed", false)
	for i in range(_soil_count + ROAD_DECKS.size(), collision_geometry.size()):
		_add_east_fixture(collision_geometry[i])
	parent.add_child(_east_soil)
	for index in ROAD_DECKS.size():
		var a:Vector2=ROAD_DECKS[index][0];var b:Vector2=ROAD_DECKS[index][1]
		var bridge:=StaticBody2D.new()
		bridge.name="TimberBridge" if index==0 else "MillRiverCrossing"
		bridge.collision_layer=1
		bridge.collision_mask=3
		bridge.set_meta("map_drop_allowed",true)
		var delta:=b-a
		var normal:=Vector2(-delta.y,delta.x).normalized()
		bridge.position=(a+b)*0.5-normal*0.09
		var deck:=CollisionShape2D.new()
		var shape:=RectangleShape2D.new()
		shape.size=Vector2(delta.length(),0.18)
		deck.rotation=delta.angle()+PI
		deck.shape=shape
		deck.one_way_collision=true
		deck.one_way_collision_margin=0.04
		bridge.add_child(deck)
		parent.add_child(bridge)

func step(delta: float) -> void:
	if not east_ink.pending.is_empty() and not east_ink.actor_driven:
		var contour: PackedVector2Array = east_ink.advance(delta)
		if not contour.is_empty():
			_append_east_contour(contour)
	elapsed+=delta
	for ripple in ripples: ripple.age+=delta
	ripples=ripples.filter(func(ripple):return ripple.age<1.2)
	for id in _wet_bodies.keys():
		var body=_wet_bodies[id].get_ref()
		if body==null or not in_water(body.position): _wet_bodies.erase(id)

func water_surface(point: Vector2) -> float:
	if paper_space!=null:
		var water:float=paper_space.water_surface(point)
		if is_finite(water):return water
	for zone in WATER_ZONES:
		if point.x>zone.left and point.x<zone.right and point.y<zone.height+0.2 and point.y>surface_height(point.x)-0.4:return zone.height
	return -INF

func in_water(point: Vector2) -> bool:
	return water_surface(point)>-INF

func apply_water_body(body: RigidBody2D,delta: float) -> void:
	if body==null or body.freeze or not in_water(body.position) or not is_finite(delta) or delta<=0: return
	delta=minf(delta,0.1)
	var height:=water_surface(body.position)
	var submerged:=clampf((height-body.position.y+0.25)/0.9,0,1)
	body.linear_velocity.x*=exp(-1.9*submerged*delta)
	body.linear_velocity.y=body.linear_velocity.y*exp(-1.1*submerged*delta)+22.0*submerged*delta
	var id:=body.get_instance_id()
	if not _wet_bodies.has(id):
		_wet_bodies[id]=weakref(body)
		if ripples.size()>=24: ripples.pop_front()
		ripples.append({"x":body.position.x,"y":height,"age":0.0})

# Keep marks on the few folds of the original dry slope where the grade changes.
# The flat stretches stay open and the playable outline remains the darkest line.
func _draw_dry_folds(canvas: Node2D, game, left: float, right: float) -> void:
	for i in range(maxi(1, profile_span(profile, left) - 1), mini(_base_profile_size - 1, profile_span(profile, right) + 1)):
		var shoulder := profile[i]
		var incoming := shoulder - profile[i - 1]
		var outgoing := profile[i + 1] - shoulder
		var before := incoming.y / incoming.x
		var after := outgoing.y / outgoing.x
		if absf(before - after) < 0.52:
			continue
		var side := -1.0 if absf(before) > absf(after) else 1.0
		for mark in 2:
			var x := shoulder.x + side * (0.24 + mark * 0.36)
			if (x >= WATER_LEFT and x <= WATER_RIGHT) or (x >= MILL_WATER_LEFT and x <= MILL_WATER_RIGHT):
				continue
			var end_x := x + side * (0.26 - mark * 0.09)
			var a := Vector2(x, surface_height(x) - 0.14 - mark * 0.08)
			var b := Vector2(end_x, surface_height(end_x) - 0.26 - mark * 0.04)
			if paper_space != null and not paper_space.modified_legacy.is_empty():
				if not paper_space.solid_at(a) or not paper_space.solid_at(b):
					continue
			canvas.draw_line(game.world_to_screen(a), game.world_to_screen(b), Color(0.41, 0.31, 0.20, 0.26 - mark * 0.07), 1.0, true)

# Project each submerged stretch of the real bed up to its own level. The ends
# are clipped to both the profile and the original river's horizontal bounds.
func _draw_village_river(canvas: Node2D, game, zone: Dictionary) -> void:
	var level: float = zone.height
	var shallow := Color(0.26, 0.46, 0.48, 0.12)
	var deep := Color(0.25, 0.40, 0.54, 0.28)
	for i in range(profile_span(profile, zone.left), profile_span(profile, zone.right) + 1):
		var x0 := maxf(profile[i - 1].x, zone.left)
		var x1 := minf(profile[i].x, zone.right)
		var a := Vector2(x0, surface_height(x0))
		var b := Vector2(x1, surface_height(x1))
		if x1 <= x0 or minf(a.y, b.y) >= level:
			continue
		if a.y > level:
			a = a.lerp(b, (level - a.y) / (b.y - a.y))
		elif b.y > level:
			b = b.lerp(a, (level - b.y) / (a.y - b.y))
		var vertices := PackedVector2Array([game.world_to_screen(Vector2(a.x, level)), game.world_to_screen(Vector2(b.x, level))])
		var shades := PackedColorArray([shallow, shallow])
		for bed in [b, a]:
			var depth: float = level - bed.y
			if depth > 0.0001:
				vertices.append(game.world_to_screen(bed))
				shades.append(shallow.lerp(deep, clampf(depth / 2.1, 0.0, 1.0)))
		if vertices.size() >= 3:
			canvas.draw_polygon(vertices, shades)
		canvas.draw_line(vertices[0], vertices[1], Color(0.21, 0.36, 0.44, 0.56), 1.35, true)

	# Short, separated surface strokes leave paper showing between reflections.
	for accent: Vector3 in [Vector3(0.13, 0.29, 0.11), Vector3(0.40, 0.48, 0.22), Vector3(0.58, 0.82, 0.13)]:
		var a := Vector2(lerpf(zone.left, zone.right, accent.x), level - accent.z)
		var b := Vector2(lerpf(zone.left, zone.right, accent.y), a.y)
		if minf(a.y - surface_height(a.x), b.y - surface_height(b.x)) <= 0.01:
			continue
		canvas.draw_line(game.world_to_screen(a), game.world_to_screen(b), Color(0.26, 0.43, 0.49, 0.28), 1.0, true)

func draw_world(canvas: Node2D,game) -> void:
	# Presentation-only bounds: distant water and bridge ink still keep their
	# physical bodies and continuous simulation, but submit no invisible lines.
	var left:float=game.screen_to_world(Vector2.ZERO).x-1.0
	var right:float=game.screen_to_world(Vector2(game.get_viewport_rect().size.x,0)).x+1.0
	east_ground_wash.draw(canvas,game,self,left,right)
	var smooth_ground := PackedVector2Array()
	for i in range(profile_span(profile,left),profile_span(profile,right)+1):
		var a:=profile[i-1];var b:=profile[i]
		if b.x<left or a.x>right:continue
		if paper_space!=null and not paper_space.modified_legacy.is_empty():
			for line in paper_space.legacy_line(a,b):canvas.draw_line(game.world_to_screen(line[0]),game.world_to_screen(line[1]),INK,1.8,true)
			continue
		if east_ink.expressive_at((a.x + b.x) * 0.5):
			if smooth_ground.is_empty():
				smooth_ground.append(game.world_to_screen(a))
			smooth_ground.append(game.world_to_screen(b))
		else:
			if smooth_ground.size() > 1:
				canvas.draw_polyline(smooth_ground, INK, 1.8, true)
				smooth_ground.clear()
			canvas.draw_line(game.world_to_screen(a),game.world_to_screen(b),INK,1.8,true)
	if smooth_ground.size() > 1:
		canvas.draw_polyline(smooth_ground, INK, 1.8, true)
	_draw_dry_folds(canvas, game, left, right)
	# Preserve the hatching on previously painted east sheets.
	for i in range(maxi(ceili(EastInk.ORIGINAL_EDGE.x),floori(left)),mini(ceili(profile[-1].x),ceili(right))):
		var x:=float(i)+0.2
		if x > profile[-1].x: continue
		var offset := Vector2(-0.28, -0.38)
		var depth := 0.16
		var graphite := Color(0.08,0.065,0.05,0.22)
		if east_ink.expressive_at(x):
			var rhythm := sin(i * 2.13)
			if rhythm < -0.1:
				continue
			depth = 0.10 + 0.11 * rhythm
			offset = Vector2(-0.15 - 0.07 * rhythm, -0.13 - 0.11 * rhythm)
			graphite.a = 0.12 + 0.035 * rhythm
		var a := Vector2(x, surface_height(x) - depth)
		if paper_space!=null and not paper_space.modified_legacy.is_empty() and not paper_space.solid_at(a):continue
		canvas.draw_line(game.world_to_screen(a), game.world_to_screen(a + offset), graphite, 1.0, true)
	east_ink.draw(canvas, game, left, right, INK)
	for zone in WATER_ZONES:
		if zone.right<left or zone.left>right:continue
		_draw_village_river(canvas, game, zone)
	for ripple in ripples:
		if ripple.x<left or ripple.x>right:continue
		var half:float=0.1+ripple.age*0.65
		canvas.draw_line(game.world_to_screen(Vector2(ripple.x-half,ripple.get("y",WATER_Y))),game.world_to_screen(Vector2(ripple.x+half,ripple.get("y",WATER_Y))),Color(0.04,0.035,0.03,(1-ripple.age/1.2)*0.65),1.5,true)
	for index in ROAD_DECKS.size():
		var a:Vector2=ROAD_DECKS[index][0];var b:Vector2=ROAD_DECKS[index][1]
		if b.x<left or a.x>right:continue
		if game.medieval_world != null and game.medieval_world.single_player_ink():
			var key := "west_crossing" if index == 0 else "mill_crossing"
			if not bridge_ink.has(key):
				bridge_ink[key] = load(preload("res://scripts/architecture/building_book.gd").BAKED + key + ".png")
			var top_left := Vector2(a.x, maxf(a.y,b.y)+.68)
			var size_m := Vector2(b.x-a.x, absf(b.y-a.y)+.88)
			canvas.draw_texture_rect(bridge_ink[key],Rect2(game.world_to_screen(top_left),size_m*game.PIXELS_PER_UNIT),false)
			continue
		var geometry:PackedVector2Array=collision_geometry[_soil_count+index]
		canvas.draw_line(game.world_to_screen(a),game.world_to_screen(b),INK,3.0,true)
		canvas.draw_line(game.world_to_screen(geometry[3]),game.world_to_screen(geometry[2]),INK,1.2,true)
		for i in 29:
			var p:=a.lerp(b,float(i)/28)
			var lower:=geometry[3].lerp(geometry[2],float(i)/28)
			canvas.draw_line(game.world_to_screen(p),game.world_to_screen(lower),INK,1.0,true)
		for i in 8:
			var p:=a.lerp(b,float(i)/7)
			canvas.draw_line(game.world_to_screen(p),game.world_to_screen(p+Vector2(0,0.65)),Color(0.08,0.065,0.05,0.75),1.4,true)
		canvas.draw_line(game.world_to_screen(a+Vector2(0,0.65)),game.world_to_screen(b+Vector2(0,0.65)),Color(0.08,0.065,0.05,0.6),1.1,true)
