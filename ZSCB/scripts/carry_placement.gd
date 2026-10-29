class_name PaperCarryPlacement
extends RefCounted
## Resolve a real drop without changing the held body or its source data.

static func resolve(world, candidate: Dictionary) -> Dictionary:
	var object := candidate.duplicate(true)
	var node: RigidBody2D = world.build_object_scene.instantiate()
	node.setup(object)
	if node.get_child_count() == 0:
		node.free()
		return {"ok":false,"error":"没有有效的碰撞轮廓"}
	var clearance := PaperSpawnClearance.resolve(world, node, object)
	node.free()
	if not clearance.valid:
		return {"ok":false,"error":"这里没有安全落点，仍在携带中"}
	var offset: Vector2 = clearance.offset
	object.x += offset.x
	object.y += offset.y
	return {"ok":true,"object":object,"offset":offset,"error":""}
