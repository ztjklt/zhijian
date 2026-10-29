extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var room=load("res://scripts/net/room.gd").new()
	room.configure("SAFETY","paper","owner-safe",PaperWorldStore.new("user://spawn_room"),"spawn")
	root.add_child(room)
	var owner:Dictionary=room.join("","甲"); room.ready(owner.player_id)
	var result:Dictionary=room.command(owner.player_id,{"op":"spawn","seq":1,"object":{"kind":"freehand","dynamic":true,"x":-4.2,"y":-1.25,"paths":[{"points":[Vector2(-.4,-1.5),Vector2(.4,-1.5),Vector2(.4,1.5),Vector2(-.4,1.5),Vector2(-.4,-1.5)],"collision":true}]}})
	if not result.ok: print("FAIL: 出生墙夹具未生成"); quit(1); return
	var guest:Dictionary=room.join("","乙")
	if not guest.ok: print("FAIL: 旁边有空位却拒绝出生"); quit(1); return
	var actor=room.actors[guest.player_id]
	var query:=PhysicsShapeQueryParameters2D.new(); var circle:=CircleShape2D.new(); circle.radius=.29
	query.shape=circle; query.collision_mask=9; query.transform=Transform2D(0,actor.player.position)
	for hit in room.world.get_world_2d().direct_space_state.intersect_shape(query):
		if hit.collider is BuildObject: print("FAIL: 玩家出生在手绘墙内部"); quit(1); return
	room.queue_free(); await process_frame
	print("NETWORK_SPAWN_TEST: PASS")
	quit()
