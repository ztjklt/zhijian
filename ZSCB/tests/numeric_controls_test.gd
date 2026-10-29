extends SceneTree

var failures: Array[String] = []
var count := 0

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("NUMBER KEYS: " + label)

func _init() -> void:
	call_deferred("run")

func key(code: Key) -> void:
	# Dispatch like an OS key event, outside the physics-frame callback used by assertions.
	await process_frame
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	await physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	# Give the game a complete released tick before another press of the same key.
	await physics_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	if game.combat.has_method("set_natives"): game.combat.set_natives(false)
	await key(KEY_2)
	check(game.draw_mode == 3, "2 enters building, matching the second toolbar button")
	var p: Vector2 = game.player.position + Vector2(2, 1.5)
	game.pointer_down(game.world_to_screen(p))
	game.pointer_move(game.world_to_screen(p + Vector2(1, 0)))
	game.pointer_up(game.world_to_screen(p + Vector2(1, 0)))
	check(game.objects.is_empty() and game.draft.size() == 1, "pen-up keeps the draft pending")
	await key(KEY_2)
	check(game.objects.size() == 1 and game.draft.is_empty(), "repeating 2 confirms exactly one building without a UI click")
	await key(KEY_2)
	check(game.objects.size() == 1, "repeating 2 with empty ink never duplicates an object")
	await key(KEY_3)
	check(game.draw_mode == 2, "3 enters weapon drawing, matching the third toolbar button")
	game.draft = [{"points": [p, p + Vector2(0, 1.7)]}]
	await key(KEY_3)
	check(game.selecting_weapon_grip and game.equipped_weapon.is_empty(), "repeating 3 advances the existing weapon workflow once")
	await key(KEY_4)
	var quick_build := BlueprintBag.add_entry(game.bag, DrawingRules.building([{"points": [p, p + Vector2(1, 0)]}], "freehand"))
	BlueprintBag.bind_hotbar(game.bag, 0, quick_build.entry.id)
	check(game.draw_mode == 4 and not game.selecting_weapon_grip, "4 changes to editing and cancels the pending phase")
	await key(KEY_3)
	check(game.draw_mode == 2 and game.draft.size() == 1 and not game.selecting_weapon_grip, "returning with 3 restores ink without accidentally confirming it")
	await key(KEY_5)
	check(game.draw_mode == 5, "5 enters sculpting")
	await key(KEY_6)
	check(game.bag_open, "6 opens blueprints")
	await key(KEY_6)
	check(not game.bag_open and game.draw_mode == 5, "6 closes blueprints without changing tools")
	await key(KEY_4)
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await physics_frame
	await key(KEY_1)
	shift = shift.duplicate()
	shift.pressed = false
	Input.parse_input_event(shift)
	await physics_frame
	check(game.placing_blueprint_id >= 0 and game.draw_mode == 3, "Shift+1 uses the blueprint slot without also entering tool 1")
	game.toggle_bag()
	game.backpack_panel.name_field.grab_focus()
	await process_frame
	await key(KEY_2)
	check(game.bag_open and game.draw_mode == 3, "typing a digit in a text field does not operate tools or close the bag")
	game.backpack_panel.name_field.release_focus()
	game.toggle_bag()
	await key(KEY_1)
	check(game.draw_mode == 1, "1 enters the first toolbar mode without changing internal slot numbering")
	for i in range(5):
		check(game.toolbar.mode_buttons[i].text.begins_with(str(i + 1) + " "), "toolbar mode uses number " + str(i + 1))
	var interruption_p := p + Vector2(5, 1)
	var before_interrupt: int = game.objects.size()
	game.draft = []
	game.pointer_down(game.world_to_screen(interruption_p))
	game.pointer_move(game.world_to_screen(interruption_p + Vector2(1, 0)))
	await key(KEY_6)
	check(game.bag_open and game.active_stroke == null and game.draft.size() == 1 and game.objects.size() == before_interrupt, "opening blueprints retains an unfinished valid stroke without generating it")
	await key(KEY_6)
	game.draft = []
	game.pointer_down(game.world_to_screen(interruption_p))
	game.pointer_move(game.world_to_screen(interruption_p + Vector2(1, 0)))
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.active_stroke == null and game.draft.size() == 1 and game.objects.size() == before_interrupt, "losing focus retains unfinished ink without confirming a creation")
	game.draft = []
	game.pointer_down(game.world_to_screen(interruption_p))
	game.pointer_move(game.world_to_screen(interruption_p + Vector2(1, 0)))
	await key(KEY_ESCAPE)
	check(game.active_stroke == null and game.draft.is_empty(), "explicit Escape still cancels the current stroke")
	# A second finger can open blueprints while the first is still drawing.
	var touch = game.touch_controls
	touch.force_visible = true
	touch._layout()
	var stick_press := InputEventScreenTouch.new()
	stick_press.index = 0
	stick_press.pressed = true
	stick_press.position = touch.stick_center
	touch.handle_touch(stick_press)
	var draw_press := InputEventScreenTouch.new()
	draw_press.index = 1
	draw_press.pressed = true
	draw_press.position = Vector2(root.size.x * 0.55, root.size.y * 0.4)
	touch.handle_touch(draw_press)
	var draw_move := InputEventScreenDrag.new()
	draw_move.index = 1
	draw_move.position = draw_press.position + Vector2(70, 0)
	touch.handle_touch(draw_move)
	var bag_press := InputEventScreenTouch.new()
	bag_press.index = 2
	bag_press.pressed = true
	bag_press.position = game.toolbar.bag_button.get_global_rect().get_center()
	touch.handle_touch(bag_press)
	bag_press = bag_press.duplicate()
	bag_press.pressed = false
	touch.handle_touch(bag_press)
	check(game.bag_open and game.draft.size() == 1 and touch.owners.is_empty() and touch.draw_finger == -1 and touch.stick_finger == -1, "touching 6 during drawing retains ink and releases every owned finger")
	draw_press = draw_press.duplicate()
	draw_press.pressed = false
	touch.handle_touch(draw_press)
	check(game.draft.size() == 1 and game.objects.size() == before_interrupt, "the old drawing finger's late release neither duplicates ink nor creates an object")
	game.toggle_bag()
	touch.force_visible = false
	# Recognition is also a same-key workflow: preview, choose, then confirm.
	game.generator = "library"
	var match_p := p + Vector2(3, 1)
	game.draft = [{"points": [match_p, match_p + Vector2(1.5, 0)]}]
	var before_match: int = game.objects.size()
	game.feedback.events.clear()
	await key(KEY_1)
	check(not game.pending_match.is_empty() and game.objects.size() == before_match, "1 previews a library candidate before creation")
	check(not game.feedback.events.any(func(e: Dictionary) -> bool: return e.kind == "create"), "candidate preview never claims creation succeeded")
	game.next_candidate()
	var chosen_kind: String = game.pending_match[game.candidate_index].id
	await key(KEY_1)
	check(game.objects.size() == before_match + 1 and game.pending_match.is_empty(), "repeating 1 confirms the preview without a UI click")
	if game.objects.size() > before_match:
		check(game.objects.back().kind == chosen_kind, "keyboard confirmation preserves the chosen candidate rather than resetting it")
		check(game.feedback.events.filter(func(e: Dictionary) -> bool: return e.kind == "create").size() == 1, "candidate success celebrates exactly once")
	await key(KEY_1)
	check(game.objects.size() == before_match + 1, "empty confirmation after a candidate never duplicates it")
	game.queue_free()
	await process_frame
	print("NUMERIC CONTROLS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
