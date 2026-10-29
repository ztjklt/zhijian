extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var room=load("res://scripts/net/room.gd").new()
	room.configure("ARROWS","paper","arrow-owner",PaperWorldStore.new("user://arrow_room"),"arrows")
	root.add_child(room)
	var a:Dictionary=room.join("","甲"); var b:Dictionary=room.join("","乙")
	room.ready(a.player_id); room.ready(b.player_id)
	for i in 20: await physics_frame
	var actor=room.actors[a.player_id]; var target=room.actors[b.player_id]
	actor.combat.shoot_arrow(actor.player.position+Vector2(.5,.2),Vector2.RIGHT,"player")
	for i in 12: await physics_frame
	if target.combat.health>=100: print("FAIL: 联机箭穿过朋友而未命中"); quit(1); return
	if actor.combat.health!=100: print("FAIL: 弓箭伤到自己"); quit(1); return
	room.queue_free(); await process_frame
	print("NETWORK_ARROW_TEST: PASS")
	quit()
