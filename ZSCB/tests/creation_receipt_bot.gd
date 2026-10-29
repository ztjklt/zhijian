extends SceneTree
class AuditedSession extends PaperNetSession:
	var creations: Array = []
	func _send(message: Dictionary) -> void:
		if message.get("op", "") in ["spawn", "equip"]: creations.append(message.duplicate(true))
		super._send(message)
var session
var role := ""
var folder := ""
var address := ""
var map_id := "paper"
var results: Dictionary = {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--coord="): folder = arg.trim_prefix("--coord=")
		elif arg.begins_with("--address="): address = arg.trim_prefix("--address=")
		elif arg.begins_with("--map="): map_id = arg.trim_prefix("--map=")
	call_deferred("run")
func wait_until(condition: Callable, seconds: float = 16) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return false
func write_file(name: String, text: String) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE); file.store_string(text); file.close()
func fail(text: String) -> void:
	write_file(role + ".failed", text); print("BOT_FAIL: ", role, ": ", text); quit(1)
func fill_bag(game) -> void:
	while game.bag.entries.size() < 128: BlueprintBag.add_entry(game.bag, PaperWeaponGrip.practice_sword())
func free_slot(game) -> void:
	BlueprintBag.remove_entry(game.bag, game.bag.entries[8].id)
func count_commands(op: String) -> int:
	return session.creations.filter(func(message): return message.op == op).size()
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var path := OS.get_environment("PAPER_NET_CAPTURE_DIR")
	if path == "": return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join("creation-" + label + ".png"))
	var file := FileAccess.open(path.path_join("creation-" + label + ".json"), FileAccess.WRITE)
	file.store_string(PaperNetCodec.encode({"waiting": session.creation_receipts.waiting.size(), "message": session.game.toolbar.status_text, "bag": session.game.bag.entries.size(), "spawn_commands": count_commands("spawn"), "equip_commands": count_commands("equip")})); file.close()
func finish_client() -> void:
	# Normal navigation removes the game before ending the process. Give its
	# existing _exit_tree audio teardown a frame before the renderer/audio exit.
	var game = session.game
	game.network_session = null; session.game = null
	game.queue_free(); session.queue_free()
	for i in 12: await process_frame
	quit()
func run() -> void:
	session = AuditedSession.new(); root.add_child(session)
	session.operation_finished.connect(func(result): results[int(result.get("seq", 0))] = result)
	if role == "owner": session.connect_room(address, "create", "", "甲", map_id)
	else:
		if not await wait_until(func(): return FileAccess.file_exists(folder.path_join("invite"))): fail("no invitation"); return
		session.connect_room(address, "join", FileAccess.get_file_as_string(folder.path_join("invite")), "乙", "paper")
	if not await wait_until(func(): return session.ready_to_play): fail("Ready not confirmed"); return
	var game = session.game
	if role == "owner":
		write_file("invite", session.code)
		if not await wait_until(func(): return session.remotes.size() == 1): fail("guest not present"); return
		game.set_draw_mode(3)
		var at: Vector2 = game.player.position + Vector2(3, 5)
		game.draft = [{"points": [at, at + Vector2(1, 0), at + Vector2(1, .5), at + Vector2(0, .5), at]}]
		var chosen := BlueprintBag.add_entry(game.bag, DrawingRules.building(game.draft, "freehand"))
		game.generate(); game.generate()
		fill_bag(game)
		game.selected_blueprint_id = chosen.entry.id; game.equip_blueprint()
		var picked: int = game.placing_blueprint_id
		if not await wait_until(func(): return session.creation_receipts.waiting.size() == 1 and game.objects.size() == 1): fail("spawn capacity race did not retain confirmed blueprint"); return
		if game.placing_blueprint_id != picked: fail("late spawn cancelled newer placement"); return
		game.place_blueprint(at.x, at.y); game.place_blueprint(at.x, at.y)
		await capture("waiting")
		free_slot(game)
		if not await wait_until(func(): return session.creation_receipts.waiting.is_empty() and session.ready_to_play): fail("confirmed building not locally archived/Ready"); return
		if game.bag.entries.size() != 128 or game.bag.entries.back().paths != game.objects[0].paths or count_commands("spawn") != 1 or game.placing_blueprint_id != picked: fail("local building retry changed placement or sent another spawn"); return
		free_slot(game); game.set_draw_mode(2)
		var grip: Vector2 = game.player.position + Vector2(0, 2)
		game.draft = [{"points": [grip, grip + Vector2(0, .9)]}]
		game.generate(); game.select_weapon_grip(grip); game.generate(); game.select_weapon_type("firearm"); game.generate()
		fill_bag(game)
		game.cancel_weapon_grip(false); game.generate(); game.select_weapon_grip(grip); game.generate(); game.select_weapon_type("hammer")
		if not await wait_until(func(): return session.creation_receipts.waiting.size() == 1 and not session.equip_wait): fail("weapon capacity race not confirmed;ready=" + str(session.ready_to_play) + " equip_commands=" + str(count_commands("equip")) + " status=" + game.toolbar.status_text + " results=" + str(results.values().filter(func(result): return result.get("op", "") == "equip"))); return
		if not game.selecting_weapon_type or game.selected_weapon_type != "hammer" or game.equipped_weapon.get("weapon_type", "") != "firearm": fail("late equip cancelled newer wheel or lied about actual equipment"); return
		free_slot(game)
		if not await wait_until(func(): return session.creation_receipts.waiting.is_empty()): fail("weapon not locally archived"); return
		if game.bag.entries.size() != 128 or game.bag.entries.back().get("weapon_type", "") != "firearm" or not game.selecting_weapon_type or count_commands("equip") != 1 or count_commands("spawn") != 1: fail("local weapon retry duplicated network command or erased new work"); return
		await capture("archived")
		if not await wait_until(func(): return FileAccess.file_exists(folder.path_join("guest.checked"))): fail("guest did not verify authority object/equipment/private bag"); return
		game.save_game()
		if not await wait_until(func(): return session.save_request.phase == "saved"): fail("save not confirmed"); return
		write_file("world_id", session.world_id); write_file("owner.checked", "one spawn,one equip,local archive,new context retained")
		print("CREATION RECEIPTS owner: one actual spawn/equip,full bag during both receipts,local archive only,new placement/wheel preserved")
		session.leave()
		if not await wait_until(func(): return session.ended): fail("owner close not confirmed"); return
		await finish_client()
	else:
		if not await wait_until(func(): return game.objects.size() == 1 and session.ready_to_play): fail("guest cannot see actual object"); return
		if not await wait_until(func(): return not session.remotes.is_empty() and session.remotes.values().front().equipped_weapon.get("weapon_type", "") == "firearm"): fail("guest cannot see actual confirmed firearm"); return
		if game.bag.entries.size() != 6: fail("owner archive overwrote guest bag"); return
		var object: Dictionary = game.objects[0]
		var number: int = session.send_op("delete", {"id": object.id, "version": object.version})
		if not await wait_until(func(): return results.has(number)): fail("permission result missing"); return
		if results[number].ok: fail("guest deleted owner object"); return
		write_file("guest.checked", "one actual object,firearm,private bag,permission")
		if not await wait_until(func(): return session.ended): fail("guest did not observe close"); return
		await finish_client()
