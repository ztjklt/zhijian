class_name BuildObject
extends RigidBody2D

var data: Dictionary = {}
var fill_contours: Array = []
var damage_paths: Array = []
var damage_prepared: Dictionary = {}
var damage_pending := false

func setup(object_data: Dictionary) -> void:
	data = object_data
	PaperObjectDamage.normalize(data)
	damage_prepared=PaperObjectDamage.prepare(data)
	damage_paths=damage_prepared.paths
	position = Vector2(data.x, data.y)
	rotation = data.get("angle", 0.0)
	collision_layer = 8 if data.get("kind", "") in ["gate", "ladder"] else 1
	collision_mask = 1 | 8 | 64 | 128
	if not data.get("dynamic", true):
		freeze = true
		freeze_mode = FREEZE_MODE_STATIC
		_build_fixed(damage_paths)
		return
	linear_damp = 0.08
	angular_damp = 0.12
	continuous_cd = CCD_MODE_CAST_SHAPE
	lock_rotation = false
	var material := PhysicsMaterial.new()
	material.friction = 0.65
	material.bounce = 0.12
	physics_material_override = material
	var prepared: Dictionary = damage_prepared
	mass = prepared.mass
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = prepared.center
	inertia = prepared.inertia
	fill_contours = prepared.fills
	_add_shapes(prepared)

func _add_shapes(prepared: Dictionary) -> void:
	for item in prepared.shapes:
		var fixture := CollisionShape2D.new()
		if item.has("polygon"):
			var polygon := ConvexPolygonShape2D.new()
			polygon.points = item.polygon
			fixture.shape = polygon
		else:
			var capsule := CapsuleShape2D.new()
			capsule.radius = PaperShapePhysics.INK_RADIUS
			capsule.height = item.a.distance_to(item.b) + 2 * capsule.radius
			fixture.shape = capsule
			fixture.position = (item.a + item.b) * 0.5
			fixture.rotation = (item.b - item.a).angle() - PI * 0.5
		add_child(fixture)

# Existing fixed structures retain one-way platforms and their saved behavior.
func _build_fixed(paths: Array) -> void:
	for path in paths:
		if not path.get("collision", true): continue
		var points: Array = path.get("points", [])
		for index in range(1, points.size()):
			var a: Vector2 = points[index - 1]
			var b: Vector2 = points[index]
			if a.distance_to(b) < 0.01: continue
			var fixture := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2(a.distance_to(b), 0.06)
			fixture.shape = box
			fixture.position = (a + b) * 0.5
			fixture.rotation = (b - a).angle()
			if data.get("kind", "") == "platform":
				fixture.rotation += PI
				fixture.one_way_collision = true
				fixture.one_way_collision_margin = 0.06
			add_child(fixture)

func sync_to_data() -> void:
	if data.is_empty(): return
	data.x = position.x
	data.y = position.y
	data.angle = rotation

func rebuild_damage() -> void:
	damage_prepared=PaperObjectDamage.prepare(data)
	damage_paths=damage_prepared.paths
	fill_contours=damage_prepared.fills if data.get("dynamic",true) else []
	if not damage_pending:
		damage_pending=true
		_replace_damaged_shapes.call_deferred()

func _replace_damaged_shapes() -> void:
	damage_pending=false
	if not is_inside_tree() or is_queued_for_deletion():return
	for child in get_children():
		if child is CollisionShape2D:child.free()
	if data.get("dynamic",true):
		mass=damage_prepared.mass
		center_of_mass=damage_prepared.center
		inertia=damage_prepared.inertia
		_add_shapes(damage_prepared)
	else:_build_fixed(damage_paths)
	sleeping=false
