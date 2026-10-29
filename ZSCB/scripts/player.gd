class_name StickmanPlayer
extends RigidBody2D

const CollisionLifetime := preload("res://scripts/collision_lifetime.gd")

var game = null
var foot_sensor: Area2D
var foot_bodies: Array[Node2D] = []
var dropping_bodies: Array[PhysicsBody2D] = []
var drop_elapsed := 0.0
var passing_surfaces: Array[PhysicsBody2D] = []
var approaching_surfaces: Array[PhysicsBody2D] = []
var platform_probe := CircleShape2D.new()

func _enter_tree() -> void:
	_restore_surface_exclusions.call_deferred()

func _restore_surface_exclusions() -> void:
	if not is_inside_tree(): return
	for body in passing_surfaces+dropping_bodies:
		if is_instance_valid(body): CollisionLifetime.add(self,body)

func _physics_process(_delta: float) -> void:
	update_owned_surfaces()

func _surface_clearance(body: PhysicsBody2D) -> float:
	var a: Vector2 = body.to_global(body.get_meta("walk_edge_a"))
	var b: Vector2 = body.to_global(body.get_meta("walk_edge_b"))
	var normal := Vector2(-(b-a).y,(b-a).x).normalized()
	return (global_position-a).dot(normal)-0.29

func _inside_surface_span(body: PhysicsBody2D) -> bool:
	var a: Vector2 = body.to_global(body.get_meta("walk_edge_a"))
	var b: Vector2 = body.to_global(body.get_meta("walk_edge_b"))
	return global_position.x >= minf(a.x,b.x) and global_position.x <= maxf(a.x,b.x)

func update_owned_surfaces() -> void:
	if not is_inside_tree(): return
	# A one-way rectangle can still catch the circle at an end/corner when its
	# foot is below the face. Keep that particular face absent until the foot
	# clears it; neighbouring lower faces remain available for landings.
	platform_probe.radius = 1.2
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = platform_probe
	query.transform = Transform2D(0,global_position)
	query.collision_mask = 1
	var nearby: Array[PhysicsBody2D] = []
	for hit in get_world_2d().direct_space_state.intersect_shape(query,128):
		var body = hit.collider
		if not body is PhysicsBody2D or not body.is_inside_tree() or body.is_queued_for_deletion() or not body.has_meta("walk_edge_a"): continue
		nearby.append(body)
		var clearance := _surface_clearance(body)
		# Once approached from above, let the solver finish a landing even if
		# one fast physics step temporarily penetrates its contact margin.
		# A sloped edge's infinite plane extends beyond its visible ends.
		# Entering beside those ends is not an approach from above.
		var side_or_below := (clearance < -0.035 or not _inside_surface_span(body)) and not approaching_surfaces.has(body)
		if (side_or_below or clearance < -0.29) and not passing_surfaces.has(body):
			passing_surfaces.append(body)
			CollisionLifetime.add(self,body)
			_foot_exited(body)
	for index in range(passing_surfaces.size()-1,-1,-1):
		var body := passing_surfaces[index]
		if not is_instance_valid(body):
			passing_surfaces.remove_at(index)
		elif not nearby.has(body) or (_inside_surface_span(body) and _surface_clearance(body) > 0.015):
			passing_surfaces.remove_at(index)
			if not dropping_bodies.has(body): remove_collision_exception_with(body)
	approaching_surfaces = nearby
	# Area2D sends no second entered signal when an overlapping face stops
	# being ignored. Reconcile those candidates using the same foot criterion.
	if is_instance_valid(foot_sensor):
		for body in foot_sensor.get_overlapping_bodies():
			if body.has_meta("walk_edge_a") and _surface_clearance(body) >= -0.035:
				_foot_entered(body)

func _ready() -> void:
	lock_rotation = true
	linear_damp = 0.0
	collision_layer = 2
	# Ground/freehand objects use layer 1; gates and ladders use layer 8.
	collision_mask = 9
	var body_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 0.29
	body_shape.shape = circle
	add_child(body_shape)
	foot_sensor = Area2D.new()
	foot_sensor.collision_layer = 4
	foot_sensor.collision_mask = 9
	var foot_shape := CollisionShape2D.new()
	var foot_circle := CircleShape2D.new()
	foot_circle.radius = 0.20
	foot_shape.shape = foot_circle
	foot_shape.position = Vector2(0, -0.28)
	foot_sensor.add_child(foot_shape)
	add_child(foot_sensor)
	foot_sensor.body_entered.connect(_foot_entered)
	foot_sensor.body_exited.connect(_foot_exited)

func _foot_entered(body: Node) -> void:
	if dropping_bodies.has(body) or passing_surfaces.has(body) or linear_velocity.y > 0.5 or foot_bodies.has(body): return
	if body.has_meta("walk_edge_a") and _surface_clearance(body) < -0.035: return
	if body is BuildObject and body.data.get("kind", "") == "ladder": return
	foot_bodies.append(body)
	if game:
		if not game.on_ground and linear_velocity.y < -1.0:
			game.land_timer = 0.18
		game.ground_contacts += 1
		game.on_ground = true

