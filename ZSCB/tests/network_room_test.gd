extends SceneTree
var failures := 0
func check(value: bool, text: String) -> void:
	if not value: failures += 1; print("FAIL: ", text)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://scripts/net/room.gd"):
		check(false, "双人房间尚未实现")
		quit(1)
		return
	var room = load("res://scripts/net/room.gd").new()
	var store = load("res://scripts/net/world_store.gd").new("user://room_test")
	room.configure("ABCDEF", "paper", "owner-secret", store, "testworld")
	root.add_child(room)
	var a: Dictionary = room.join("", "甲")
	var b: Dictionary = room.join("", "乙")
	check(a.ok and b.ok, "两人能加入")
	check(not room.join("", "丙").ok, "第三人拒绝")
	check(a.player_id != b.player_id and a.token != b.token, "独立凭据")
	room.ready(a.player_id); room.ready(b.player_id)
	for i in 25: await physics_frame
	var ax: float = room.actors[a.player_id].player.position.x
	var bx: float = room.actors[b.player_id].player.position.x
	room.command(a.player_id, {"op":"input", "seq":1, "right":true})
	for i in 15: await physics_frame
	check(room.actors[a.player_id].player.position.x > ax + .4, "甲独立向右移动")
	check(absf(room.actors[b.player_id].player.position.x-bx)<.15, "乙不串输入")
	var shape := {"source":"own","kind":"freehand","x":5.0,"y":0.0,"paths":[{"points":[Vector2(-.4,0),Vector2(.4,0)],"collision":true}],"dynamic":true}
	var spawn: Dictionary = room.command(a.player_id, {"op":"spawn","seq":2,"object":shape})
	check(spawn.ok, "生成真实造物")
	room.command(a.player_id, {"op":"spawn","seq":2,"object":shape})
	check(room.world.objects.size()==1, "重复命令不重复生成")
	if spawn.ok:
		check(not room.command(b.player_id,{"op":"delete","seq":1,"id":spawn.id,"version":1}).ok, "客人不能拆除别人的造物")
	check(room.command(a.player_id,{"op":"equip","seq":3,"weapon":PaperWeaponGrip.practice_sword()}).ok, "服务器校验装备")
	room.disconnect_player(a.player_id)
	check(room.actors[a.player_id].player.freeze, "断线角色暂停并退出碰撞")
	var reconnect: Dictionary = room.join(a.token, "甲")
	check(reconnect.ok and reconnect.player_id==a.player_id, "凭据重连保留身份")
	room.ready(a.player_id)
	check(not room.join("forged-token", "伪造").ok, "未知凭据不能夺取席位")
	check(not room.command(b.player_id,{"op":"save","seq":2}).ok, "客人不能保存为所有者")
	var saved: Dictionary=room.command(a.player_id,{"op":"save","seq":4})
	if not saved.ok: print("SAVE_ERROR: ", saved.get("error", ""))
	check(saved.ok, "所有者保存独立云档")
	check(not room.command(b.player_id,{"op":"import","seq":3,"data":{"objects":[],"world":{"id":"paper"}}}).ok,"客人不能导入覆盖世界")
	var before_count: int=room.world.objects.size()
	check(not room.command(a.player_id,{"op":"import","seq":5,"data":{"objects":[{"paths":[]}],"world":{"id":"paper"}}}).ok,"无效导入必须拒绝")
	check(room.world.objects.size()==before_count,"无效导入保留原世界")
	var imported:Dictionary=room.command(a.player_id,{"op":"import","seq":6,"data":{"objects":[shape],"world":{"id":"paper"}}})
	check(imported.ok,"所有者可以导入旧单人作品")
	room.queue_free()
	await process_frame
	print("NETWORK_ROOM_TEST: ", "PASS" if failures==0 else "FAIL", " failures=",failures)
	quit(0 if failures==0 else 1)
