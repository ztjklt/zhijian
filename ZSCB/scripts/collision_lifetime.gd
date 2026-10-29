class_name PaperCollisionLifetime
extends RefCounted
## Remove temporary exclusions while the target's physics RID still exists.
## Godot's native exclusion getter cannot resolve an already freed target RID.
static func add(actor: PhysicsBody2D, target: PhysicsBody2D) -> void:
	# A physics query can still return a retired surface until the next sync.
	# Re-registering it after tree_exiting would outlive the one-shot cleanup.
	if not target.is_inside_tree() or target.is_queued_for_deletion(): return
	# Signals compare the base callable, so a shared static callback with
	# different bound actors would register cleanup for only the first actor.
	# Bind the receiver itself; it also disconnects if that actor dies first.
	var cleanup := Callable(actor,"remove_collision_exception_with").bind(target)
	if not target.tree_exiting.is_connected(cleanup):
		target.tree_exiting.connect(cleanup,CONNECT_ONE_SHOT)
	actor.add_collision_exception_with(target)
