extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		push_error("REALTIME: " + label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var line := [{"points": [Vector2(0, 0), Vector2(20, 0)]}]
	var has_rules := ResourceLoader.exists("res://scripts/drawing_rules.gd")
	check(has_rules, "drawing has separate weapon and building rules")
	if has_rules:
		var rules = load("res://scripts/drawing_rules.gd")
		var weapon: Dictionary = rules.weapon(line)
		check(weapon.role == "weapon" and weapon.paths[0].points.size() == 2, "weapon preserves the original drawn path")
		check(is_equal_approx(weapon.reach, 2.7), "oversized weapon has bounded 2.7m reach")
		check(weapon.damage <= 40 and weapon.cooldown >= 0.3, "weapon size cannot produce unlimited power")
		check(rules.weapon([{"points": [Vector2.ZERO, Vector2.ZERO]}]).is_empty(), "zero-length weapon cannot be generated")
		var platform: Dictionary = rules.building([{"points": [Vector2(-1, 0), Vector2(1, 0)]}], "platform")
		check(platform.role == "building" and platform.dynamic, "new buildings use dynamic rigid bodies")
		var placed: Dictionary = rules.placement(platform, Vector2(0, -2.8), [], Vector2(-5, -2.2))
		check(placed.valid and placed.object.y >= -2.8, "placement snaps the actual geometry above ground")
		var denied: Dictionary = rules.placement(platform, Vector2(30, 0), [], Vector2(-5, -2.2))
		check(not denied.valid, "building cannot be placed infinitely far from the player")

	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	check(game.has_method("set_draw_mode"), "four distinct drawing modes exist")
	if not game.has_method("set_draw_mode"):
		game.queue_free()
		finish()
		return
	check(game.mode == "play", "game starts with movement active")
	Input.action_press("hotbar_3")
	await physics_frame
	await physics_frame
	Input.action_release("hotbar_3")
	check(game.draw_mode == 2 and game.placing_blueprint_id == -1, "numeric 3 selects weapon drawing instead of taking a blueprint")
	game.toggle_bag()
	game.backpack_panel.name_field.grab_focus()
	Input.action_press("hotbar_2")
	await physics_frame
	await physics_frame
	Input.action_release("hotbar_2")
	check(game.draw_mode == 2, "typing a number in the blueprint name cannot switch drawing mode")
	game.backpack_panel.name_field.release_focus()
	game.toggle_bag()
	game.set_draw_mode(2)
	game.draft = [{"points": [Vector2(0, 0), Vector2(1.5, 0)]}]
	game.set_draw_mode(3)
	check(game.draft.is_empty(), "weapon strokes do not become buildings when modes change")
	game.draft = [{"points": [Vector2(0, 0), Vector2(0, 1.5)]}]
	game.set_draw_mode(2)
	check(game.draft.size() == 1 and game.draft[0].points[1] == Vector2(1.5, 0), "mode switching restores the previous weapon sketch")
	var count: int = game.objects.size()
	game.generate()
	if game.get("selecting_weapon_grip") == true:
		game.select_weapon_grip(Vector2.ZERO)
		game.generate()
		game.select_weapon_type("sword")
		game.generate()
	check(not game.equipped_weapon.is_empty() and game.objects.size() == count, "drawing a weapon equips it instead of dropping a building")
	check(game.bag.entries.back().category == "武器", "weapon is a reusable weapon blueprint")
	game.set_draw_mode(3)
	game.build_kind = "wall"
	game.draft = [{"points": [Vector2(-1, -2.5), Vector2(1, -2.5), Vector2(1, -1.2), Vector2(-1, -1.2), Vector2(-1, -2.5)]}]
	game.generate()
	check(game.pending_building.is_empty() and game.objects.size() == count + 1, "building generation immediately releases the drawn body")
	check(game.objects.size() == count + 1, "valid building placement creates one structure")
	check(game.objects.back().dynamic and not game.object_nodes.back().freeze, "released building is a native falling body")
	var structure: Dictionary = game.objects.back()
	var saved_y: float = structure.y
	for frame in range(10): await physics_frame
	check(game.objects.back().y < saved_y - 0.02, "building falls while the character can keep moving")
	game.selected = game.objects.size() - 1
	game.set_draw_mode(4)
	var old_x: float = game.player.position.x
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	Input.action_release("move_right")
	check(game.player.position.x > old_x, "WASD movement remains active in editing mode")
	game.set_draw_mode(2)
	var start: Vector2 = game.world_to_screen(Vector2(-3, -0.5))
	game.pointer_down(start)
	Input.action_press("move_right")
	for frame in range(6):
		game.pointer_move(start + Vector2(frame * 12, 0))
		await physics_frame
	Input.action_release("move_right")
	game.pointer_up(start + Vector2(80, 0))
	check(game.draft.size() == 1 and game.player.position.x > old_x, "drawing does not stop movement")

	check(game.toolbar.get("mode_buttons") != null, "toolbar exposes four always-available modes")
	game.draft = []
	game.pointer_down(start)
	game.pointer_move(start + Vector2(80, 0))
	game.set_draw_mode(3)
	game.set_draw_mode(2)
	check(game.draft.size() == 1 and game.active_stroke == null, "switching modes finishes and preserves a valid stroke in progress")
	# Snapshots and real save/load must carry both equipment and structure behavior.
	var snap: Dictionary = game.snapshot()
	game.equipped_weapon = {}
	game.restore(snap)
	check(not game.equipped_weapon.is_empty(), "undo snapshots preserve equipped hand-drawn weapon")
	check(game.save_game(), "new world saves")
	game.equipped_weapon = {}
	game.load_game()
	check(not game.equipped_weapon.is_empty(), "weapon equipment survives a validated save/load")
	check(game.objects.back().dynamic and game.objects.back().role == "building", "dynamic building metadata survives save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))

	check(game.has_method("attack") and game.get("combat") != null, "hand-drawn weapon has real combat behavior")
	if game.has_method("attack") and game.get("combat") != null:
		game.combat.set_training(false)
		game.player.position = Vector2(-4, game.GROUND_Y + 0.54)
		game.combat.targets = [{"position": Vector2(-3, game.GROUND_Y + 0.54), "health": 100.0, "flash": 0.0}]
		game.aim_world = Vector2(-2, game.player.position.y)
		game.attack()
		check(game.combat.targets[0].health == 100, "attack press alone does not apply damage before the sword swings")
		for frame in range(12): game.combat.step(1.0 / 60.0)
		check(game.combat.targets[0].health < 100, "the moving sword model hits the target it actually sweeps over")
		var hp: float = game.combat.targets[0].health
		game.attack()
		check(is_equal_approx(game.combat.targets[0].health, hp), "holding attack respects weapon cooldown")
		game.combat.cooldown = 0
		game.pointer_down(game.world_to_screen(Vector2(-3, -0.5)))
		game.attack()
		check(game.combat.cooldown > 0 and game.active_stroke != null, "explicit attack works while another pointer keeps drawing")
		game.cancel_pointer()
		game.combat.cooldown = 0
		game.combat.targets[0].position = Vector2(9, 0)
		hp = game.combat.targets[0].health
		game.attack()
		check(is_equal_approx(game.combat.targets[0].health, hp), "weapon cannot hit out-of-range targets")
		game.set_draw_mode(2)
		game.draft = [{"points": [Vector2(0, 0), Vector2(1, 0)]}]
		game.combat.cooldown = 0
		game.input_command("secondary")
		if game.get("selecting_weapon_grip") == true:
			game.select_weapon_grip(Vector2.ZERO)
			game.generate()
			game.select_weapon_type("sword")
			game.generate()
		check(game.draft.is_empty() and is_zero_approx(game.combat.cooldown), "right-click with a sketch generates without also attacking")

	check(game.get("touch_controls") != null, "phone has owned multitouch controls")
	if game.get("touch_controls") != null:
		var touch = game.touch_controls
		touch.force_visible = true
		touch._layout()
		game.set_draw_mode(2)
		game.draft = []
		var press := InputEventScreenTouch.new()
		press.index = 0
		press.pressed = true
		press.position = touch.stick_center + Vector2(35, 0)
		touch.handle_touch(press)
		var pen := InputEventScreenTouch.new()
		pen.index = 1
		pen.pressed = true
		pen.position = game.world_to_screen(Vector2(game.camera_x + 1, game.GROUND_Y + 1.4))
		touch.handle_touch(pen)
		check(touch.movement_vector().x > 0.4 and touch.draw_finger == 1, "one finger moves while another draws")
		var motion := InputEventScreenDrag.new()
		motion.index = 1
		motion.position = pen.position + Vector2(100, 0)
		touch.handle_touch(motion)
		pen.pressed = false
		pen.position = motion.position
		touch.handle_touch(pen)
		check(game.draft.size() == 1 and touch.movement_vector().x > 0.4, "lifting drawing finger does not release movement finger")
		touch.reset()
		check(touch.movement_vector() == Vector2.ZERO and game.active_stroke == null, "cancel/focus loss clears touches without a stuck stroke")
		game.draft = []
		press.pressed = true
		press.index = 3
		press.position = touch.stick_center
		touch.handle_touch(press)
		press.pressed = false
		touch.handle_touch(press)
		check(game.draft.is_empty(), "touching movement control never draws on the canvas")
		var previous: int = game.draw_mode
		var mode_button: Button = game.toolbar.mode_buttons[0]
		press.index = 4
		press.pressed = true
		press.position = mode_button.get_global_rect().get_center()
		touch.handle_touch(press)
		press.pressed = false
		press.position = Vector2(800, 400)
		touch.handle_touch(press)
		check(game.draw_mode == previous, "dragging off a phone mode button cancels the click")
		# Exercise actual SceneTree dispatch, including mouse emulation, not just the handler.
		touch.reset()
		game.draft = []
		game.set_draw_mode(2)
		press.index = 0
		press.pressed = true
		press.position = touch.stick_center + Vector2(30, 0)
		Input.parse_input_event(press.duplicate())
		await process_frame
		pen.index = 1
		pen.pressed = true
		pen.position = game.world_to_screen(Vector2(game.camera_x + 1, game.GROUND_Y + 1.4))
		Input.parse_input_event(pen.duplicate())
		await process_frame
		motion.index = 1
		motion.position = pen.position + Vector2(100, 0)
		Input.parse_input_event(motion.duplicate())
		await process_frame
		pen.pressed = false
		pen.position = motion.position
		Input.parse_input_event(pen.duplicate())
		await process_frame
		await process_frame
		check(game.draft.size() == 1 and touch.movement_vector().x > 0.4, "actual touch dispatch draws exactly once without releasing the stick")
		press.pressed = false
		Input.parse_input_event(press.duplicate())
		await process_frame
		touch.reset()
		game.pointer_down(Vector2(600, 240))
		game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(game.active_stroke == null and touch.owners.is_empty(), "focus loss cancels the actual active pointer and all held touches")
	# Buildings block actual swept projectiles and can be destroyed.
	game.objects.clear()
	game._rebuild_objects()
	var wall_data: Dictionary = DrawingRules.building([{ "points": [Vector2(-0.1, -1), Vector2(0.1, 1)]}], "wall")
	wall_data.x = -2.0
	wall_data.y = game.GROUND_Y + 1.0
	game.objects.append(wall_data)
	game.object_nodes.append(game._build_physics_for_object(wall_data))
	game.player.position = Vector2(-4, game.GROUND_Y + 0.54)
	game.combat.training = true
	game.combat.fire_clock = 100
	game.combat.health = 100
	game.combat.projectiles = [{"position": Vector2(0, game.player.position.y), "velocity": Vector2(-10, 0), "life": 5.0}]
	game.combat.step(0.6)
	check(game.combat.projectiles.is_empty() and game.combat.health == 100 and wall_data.health == 100, "swept projectile hits wall before player even in a long frame")
	wall_data.x = -6
	wall_data.health = 120
	game.object_nodes[0].position.x = -6
	game.combat.invulnerable = 0
	game.combat.projectiles = [{"position": Vector2(0, game.player.position.y), "velocity": Vector2(-10, 0), "life": 5.0}]
	game.combat.step(0.8)
	check(game.combat.health == 85 and wall_data.health == 120, "a wall behind the player cannot retroactively block a projectile")
	game.combat.damage_building(0, 120)
	check(game.objects.is_empty() and game.object_nodes.is_empty(), "destroying a structure removes both geometry and physics")
	game.combat.training = false
	# A functional ladder must lead through a platform to a stable landing.
	var ladder: Dictionary = DrawingRules.building([{"points": [Vector2.ZERO, Vector2(0.8, 2.2)]}], "ladder")
	ladder.dynamic = false # Compatibility fixture: old saved anchored ladders.
	ladder.paths = ShapeMatcher.make_prefab("ladder", {"width": 0.8, "height": 2.2})
	ladder.x = -4
	ladder.y = game.GROUND_Y + 1.1
	var top_platform: Dictionary = DrawingRules.building([{"points": [Vector2.ZERO, Vector2(3.0, 0.3)]}], "platform")
	top_platform.dynamic = false # Compatibility fixture: old saved anchored platforms.
	top_platform.x = -4
	top_platform.y = game.GROUND_Y + 2.2
	for obj in [ladder, top_platform]:
		game.objects.append(obj)
		game.object_nodes.append(game._build_physics_for_object(obj))
	game.player.position = Vector2(-4, game.GROUND_Y + 0.54)
	game.player.linear_velocity = Vector2.ZERO
	game.climbing = false
	game.jump_was_down = false
	Input.action_press("move_up")
	var peak: float = game.player.position.y
	for frame in range(85):
		await physics_frame
		peak = maxf(peak, game.player.position.y)
	Input.action_release("move_up")
	for frame in range(30): await physics_frame
	check(peak > game.GROUND_Y + 2.5, "ladder lets the player climb through the platform above it")
	check(game.player.position.y > game.GROUND_Y + 2.3, "player can remain on the built platform after climbing")

	game.set_draw_mode(2)
	game.draft = [{"points": [Vector2.ZERO, Vector2(1, 0)]}]
	game.generate()
	game.set_draw_mode(3)
	check(not game.selecting_weapon_grip, "grip selection cannot hijack the next drawing mode")

	# Compact layouts must remain touchable and fit both phone orientations.
	root.content_scale_size = Vector2i.ZERO
	for viewport_size in [Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = viewport_size
		game.touch_controls.force_visible = true
		await process_frame
		await process_frame
		game.toolbar._layout()
		game.backpack_panel._layout()
		check(game.toolbar.header.get_global_rect().end.x <= viewport_size.x + 0.1, "mode toolbar fits phone " + str(viewport_size))
		check(game.backpack_panel.get_global_rect().end.y <= viewport_size.y + 0.1, "bag fits phone " + str(viewport_size))
		game.toggle_bag()
		await process_frame
		await process_frame
		var next_page := find_button(game.backpack_panel, "下一页")
		if next_page != null and viewport_size.y < 500:
			check(game.touch_controls._button_at(game.backpack_panel, next_page.get_global_rect().get_center()) == next_page, "clipped blueprint cards cannot intercept a visible page button")
		if viewport_size.x < 600:
			game.backpack_panel.content_scroll.ensure_control_visible(game.backpack_panel.name_field)
			await process_frame
			await process_frame
			var releases := {"count": 0}
			game.backpack_panel.name_field.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: releases.count += 1)
			var field_tap := InputEventScreenTouch.new()
			field_tap.index = 0
			field_tap.pressed = true
			field_tap.position = game.backpack_panel.name_field.get_global_rect().get_center()
			Input.parse_input_event(field_tap.duplicate())
			await process_frame
			# Headless DisplayServer has no native pointer emulation; supply that boundary explicitly.
			var mouse_tap := InputEventMouseButton.new()
			mouse_tap.device = -1
			mouse_tap.position = field_tap.position
			mouse_tap.global_position = field_tap.position
			mouse_tap.button_index = MOUSE_BUTTON_LEFT
			mouse_tap.button_mask = MOUSE_BUTTON_MASK_LEFT
			mouse_tap.pressed = true
			Input.parse_input_event(mouse_tap.duplicate())
			await process_frame
			field_tap.pressed = false
			Input.parse_input_event(field_tap.duplicate())
			await process_frame
			mouse_tap.pressed = false
			mouse_tap.button_mask = 0
			Input.parse_input_event(mouse_tap.duplicate())
			await process_frame
			check(releases.count == 1, "phone text field receives its emulated mouse release")
		var close_button := find_button(game.backpack_panel, "×")
		var close_event := InputEventScreenTouch.new()
		close_event.index = 8
		close_event.pressed = true
		close_event.position = close_button.get_global_rect().get_center()
		game.touch_controls.handle_touch(close_event)
		close_event.pressed = false
		game.touch_controls.handle_touch(close_event)
		check(not game.bag_open, "phone closes the bag without clicking the toolbar underneath")
		if game.bag_open: game.toggle_bag()
		if game.toolbar.get("mode_buttons") != null:
			for button in game.toolbar.mode_buttons:
				check(button.size.y >= 40 and button.get_global_rect().end.x <= viewport_size.x + 0.1, "phone mode button has a visible touch target")
	var invalid_equipment := {"x": 0, "y": 0, "paths": [{"points": [Vector2.ZERO, Vector2.RIGHT]}]}
	var rejected_save := SaveStore.save_game("draft", [], BlueprintBag.new_bag(), 0, 0, invalid_equipment)
	check(not rejected_save.ok, "non-weapon equipment is rejected before overwriting the saved work")
	# Loading must also reject malformed external/legacy data, independently of the writer guard.
	var malformed_file := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
	malformed_file.store_string(JSON.stringify(SaveStore._json_value({"version": 2, "paper": "draft", "objects": [], "bag": BlueprintBag.new_bag(), "cameraX": 0, "playerX": 0, "equipped_weapon": invalid_equipment})))
	malformed_file.close()
	check(SaveStore.load_game().error == "存档中的武器无效", "non-weapon equipment is rejected before combat can access missing stats")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	game.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("REALTIME TESTS: ", assertions, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption: return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found != null: return found
	return null
