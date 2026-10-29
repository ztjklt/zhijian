extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var room=PaperNetRoom.new()
	room.configure("RACE01","paper","owner",PaperWorldStore.new("user://equip-race"),"world")
	root.add_child(room)
	var identity:Dictionary=room.join("","甲");room.ready(identity.player_id)
	var session=PaperNetSession.new();root.add_child(session)
	session.player_id=identity.player_id;session.epoch=room.epoch
	session.apply_snapshot(room.snapshot());session.ready_to_play=true
	var game=session.game
	var sword:=PaperWeaponGrip.practice_sword()
	game.equipped_weapon=sword.duplicate(true)
	# Delayed Ready/initial state reaches the GUI after a hotbar choice but before tick sends it.
	session._actor(room.actors[identity.player_id].state())
	if game.equipped_weapon.is_empty():
		print("FAIL EQUIP RACE: delayed empty authority frame erased unsent local choice");quit(1);return
	session.tick(.06)
	if not session.equip_wait or session.pending.is_empty():
		print("FAIL EQUIP RACE: chosen equipment never reaches command queue");quit(1);return
	var number:int=session.pending.keys().front()
	var result:Dictionary=room.command(identity.player_id,session.pending[number].request)
	result.seq=number;session._result(result)
	if not result.ok or game.equipped_weapon!=session.sent_weapon or game.equipped_weapon.is_empty():
		print("FAIL EQUIP RACE: authority confirmation did not retain sword");quit(1);return
	room.command(identity.player_id,{"seq":number+1,"op":"equip","weapon":{}})
	session._actor(room.actors[identity.player_id].state())
	if not game.equipped_weapon.is_empty():
		print("FAIL EQUIP RACE: later confirmed unequip ignored");quit(1);return
	game.queue_free();session.queue_free();room.queue_free();await process_frame
	print("NETWORK EQUIPMENT RACE: PASS");quit()
