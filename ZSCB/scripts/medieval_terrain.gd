class_name MedievalTerrain
extends RefCounted
## One world-space profile drives paper ink, solid soil, spawns and weapon contacts.
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
var profile := PackedVector2Array([Vector2(-5,13),Vector2(0,10),Vector2(3,8.2),Vector2(6,6.4),Vector2(9,6.0),Vector2(12,4.5),Vector2(15,1.8),Vector2(18,-0.2),Vector2(20,-1.2),Vector2(37,-1.2),Vector2(40,-0.6),Vector2(54,-0.6),Vector2(55,-1),Vector2(57,-3.4),Vector2(59,-4.3),Vector2(61,-4.3),Vector2(63,-3.4),Vector2(64,-1.4),Vector2(68,3.4),Vector2(88,3.4),Vector2(91,4.4),Vector2(94,6.8),Vector2(97,6.2),Vector2(101,7.4),Vector2(104,5.2),Vector2(108,2.8),Vector2(124,2.8),Vector2(128,2.8),Vector2(130,-0.8),Vector2(134,-1.4),Vector2(138,-0.8),Vector2(140,1.8),Vector2(144,2.8),Vector2(147,4.6),Vector2(160,4.6),Vector2(164,8.4),Vector2(179,8.4),Vector2(185,13.2)])
var collision_geometry: Array = []
var ripples: Array = []
var _wet_bodies := {}
var _physics_built := false
var _soil_count := 0
var elapsed := 0.0

func _init() -> void:
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
	for i in range(1,points.size()):
		if x<=points[i].x:
			var a:=points[i-1];var b:=points[i]
			return lerpf(a.y,b.y,(x-a.x)/(b.x-a.x))
	return points[-1].y

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

func build_physics(parent: Node2D) -> void:
	if _physics_built: return
	_physics_built=true
	var soil:=StaticBody2D.new()
	soil.name="MountainRiverSoil"
	soil.collision_layer=1
	soil.collision_mask=3
	soil.set_meta("map_drop_allowed",false)
	for polygon in collision_geometry.slice(0,_soil_count):
		var fixture:=CollisionPolygon2D.new()
		fixture.polygon=polygon
		soil.add_child(fixture)
	parent.add_child(soil)
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
	elapsed+=delta
	for ripple in ripples: ripple.age+=delta
	ripples=ripples.filter(func(ripple):return ripple.age<1.2)
	for id in _wet_bodies.keys():
		var body=_wet_bodies[id].get_ref()
		if body==null or not in_water(body.position): _wet_bodies.erase(id)

func water_surface(point: Vector2) -> float:
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

func draw_world(canvas: Node2D,game) -> void:
	# Presentation-only bounds: distant water and bridge ink still keep their
	# physical bodies and continuous simulation, but submit no invisible lines.
	var left:float=game.screen_to_world(Vector2.ZERO).x-1.0
	var right:float=game.screen_to_world(Vector2(game.get_viewport_rect().size.x,0)).x+1.0
	for i in range(1,profile.size()):
		var a:=profile[i-1];var b:=profile[i]
		if b.x<left or a.x>right:continue
		canvas.draw_line(game.world_to_screen(a),game.world_to_screen(b),INK,1.8,true)
	# Sparse pencil hatching stays just below the same physical surface.
	for i in range(maxi(-3,floori(left)),mini(185,ceili(right))):
		var x:=float(i)+0.2
		var a:=Vector2(x,surface_height(x)-0.16)
		var b:=a+Vector2(-0.28,-0.38)
		canvas.draw_line(game.world_to_screen(a),game.world_to_screen(b),Color(0.08,0.065,0.05,0.22),1.0,true)
	for zone in WATER_ZONES:
		if zone.right<left or zone.left>right:continue
		var water:=PackedVector2Array([game.world_to_screen(Vector2(zone.left,zone.height))])
		for p in profile:
			if p.x>zone.left and p.x<zone.right: water.append(game.world_to_screen(p))
		water.append(game.world_to_screen(Vector2(zone.right,zone.height)))
		canvas.draw_colored_polygon(water,Color(0.13,0.12,0.10,0.065))
		for row in 3:
			var line:=PackedVector2Array()
			for i in 43:
				var x:float=zone.left+float(i)*(zone.right-zone.left)/42
				line.append(game.world_to_screen(Vector2(x,zone.height-row*0.12+sin(x*4+elapsed*1.8+row)*0.025)))
			canvas.draw_polyline(line,Color(0.06,0.05,0.04,0.48 if row==0 else 0.2),1.1,true)
	for ripple in ripples:
		if ripple.x<left or ripple.x>right:continue
		var half:float=0.1+ripple.age*0.65
		canvas.draw_line(game.world_to_screen(Vector2(ripple.x-half,ripple.get("y",WATER_Y))),game.world_to_screen(Vector2(ripple.x+half,ripple.get("y",WATER_Y))),Color(0.04,0.035,0.03,(1-ripple.age/1.2)*0.65),1.5,true)
	for index in ROAD_DECKS.size():
		var a:Vector2=ROAD_DECKS[index][0];var b:Vector2=ROAD_DECKS[index][1]
		if b.x<left or a.x>right:continue
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
