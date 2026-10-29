extends SceneTree

var failures: Array[String] = []
var count := 0

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("DRAW SESSION: " + label)

func _init() -> void:
	call_deferred("run")

func key(code: Key) -> void:
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
	await physics_frame

func run() -> void:
	var rules = load("res://scripts/weapon_grip.gd")
	var separated := [{"points": [Vector2(-1, -1), Vector2(1, -1)]}, {"points": [Vector2(-1, 1), Vector2(1, 1)]}]
	check(not rules.accepts(separated, Vector2.ZERO), "empty space between two strokes is not a weapon grip")
	check(rules.accepts(separated, Vector2(0.4, 1.04)), "thin ink permits a nearby click")
	var snapped: Dictionary = rules.make_weapon(separated, Vector2(0.4, 1.04))
	check(not snapped.is_empty() and (snapped.paths[1].points[0] - snapped.grip).is_equal_approx(Vector2(-1.4, 0)), "a nearby click anchors onto actual ink, not empty air")
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	await key(KEY_3)
	check(game.draw_mode == 2 and not game.selecting_weapon_grip, "first 3 enters weapon drawing")
	game.set_draw_mode(2)
	var origin := Vector2(-2, 0)
	var strokes := [{"points": [origin, origin + Vector2(0, 2)]}, {"points": [origin + Vector2(-0.5, 0.4), origin + Vector2(0.5, 0.4)]}]
	game.draft = strokes.duplicate(true)
	var chosen := origin + Vector2(0, 0.2)
	Input.action_press("move_right")
	var start_x: float = game.player.position.x
	for frame in range(8): await physics_frame
	Input.action_release("move_right")
	check(game.player.position.x > start_x, "WASD moves while a multi-stroke weapon is pending")
	await key(KEY_3)
	check(game.selecting_weapon_grip and game.draft.size() == 2, "second 3 selects a grip and retains both sky strokes")
	if not game.selecting_weapon_grip: game.generate()
	await key(KEY_3)
	check(game.selecting_weapon_grip and game.equipped_weapon.is_empty(), "3 without selecting a valid point cannot equip")
	game.pointer_down(game.world_to_screen(origin + Vector2(0.4, 1.4)))
	check(game.selecting_weapon_grip and game.equipped_weapon.is_empty(), "clicking empty space inside the sketch leaves equipment unchanged")
	game.pointer_down(game.world_to_screen(chosen))
	game.pointer_up(game.world_to_screen(chosen))
	check(game.selecting_weapon_grip and game.equipped_weapon.is_empty() and game.draft.size() == 2, "a valid grip click selects only, it does not equip or clear ink")
	await key(KEY_3)
	check(game.selecting_weapon_type and game.equipped_weapon.is_empty() and game.draft.size()==2, "third 3 opens type selection without equipping")
	game.select_weapon_type("sword")
	await key(KEY_3)
	check(not game.selecting_weapon_grip and game.draft.is_empty() and not game.equipped_weapon.is_empty(), "fourth 3 equips the chosen type")
	if not game.equipped_weapon.is_empty():
		var w: Dictionary = game.equipped_weapon
		check(w.paths.size() == 2, "both strokes survive as separate weapon paths")
		check((w.paths[0].points[1] - w.grip).is_equal_approx(Vector2(0, 1.8)), "blade orientation and length relative to the hand are preserved")
		check((w.paths[1].points[0] - w.grip).is_equal_approx(Vector2(-0.5, 0.2)), "crossguard retains its position relative to the blade")
		var held = game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
		game.PIXELS_PER_UNIT = 78
		for face in [-1, 1]:
			game.facing = face
			game.character_visual._process(0)
			held._process(0)
			check(held.to_global(held.local_point(w.grip)).distance_to(held.get_parent().global_position) < 0.01, "selected ink is mounted on the hand facing " + str(face))
			var blade: Vector2 = held.to_global(held.local_point(w.paths[0].points[1])) - held.to_global(held.local_point(w.paths[0].points[0]))
			var guard: Vector2 = held.to_global(held.local_point(w.paths[1].points[1])) - held.to_global(held.local_point(w.paths[1].points[0]))
			check(absf(blade.length() - 156) < 0.01 and absf(guard.length() - 78) < 0.01 and absf(blade.dot(guard)) < 0.01, "blade and guard retain their scale and right angle through the wrist pose facing " + str(face))
	# Repeated strokes and pauses form one drawing, not separate auto-generated buildings.
	await key(KEY_2)
	check(game.draw_mode == 3, "2 enters building drawing without changing internal 5-compatible mode indices")
	game.set_draw_mode(3)
	game.draft = []
	var object_count: int = game.objects.size()
	for index in range(24):
		var p := Vector2(-1.5 + float(index % 6) * 0.35, 0.1 + float(index / 6) * 0.3)
		game.pointer_down(game.world_to_screen(p))
		game.pointer_move(game.world_to_screen(p + Vector2(0.3, 0)))
		game.pointer_up(game.world_to_screen(p + Vector2(0.3, 0)))
	check(game.draft.size() == 24, "twenty-four separate pen rounds remain in one draft beyond the old eight-stroke limit")
	game.set_physics_process(false)
	for frame in range(90):
		game._physics_process(1.0 / 60.0)
	check(game.objects.size() == object_count and game.draft.size() == 24, "a long pen-up pause never submits a multi-round drawing")
	game.set_physics_process(true)
	game.camera_x = -2
	game.player.position = Vector2(-5, game.GROUND_Y + 0.54)
	await key(KEY_2)
	check(game.objects.size() == object_count + 1 and game.draft.is_empty(), "second 2 creates exactly one multi-round building")
	if game.objects.size() > object_count:
		check(game.objects.back().paths.size() == 24, "all twenty-four paths remain in the generated body")
		check(game.save_game(), "multi-round drawing saves")
		var loaded := SaveStore.load_game()
		check(loaded.error == "" and loaded.data.objects.back().paths.size() == 24, "multi-round paths survive validated save and load")
	game.set_draw_mode(2)
	game.draft = []
	game.pointer_down(game.world_to_screen(Vector2(1, 0)))
	for index in range(1, 161):
		var angle := float(index) * TAU / 160.0
		game.pointer_move(game.world_to_screen(Vector2(cos(angle), sin(angle))))
	game.pointer_up(game.world_to_screen(Vector2(1, 0)))
	check(game.draft.size() == 1 and game.draft[0].points.front().distance_to(game.draft[0].points.back()) < 0.02, "slow strokes retain their actual final endpoint instead of being truncated at the sample limit")
	game.draft = strokes.duplicate(true)
	game.generate()
	game.pointer_down(game.world_to_screen(chosen))
	game.cancel_weapon_grip()
	check(not game.selecting_weapon_grip and game.draft.size() == 2, "cancel retains all strokes for another drawing round")
	game.generate()
	game.generate()
	check(game.selecting_weapon_grip, "cancelling clears the previous point so confirmation requires a new selection")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	game.queue_free()
	await process_frame
	print("DRAWING SESSION TESTS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
