extends "res://tests/network_duel_bot.gd"
## Observe real authority events and audio; never inject a damage or visual event.

var captured_feedback: Dictionary = {}
var heard_feedback: Dictionary = {}

func _process(delta: float) -> bool:
	super(delta)
	if session == null or session.game == null: return false
	# Two test windows share one desktop. Emulate each remote user's focused window.
	# Bag/modal blocking remains in the real session and is exercised by the duel.
	session.focus_active = true
	var feedback = session.game.feedback
	for event in feedback.events:
		if event.kind not in ["hit", "hurt"]: continue
		if feedback.voices.any(func(voice): return voice.playing and feedback.sound_banks[event.kind].has(voice.stream)):
			heard_feedback[event.kind] = true
		if event.age < 0.04 or event.age > 0.18 or captured_feedback.has(event.kind): continue
		captured_feedback[event.kind] = true
		capture_feedback(event.kind)
	return false

func capture_feedback(kind: String) -> void:
	var destination := OS.get_environment("PAPER_NET_CAPTURE_DIR")
	if destination.is_empty(): return
	DirAccess.make_dir_recursive_absolute(destination)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination.path_join(role + "-" + kind + ".png"))
	print("NETWORK FEEDBACK CAPTURE ", role, " ", kind)

func mark(name: String, value: String = "ok") -> void:
	if name == role + ".checked":
		if DisplayServer.get_name() == "headless" or not captured_feedback.has("hit") or not captured_feedback.has("hurt") or not heard_feedback.has("hit") or not heard_feedback.has("hurt"):
			fail("missing real hit/hurt render or audio: " + str(captured_feedback) + " / " + str(heard_feedback))
			return
		print("NETWORK FEEDBACK PASS ", role, ": confirmed hit/hurt rendered and matching audio voices playing")
	super(name, value)

func run() -> void:
	session = PaperNetSession.new()
	root.add_child(session)
	session.operation_finished.connect(func(result): results[int(result.get("seq", 0))] = result)
	if role == "owner": session.connect_room(address, "create", "", "甲", map_id)
	else:
		if not await wait_until(func(): return marked("invite")): fail("missing invite"); return
		session.connect_room(address, "join", FileAccess.get_file_as_string(folder.path_join("invite")), "乙", map_id)
	if not await wait_until(func(): return session.ready_to_play): fail("not ready"); return
	if role == "owner": mark("invite", session.code)
	if not await wait_until(func(): return session.remotes.size() == 1): fail("missing friend"); return
	var game: PaperCastleMain = session.game
	game.equipped_weapon = PaperWeaponGrip.practice_sword()
	if not await wait_until(func(): return not session.sent_weapon.is_empty() and not session.remotes.values().front().equipped_weapon.is_empty()): fail("equipment not shared"); return
	session._send({"type": "ping", "stamp": Time.get_ticks_msec()})
	if not await wait_until(func(): return session.round_trip_ms >= 0): fail("ping missing"); return
	if role == "owner":
		phase = "approach for hit feedback"
		if not await approach(): fail("cannot approach friend"); return
		hit_friend()
		if not await wait_until(func(): return session.remotes.values().front().combat.health < 100): fail("sword missed"); return
		mark("first_hit")
		if not await wait_until(func(): return game.combat.health < 100 and captured_feedback.has("hurt") and heard_feedback.has("hurt")): fail("return hit feedback missing"); return
		mark("return_hit")
		if not await wait_until(func(): return marked("guest.checked")): fail("guest feedback verification missing"); return
		var number := session.send_op("save")
		if not await wait_until(func(): return results.has(number)) or not results[number].ok: fail("save not confirmed"); return
		mark("world_id", session.world_id)
		mark("owner.checked")
		session.leave()
		if not await wait_until(func(): return session.ended): fail("leave not confirmed"); return
	else:
		phase = "receive and return hit"
		if not await wait_until(func(): return game.combat.health < 100 and marked("first_hit")): fail("incoming sword missing"); return
		await create_timer(0.8).timeout
		if not await approach(): fail("cannot approach for retaliation"); return
		hit_friend()
		if not await wait_until(func(): return marked("return_hit") and captured_feedback.has("hit") and heard_feedback.has("hit")): fail("return hit confirmation missing"); return
		mark("guest.checked")
		if not await wait_until(func(): return session.ended): fail("owner close missing"); return
	# Release WAV playback on normal frames before the test process shuts down.
	# Immediate SceneTree.quit can outrun the audio mixer's deferred references.
	var finished_session = session
	session = null
	if finished_session.game != null: finished_session.game.queue_free()
	finished_session.queue_free()
	for frame in range(5): await process_frame
	await create_timer(0.05).timeout
	quit()
