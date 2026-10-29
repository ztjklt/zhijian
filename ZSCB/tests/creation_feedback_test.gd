extends SceneTree

var failures: Array[String] = []
var count := 0

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("FEEDBACK: " + label)

func _init() -> void:
	call_deferred("run")

func creations(feedback: Node) -> int:
	return feedback.events.filter(func(event: Dictionary) -> bool: return event.kind == "create").size()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	check("feedback" in game, "game has a creation and combat feedback layer")
	if not "feedback" in game:
		game.queue_free()
		await process_frame
		quit(1)
		return
	var feedback = game.feedback
	feedback.set_process(false)
	var p: Vector2 = game.player.position + Vector2(2, 1.5)
	game.pointer_down(game.world_to_screen(p))
	game.pointer_move(game.world_to_screen(p + Vector2(1, 0)))
	game.pointer_up(game.world_to_screen(p + Vector2(1, 0)))
	check(creations(feedback) == 0 and game.objects.is_empty(), "pen-up acknowledges ink without claiming an object was created")
	check(feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "stroke"), "valid pen-up has a small local acknowledgement")
	game.generate()
	check(game.objects.size() == 1 and creations(feedback) == 1, "free drawing celebrates exactly once after successful creation")
	game.generate()
	check(creations(feedback) == 1, "empty confirmation does not repeat success")
	feedback.events.clear()
	game.set_draw_mode(3)
	var building_p := p + Vector2(2, 0)
	game.draft = [{"points": [building_p, building_p + Vector2(1, 0), building_p + Vector2(1, 1), building_p]}]
	game.generate()
	check(creations(feedback) == 1, "2 building success celebrates")
	feedback.events.clear()
	game.set_draw_mode(5)
	var sculpt_p := p + Vector2(4, 0)
	game.draft = [{"points": [sculpt_p, sculpt_p + Vector2(1, 0), sculpt_p + Vector2(1, 1), sculpt_p + Vector2(0, 1), sculpt_p]}]
	game.generate()
	check(creations(feedback) == 1 and game.draw_mode != 5, "5 sculpt celebrates after actual creation")
	feedback.events.clear()
	game.set_draw_mode(2)
	game.draft = [{"points": [p, p + Vector2(0, 1.7)]}]
	game.generate()
	game.select_weapon_grip(p + Vector2(0, 0.2))
	check(creations(feedback) == 0 and game.equipped_weapon.is_empty(), "grip selection never celebrates premature equipment")
	game.generate()
	check(creations(feedback)==0 and game.equipped_weapon.is_empty(), "type wheel never celebrates before final confirmation")
	game.select_weapon_type("sword")
	game.generate()
	check(creations(feedback) == 1 and not game.equipped_weapon.is_empty(), "final 3 confirms and celebrates the forged weapon once")
	feedback.events.clear()
	game.set_draw_mode(3)
	game.draft = [{"points": [p + Vector2(40, 0), p + Vector2(41, 0)]}]
	game.generate()
	check(creations(feedback) == 0 and not game.draft.is_empty(), "out-of-range failure retains ink and does not announce success")
	feedback.events.clear()
	game.combat.targets = [{"position": game.player.position + Vector2(1, 0.06), "health": 1.0, "flash": 0.0, "respawn": 0.0}]
	game.combat.attack(Vector2.RIGHT)
	for frame in range(12): game.combat.step(1.0 / 60.0)
	check(feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "break"), "defeating a target emits a distinct impact burst")
	var event_count: int = feedback.events.size()
	game.combat.attack(Vector2.RIGHT)
	check(feedback.events.size() == event_count, "cooldown blocks duplicate hit sound and visual feedback")
	feedback.step(3.0)
	check(feedback.events.is_empty(), "temporary feedback expires rather than accumulating")
	for i in range(80): feedback.emit_event("hit", p)
	check(feedback.events.size() <= feedback.MAX_EVENTS, "rapid effects have a bounded particle workload")
	feedback.step(3.0)
	for cue in ["create", "stroke", "grip", "swing", "hit", "break", "hurt"]:
		var sound = load("res://assets/audio/feedback/%s.wav" % cue)
		check(sound is AudioStreamWAV and sound.get_length() > 0.02, "playable local cue: " + cue)
	game.queue_free()
	await process_frame
	print("CREATION FEEDBACK TESTS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
