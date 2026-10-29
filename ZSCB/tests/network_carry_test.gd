extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL NETWORK CARRY: ", label)

func run() -> void:
	var room := PaperNetRoom.new()
	room.configure("CARRY01", "paper", "owner-token", PaperWorldStore.new("user://carry-network"), "carry-world")
	root.add_child(room)
	room.set_physics_process(false)
	var owner := room.join("", "甲")
	var guest := room.join("", "乙")
	room.ready(owner.player_id)
	room.ready(guest.player_id)
	var owner_actor = room.actors[owner.player_id]
	var object := {"id": "carry-net", "structure_id": "carry-net", "author": owner.player_id, "kind": "freehand", "role": "building", "dynamic": true, "x": owner_actor.player.position.x + .8, "y": owner_actor.player.position.y - .4, "angle": 0.0, "health": 120.0, "max_health": 120.0, "version": 1, "paths": [{"points": [Vector2(-.4,-.3), Vector2(.4,-.3), Vector2(.4,.3), Vector2(-.4,.3), Vector2(-.4,-.3)], "collision": true}]}
	room.world.objects.append(object)
	var body = room.world.build_object_scene.instantiate()
	body.setup(object)
	room.world.object_nodes.append(room.world._attach_body(body, object))
	room.actors[owner.player_id].objects = room.world.objects
	room.actors[owner.player_id].object_nodes = room.world.object_nodes
	room.actors[guest.player_id].objects = room.world.objects
	room.actors[guest.player_id].object_nodes = room.world.object_nodes
	var denied := room.command(guest.player_id, {"op": "carry", "action": "pick", "id": "carry-net", "version": 1, "seq": 1})
	check(not denied.ok, "guest cannot pick a private object")
	var picked := room.command(owner.player_id, {"op": "carry", "action": "pick", "id": "carry-net", "version": 1, "seq": 1})
	check(picked.ok and room.actors[owner.player_id].carried_id == "carry-net", "owner pick is authoritative")
	check(body.collision_layer == 0 and body.collision_mask == 0 and body.freeze, "authority disables collision while carrying")
	var old_position: Vector2 = body.position
	room.actors[owner.player_id].player.position.x += 2.0
	room._physics_process(.1)
	check(body.position != old_position and body.position == room.carry_position(room.actors[owner.player_id]), "authority moves the body with the carrier")
	var wrong_drop := room.command(owner.player_id, {"op": "carry", "action": "drop", "id": "other", "version": 1, "seq": 2})
	check(not wrong_drop.ok and room.actors[owner.player_id].carried_id == "carry-net", "invalid drop cannot clear the carried object")
	var drop := room.command(owner.player_id, {"op": "carry", "action": "drop", "id": "carry-net", "version": 1, "seq": 3})
	check(drop.ok and room.actors[owner.player_id].carried_id == "", "owner drop is authoritative")
	check(body.collision_layer != 0 and body.collision_mask != 0 and not body.freeze, "drop restores authoritative physics")
	room.actors[owner.player_id].carried_id = "carry-net"
	room.disconnect_player(owner.player_id)
	check(room.actors[owner.player_id].carried_id == "", "disconnect drops carried object and releases the lock")
	room.queue_free()
	await process_frame
	print("NETWORK CARRY: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
