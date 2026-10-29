extends "res://tests/network_carry_drop_test.gd"

func run() -> void:
	await fresh("tick")
	var guest: Dictionary = room.join("", "乙")
	room.ready(guest.player_id)
	room._physics_process(.1)
	check(held.freeze and held.collision_layer == 0 and held.collision_mask == 0, "authority world activity cannot unfreeze a carried body")
	var session := PaperNetSession.new()
	root.add_child(session)
	session.player_id = owner.player_id
	session.epoch = room.epoch
	session.apply_snapshot(room.snapshot())
	var client = session.game
	client.set_physics_process(false)
	check(client.carried_id == "wire-drop" and client.object_nodes[0].collision_layer == 0, "initial carried snapshot suppresses prediction collision")
	session.apply_snapshot(room.snapshot())
	check(client.carried_id == "wire-drop" and client.object_nodes[0].collision_layer == 0, "same-id resync reapplies suppression to the new replica")
	var viewer := PaperNetSession.new()
	root.add_child(viewer)
	viewer.player_id = guest.player_id; viewer.epoch = room.epoch
	viewer.apply_snapshot(room.snapshot())
	viewer.game.set_physics_process(false)
	check(viewer.game.carried_id == "" and viewer.game.object_nodes[0].collision_layer == 0, "friend's carried object also stays nonblocking for local movement prediction")
	room.command(owner.player_id,{"op":"carry","action":"drop","id":"wire-drop","version":1,"seq":2})
	session.apply_snapshot(room.snapshot())
	check(client.carried_id == "" and client.object_nodes[0].freeze and client.object_nodes[0].collision_layer == 1 and client.object_nodes[0].collision_mask == 0, "drop restores only the normal frozen replica collision state")
	viewer.apply_snapshot(room.snapshot())
	check(viewer.game.object_nodes[0].collision_layer == 1, "friend's drop restores the normal replica layer")
	viewer.game.queue_free();viewer.queue_free()
	session.game.queue_free();session.queue_free()
	await process_frame
	await dispose()
	print("NETWORK CARRY REPLICA: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
