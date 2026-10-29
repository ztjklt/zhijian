extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL DUEL STATE: ",label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var room=PaperNetRoom.new()
	room.configure("DUEL01","paper","owner",PaperWorldStore.new("user://duel-state"),"world")
	root.add_child(room)
	var identity:Dictionary=room.join("","甲")
	room.ready(identity.player_id)
	var actor=room.actors[identity.player_id]
	await frames(12)
	room.command(identity.player_id,{"seq":1,"op":"bow"})
	room.command(identity.player_id,{"seq":2,"op":"attack","direction":Vector2.RIGHT})
	check(actor.combat.bow_charge>0,"actual bow starts charging")
	room.command(identity.player_id,{"seq":3,"op":"input","blocked":true,"right":true,"jump":true})
	await frames(32)
	check(actor.combat.projectiles.is_empty() and actor.combat.bow_charge==0,"blocked input cancels authority bow before release")
	check(absf(actor.player.linear_velocity.x)<.1,"blocked input never moves player even with held direction")
	check(not room.command(identity.player_id,{"seq":4,"op":"attack","direction":Vector2.RIGHT}).ok,"authority rejects attacks while personal controls blocked")
	room.command(identity.player_id,{"seq":5,"op":"input","blocked":false,"jump":true})
	await frames(1)
	check(actor.player.linear_velocity.y>6,"unblock does not retain stale held-jump latch")
	await frames(20)
	room.command(identity.player_id,{"seq":7,"op":"attack","direction":Vector2.RIGHT})
	var before_x:float=actor.player.position.x
	room.command(identity.player_id,{"seq":8,"op":"input","combat_blocked":true,"right":true})
	await frames(28)
	check(actor.combat.projectiles.is_empty(),"weapon grip selection cancels authority charge")
	check(actor.player.position.x>before_x+.8,"weapon grip selection keeps actual WASD movement")
	check(not room.command(identity.player_id,{"seq":9,"op":"attack","direction":Vector2.RIGHT}).ok,"grip selection rejects new combat without blocking movement")
	room.disconnect_player(identity.player_id)
	room.join(identity.token,"甲"); room.ready(identity.player_id)
	room.command(identity.player_id,{"seq":10,"op":"input","jump":true})
	await frames(1)
	check(actor.player.linear_velocity.y>6,"reconnect clears held-jump and locomotion latches")
	room.queue_free(); await process_frame
	room=PaperNetRoom.new()
	room.configure("MAP001","medieval-v1","map-owner",PaperWorldStore.new("user://duel-map"),"world")
	root.add_child(room)
	var snapshot:Dictionary=room.snapshot()
	var session=PaperNetSession.new(); root.add_child(session)
	session.epoch=snapshot.epoch
	session.apply_snapshot(snapshot)
	var mismatch:=0
	for record in snapshot.world.entities:
		var entity=session.game.medieval_world.entity_by_id(record.id)
		if entity==null or entity.position.distance_to(Vector2(record.x,record.y))>.01: mismatch+=1
	check(mismatch==0,"current map snapshot preserves every authoritative entity coordinate; shifted="+str(mismatch))
	session.game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("NETWORK DUEL STATE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