func _foot_exited(body: Node) -> void:
	if not foot_bodies.has(body): return
	foot_bodies.erase(body)
	if game:
		game.ground_contacts = foot_bodies.size()
		game.on_ground = game.ground_contacts > 0

func clear_foot_contacts() -> void:
	foot_bodies.clear()
	if game:
		game.on_ground = false
		game.ground_contacts = 0

func support_bodies() -> Array[PhysicsBody2D]:
	var supports: Array[PhysicsBody2D] = []
	var excluded: Array[RID] = [get_rid()]
	for body in get_collision_exceptions():
		if is_instance_valid(body): excluded.append(body.get_rid())
	# Probe beneath the round body, so a nearby wall is not a landing/support.
	for x in [-0.18, 0.0, 0.18]:
		var from := global_position + Vector2(x, 0)
		var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, -0.38), 9)
		query.exclude = excluded
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		# Ladders are climbable rails, not floors (dynamic ladders also ghost the body).
		while not hit.is_empty() and hit.collider is BuildObject and hit.collider.data.get("kind", "") == "ladder":
			excluded.append(hit.collider.get_rid())
			query.exclude = excluded
			hit = get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y > 0.35 and not supports.has(hit.collider):
			supports.append(hit.collider)
	return supports

func begin_drop_through() -> bool:
	var supports := support_bodies()
	if supports.is_empty(): return false
	# Only created structures may be bypassed. Base terrain is never exempted.
	for body in supports:
		if not body is BuildObject and not body.get_meta("map_drop_allowed", false): return false
	# At a roof ridge the circle can touch both slopes although the short foot
	# rays report only one. Drop both adjacent faces, keeping lower sills solid.
	var near := Rect2(global_position-Vector2(.37,.37),Vector2(.74,.74))
	for support in supports.duplicate():
		if not support.has_meta("medieval_owner"): continue
		var owner = support.get_meta("medieval_owner")
		if not is_instance_valid(owner): continue
		for candidate in owner.get_children():
			if not candidate is StaticBody2D or supports.has(candidate): continue
			for fixture in candidate.get_children():
				if fixture is CollisionShape2D and fixture.shape != null and (fixture.global_transform*fixture.shape.get_rect()).intersects(near):
					supports.append(candidate)
					break
	for body in supports:
		if dropping_bodies.has(body): continue
		dropping_bodies.append(body)
		CollisionLifetime.add(self,body)
	drop_elapsed = 0
	clear_foot_contacts()
	sleeping = false
	return true

func update_drop_through(delta: float) -> void:
	update_owned_surfaces()
	drop_elapsed += delta
	for index in range(dropping_bodies.size() - 1, -1, -1):
		var body := dropping_bodies[index]
		if not is_instance_valid(body):
			dropping_bodies.remove_at(index)
			continue
		var bounds := Rect2()
		var has_bounds := false
		for child in body.get_children():
			if not child is CollisionShape2D or child.disabled or child.shape == null: continue
			var rect: Rect2 = child.global_transform * child.shape.get_rect()
			bounds = bounds.merge(rect) if has_bounds else rect
			has_bounds = true
		# Wait for the entire player to clear real geometry, including thick/rotated islands.
		var player_bounds := Rect2(global_position - Vector2(0.31, 0.31), Vector2(0.62, 0.62))
		var intersects := has_bounds and bounds.intersects(player_bounds)
		if intersects and body.has_meta("medieval_owner"):
			# A long pitched roof's bounding box also contains the lower window.
			# Restore this support once the player clears its actual thin shape.
			intersects = false
			var player_polygon := PackedVector2Array([player_bounds.position,Vector2(player_bounds.end.x,player_bounds.position.y),player_bounds.end,Vector2(player_bounds.position.x,player_bounds.end.y)])
			for fixture in body.get_children():
				if not fixture is CollisionShape2D or fixture.shape == null: continue
				var local: Rect2 = fixture.shape.get_rect()
				var polygon: PackedVector2Array = fixture.global_transform*PackedVector2Array([local.position,Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)])
				if not Geometry2D.intersect_polygons(player_polygon,polygon).is_empty(): intersects = true
		if drop_elapsed > 0.1 and not intersects:
			if not passing_surfaces.has(body): remove_collision_exception_with(body)
			dropping_bodies.remove_at(index)

func reset_movement() -> void:
	for body in passing_surfaces:
		if is_instance_valid(body): remove_collision_exception_with(body)
	passing_surfaces.clear()
	approaching_surfaces.clear()
	for body in dropping_bodies:
		if is_instance_valid(body): remove_collision_exception_with(body)
	dropping_bodies.clear()
	clear_foot_contacts()
	if game:
		game.wall_climb.reset(self)
		game.jumps_used = 0
		game.down_tap_timer = 0
		game.down_was_down = Input.is_action_pressed("move_down")
		game.jump_was_down = Input.is_action_pressed("move_up")
		game.climbing = false
	gravity_scale = 1
