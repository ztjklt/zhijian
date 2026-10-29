class_name PaperWallClimb
extends RefCounted

const SPEED := 2.8
# Slightly inside the 0.29 m body: existing contacts can penetrate by 0.005 m.
# The safety probe must allow that contact while the real body still collides.
const BODY_RADIUS := 0.27
var active := false
var side := 0
var _has_ledge := false
var _ledge := Vector2.ZERO
var _detach_time := 0.0
var _detach_side := 0

func reset(actor: RigidBody2D = null) -> void:
	active = false
	side = 0
	_has_ledge = false
	_detach_time = 0
	_detach_side = 0
	if actor != null: actor.gravity_scale = 1

func jump_off(actor: RigidBody2D) -> void:
	var away := -side
	reset(actor)
	_detach_side = away
	_detach_time = 0.18
	actor.linear_velocity = Vector2(away*4.6,7.8)

func _stop(actor: RigidBody2D) -> bool:
	active = false
	side = 0
	_has_ledge = false
	actor.gravity_scale = 1
	return false

func step(actor: RigidBody2D, direction: int, delta: float, enabled: bool = true) -> bool:
	if _detach_time > 0:
		_detach_time = maxf(0,_detach_time-delta)
		actor.linear_velocity.x = _detach_side*4.6
		return _stop(actor)
	if not enabled or direction == 0: return _stop(actor)
	if active and direction != side: _stop(actor)
	if _has_ledge:
		return _mantle(actor,delta)
	var wall: Dictionary = {}
	for height in [0.1,0.0,-0.16]:
		var start := actor.global_position+Vector2(0,height)
		var hit := _ray(actor,start,start+Vector2(direction*0.5,0))
		if not hit.is_empty() and hit.normal.x*direction < -0.7 and absf(hit.normal.y) < 0.45:
			wall = hit
			break
	if wall.is_empty(): return _stop(actor)
	if not _clear(actor,actor.global_position+Vector2(0,0.10)): return _stop(actor)
	active = true
	side = direction
	actor.gravity_scale = 0
	actor.sleeping = false
	# Detect a nearby top while there is still a vertical wall to climb against.
	var x := actor.global_position.x+direction*0.55
	var top := _ray(actor,Vector2(x,actor.global_position.y+0.9),Vector2(x,actor.global_position.y-0.24))
	if not top.is_empty() and top.normal.y > 0.65 and top.collider == wall.collider:
		var destination := Vector2(x,top.position.y+0.33)
		if _clear(actor,destination):
			_ledge = destination
			_has_ledge = true
			return _mantle(actor,delta)
	actor.linear_velocity = Vector2(direction*0.75,SPEED)
	return true

func _mantle(actor: RigidBody2D, delta: float) -> bool:
	var rise := _ledge.y-actor.global_position.y
	var desired := Vector2.ZERO
	if rise > 0.015:
		desired.y = minf(SPEED,rise/maxf(delta,0.001))
	elif absf(_ledge.x-actor.global_position.x) > 0.025:
		desired.x = signf(_ledge.x-actor.global_position.x)*minf(3.8,absf(_ledge.x-actor.global_position.x)/maxf(delta,0.001))
	else:
		return _stop(actor)
	if not _clear(actor,actor.global_position+desired*delta): return _stop(actor)
	active = true
	actor.gravity_scale = 0
	actor.linear_velocity = desired
	return true

func _excluded(actor: RigidBody2D) -> Array[RID]:
	var ignored: Array[RID] = [actor.get_rid()]
	for body in actor.get_collision_exceptions(): ignored.append(body.get_rid())
	return ignored

func _ray(actor: RigidBody2D, start: Vector2, end: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(start,end,9)
	query.exclude = _excluded(actor)
	return actor.get_world_2d().direct_space_state.intersect_ray(query)

func _clear(actor: RigidBody2D, center: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0,center)
	query.collision_mask = 9
	query.margin = 0.001
	query.exclude = _excluded(actor)
	return actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
