extends Node2D
## Optional load test. The cargo moves by force and real contacts, never by a path.
const LEFT := 129.5
const RIGHT := 137.5
const DECK_Y := 5.2
const GOAL_X := 137.8
const START := Vector2(129.0,5.63)
const WHEEL_RADIUS := .18
const PHASES := ["idle","ready","running","failed","delivered"]
var world
var phase := "idle"
var attempt := 0
var completed := false
var parcel: RigidBody2D
var platforms: Array[StaticBody2D] = []
var geometry: Array[PackedVector2Array] = []
var settled := 0.0

func remote() -> bool:
	return world != null and world.game != null and world.game.get("network_session") != null

func _clear_at(rect: Rect2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0,rect.get_center())
	query.collision_mask = 1|2|8|64|128
	if is_instance_valid(parcel): query.exclude = [parcel.get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func prepare() -> Dictionary:
	if remote(): return {"ok":false,"error":"等待服务器布置试桥台"}
	if phase != "idle": return {"ok":false,"error":"试桥台已经布置好了"}
	for x in [LEFT,RIGHT]:
		if not _clear_at(Rect2(x-1.1,DECK_Y-.2,2.2,.2)):
			return {"ok":false,"error":"试桥台位置被占用，请先清出两端；原作品保留"}
	_build_stands()
	phase = "ready"
	return {"ok":true,"error":""}

func _build_stands() -> void:
	if not platforms.is_empty(): return
	for x in [LEFT,RIGHT]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 3
		body.position = Vector2(x,DECK_Y-.1)
		body.set_meta("map_drop_allowed",true)
		var fixture := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(2.2,.2)
		fixture.shape = shape
		fixture.rotation = PI
		fixture.one_way_collision = true
		fixture.one_way_collision_margin = .04
		body.add_child(fixture)
		add_child(body)
		platforms.append(body)
		var polygon := PackedVector2Array([Vector2(x-1.1,DECK_Y),Vector2(x+1.1,DECK_Y),Vector2(x+1.1,DECK_Y-.2),Vector2(x-1.1,DECK_Y-.2)])
		geometry.append(polygon)
		world.terrain.collision_geometry.append(polygon)

func start() -> Dictionary:
	if remote(): return {"ok":false,"error":"等待服务器投放货物"}
	if phase not in ["ready","failed","delivered"]:
		return {"ok":false,"error":"先布置试桥台，正在运输时不能重复投放"}
	if not _clear_at(Rect2(START-Vector2(.43,.41),Vector2(.86,.64))):
		return {"ok":false,"error":"货物起点被挡住了，请先留出空位；搭建保留"}
	_remove_parcel()
	attempt += 1
	settled = 0
	phase = "running"
	_make_parcel(START,Vector2.ZERO)
	return {"ok":true,"error":""}

func _make_parcel(at: Vector2, velocity: Vector2) -> void:
	parcel = RigidBody2D.new()
	parcel.position = at
	parcel.mass = .25
	parcel.lock_rotation = true
	parcel.linear_damp = .08
	parcel.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	parcel.collision_layer = 1
	parcel.collision_mask = 1|8|128
	parcel.contact_monitor = true
	parcel.max_contacts_reported = 8
	var material := PhysicsMaterial.new()
	material.friction = .2
	parcel.physics_material_override = material
	var chassis := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(.64,.42)
	chassis.shape = box
	parcel.add_child(chassis)
	for x in [-.24,.24]:
		var wheel := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = WHEEL_RADIUS
		wheel.shape = circle
		wheel.position = Vector2(x,-.22)
		parcel.add_child(wheel)
	add_child(parcel)
	parcel.linear_velocity = velocity
	if remote() or phase == "delivered":
		parcel.freeze = true
		parcel.collision_layer = 0
		parcel.collision_mask = 0

func _remove_parcel() -> void:
	if not is_instance_valid(parcel): parcel = null; return
	parcel.collision_layer = 0
	parcel.collision_mask = 0
	remove_child(parcel)
	parcel.queue_free()
	parcel = null

func step(delta: float) -> void:
	if remote() or phase != "running" or not is_instance_valid(parcel): return
	if not parcel.position.is_finite() or parcel.position.y < 4.05 or parcel.position.y > 20 or parcel.position.x < 125 or parcel.position.x > 145:
		phase = "failed"
		settled = 0
		_remove_parcel()
		return
	var contacts := parcel.get_colliding_bodies()
	if not contacts.is_empty():
		var desired := 0.0 if parcel.position.x >= GOAL_X else 1.05
		parcel.apply_central_force(Vector2(clampf((desired-parcel.linear_velocity.x)*40,-40,40)*parcel.mass,0))
	var on_goal := contacts.has(platforms[1]) and parcel.position.x >= RIGHT and parcel.linear_velocity.length() < .22
	settled = settled+delta if on_goal else 0.0
	if settled >= .5:
		phase = "delivered"
		completed = true
		parcel.linear_velocity = Vector2.ZERO
		parcel.freeze = true

func snapshot() -> Dictionary:
	var at := parcel.position if is_instance_valid(parcel) else START
	var velocity := parcel.linear_velocity if is_instance_valid(parcel) else Vector2.ZERO
	return {"version":1,"phase":phase,"attempt":attempt,"completed":completed,"x":at.x,"y":at.y,"vx":velocity.x,"vy":velocity.y}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	if data.get("version") != 1 or data.get("phase") not in PHASES or not data.get("completed") is bool: return false
	var number = data.get("attempt")
	if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > 1000000 or floorf(number) != float(number): return false
	if data.phase in ["running","failed","delivered"] and number < 1: return false
	if data.phase == "delivered" and not data.completed: return false
	for key in ["x","y","vx","vy"]:
		var value = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(value) > 1000: return false
	if data.x < 125 or data.x > 145 or data.y < 4.05 or data.y > 20: return false
	return true

func restore(data: Variant) -> bool:
	if not valid_state(data): return false
	_remove_parcel()
	for body in platforms:
		body.collision_layer = 0
		remove_child(body)
		body.queue_free()
	platforms.clear()
	for polygon in geometry: world.terrain.collision_geometry.erase(polygon)
	geometry.clear()
	var value: Dictionary = snapshot() if data.is_empty() else data
	if data.is_empty(): value = {"phase":"idle","attempt":0,"completed":false}
	phase = value.phase
	attempt = int(value.attempt)
	completed = value.completed
	settled = 0
	if phase != "idle": _build_stands()
	if phase in ["running","delivered"]: _make_parcel(Vector2(value.x,value.y),Vector2(value.vx,value.vy))
	return true

func receive(data: Variant) -> bool:
	if not remote() or not valid_state(data) or data.is_empty(): return false
	if (phase == "idle") != (data.phase == "idle"): return restore(data)
	if int(data.attempt) != attempt: _remove_parcel()
	phase = data.phase
	attempt = int(data.attempt)
	completed = data.completed
	if phase in ["running","delivered"]:
		if not is_instance_valid(parcel): _make_parcel(Vector2(data.x,data.y),Vector2.ZERO)
		parcel.position = Vector2(data.x,data.y)
	else: _remove_parcel()
	return true

func draw_world(canvas: Node2D, game) -> void:
	var left: Vector2 = game.world_to_screen(Vector2(LEFT,DECK_Y))
	var right: Vector2 = game.world_to_screen(Vector2(RIGHT,DECK_Y))
	if not Rect2(left-Vector2(140,120),right-left+Vector2(280,260)).intersects(canvas.get_viewport_rect()): return
	var ink := Color("3b3b34")
	var teal := Color("376f65")
	if phase == "idle":
		canvas.draw_string(ThemeDB.fallback_font,left+Vector2(-30,-22),"可选 · 磨坊试桥",HORIZONTAL_ALIGNMENT_LEFT,-1,15,teal)
		return
	for polygon in geometry:
		var points := PackedVector2Array()
		for p in polygon: points.append(game.world_to_screen(p))
		canvas.draw_colored_polygon(points,Color("e4dfcc"))
		points.append(points[0]);canvas.draw_polyline(points,ink,2,true)
	canvas.draw_line(right+Vector2(22,0),right+Vector2(22,-56),teal,2,true)
	canvas.draw_colored_polygon(PackedVector2Array([right+Vector2(22,-56),right+Vector2(53,-46),right+Vector2(22,-37)]),teal)
	canvas.draw_string(ThemeDB.fallback_font,left+Vector2(-25,-32),"起点",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
	canvas.draw_string(ThemeDB.fallback_font,right+Vector2(-25,-65),"送到这里",HORIZONTAL_ALIGNMENT_LEFT,-1,14,teal)
	if is_instance_valid(parcel):
		var points := PackedVector2Array()
		for p in [Vector2(-.32,-.21),Vector2(.32,-.21),Vector2(.32,.21),Vector2(-.32,.21),Vector2(-.32,-.21)]:points.append(game.world_to_screen(parcel.position+p))
		canvas.draw_colored_polygon(points.slice(0,4),Color("eee7d5"))
		canvas.draw_polyline(points,ink,2,true)
		canvas.draw_line(points[0],points[2],ink,1.5,true);canvas.draw_line(points[1],points[3],ink,1.5,true)
		for x in [-.24,.24]:
			var center: Vector2 = game.world_to_screen(parcel.position+Vector2(x,-.22))
			canvas.draw_circle(center,WHEEL_RADIUS*game.PIXELS_PER_UNIT,Color("faf7eb"))
			canvas.draw_arc(center,WHEEL_RADIUS*game.PIXELS_PER_UNIT,0,TAU,20,ink,2,true)
