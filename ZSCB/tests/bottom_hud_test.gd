extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("BOTTOM HUD: " + message)

func settle() -> void:
	for i in range(6): await process_frame

func buttons(node: Node) -> Array[BaseButton]:
	var result: Array[BaseButton] = []
	if node is BaseButton: result.append(node)
	for child in node.get_children(): result.append_array(buttons(child))
	return result

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await settle()
	check(game.toolbar.bottom.get_global_rect().size.y / game.toolbar.scale.y <= 230.0, "first entry contracts status wrapping before any mode switch")
	game.onboarding.dismiss()
	game.combat.set_natives(false)
	game.feedback.audio_enabled = false
	var toolbar = game.toolbar
	check(toolbar.bottom.get_theme_stylebox("panel") is StyleBoxEmpty, "bottom has no enclosing paper, border or shadow")
	check(toolbar.bottom.mouse_filter == Control.MOUSE_FILTER_IGNORE, "invisible wrapper does not capture GUI input")
	for dimensions in [Vector2i(1440,900), Vector2i(3840,2160), Vector2i(844,390), Vector2i(390,844)]:
		root.min_size = dimensions
		root.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for mode in [1,3,2,4,5]:
			game.activate_draw_mode(mode)
			await settle()
			check(bounds.encloses(toolbar.bottom.get_global_rect()), "floating actions fit %s mode %d" % [dimensions, mode])
			for button in buttons(toolbar.bottom):
				if not button.is_visible_in_tree(): continue
				check(bounds.encloses(button.get_global_rect()), "button remains reachable %s %s" % [dimensions, button.text])
				check(toolbar.blocks_canvas(button.get_global_rect().get_center()), "visible buttons consume canvas input %s" % button.text)
			var status_center: Vector2 = toolbar.status_label.get_global_rect().get_center()
			check(not toolbar.blocks_canvas(status_center), "floating status text leaves world drawing accessible %s" % dimensions)
			check(is_equal_approx(toolbar.status_label.modulate.a, 1.0), "status typography stays fully legible")
			check(toolbar.bottom.get_global_rect().size.y / toolbar.scale.y <= 230.0, "floating area stays compact %s" % dimensions)
		game.activate_draw_mode(1)
		await settle()
		var empty_point: Vector2 = toolbar.status_label.get_global_rect().get_center()
		var press := InputEventMouseButton.new()
		press.position = empty_point
		press.global_position = empty_point
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press, true)
		check(game.active_stroke != null, "real mouse press through status begins a world stroke %s" % dimensions)
		press = press.duplicate()
		press.pressed = false
		root.push_input(press, true)
		game.cancel_pointer()
		for button in [toolbar.generate_button, toolbar.clear_button]:
			for state in ["normal", "hover", "pressed", "disabled"]:
				var style: StyleBox = button.get_theme_stylebox(state)
				check(style is StyleBoxFlat and style.bg_color.a >= 0.6 and style.bg_color.a <= 0.85, "small action background is translucent %s %s" % [button.text, state])
			check(is_equal_approx(button.modulate.a, 1.0) and is_equal_approx(button.get_theme_color("font_color").a, 1.0), "button text is not faded with background")
		# Candidate and grip stages must keep every action visible at narrow sizes.
		game.pending_match = [{"kind": "box"}]
		toolbar.last_state = ""
		toolbar.update_buttons()
		await settle()
		check(toolbar.candidate_button.visible and toolbar.confirm_button.visible and bounds.encloses(toolbar.confirm_button.get_global_rect()), "candidate confirmation stays reachable %s" % dimensions)
		game.pending_match = []
		game.draw_mode = 2
		game.selecting_weapon_grip = true
		toolbar.last_state = ""
		toolbar.update_buttons()
		await settle()
		check(toolbar.grip_cancel_button.visible and bounds.encloses(toolbar.generate_button.get_global_rect()) and bounds.encloses(toolbar.grip_cancel_button.get_global_rect()), "weapon grip actions remain reachable %s" % dimensions)
		game.selecting_weapon_grip = false
	game.queue_free()
	await process_frame
	print("BOTTOM HUD: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
