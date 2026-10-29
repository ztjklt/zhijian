extends SceneTree

var failures: Array[String] = []
var count := 0

func check(value: bool, label: String) -> void:
	count += 1
	if not value:
		failures.append(label)
		push_error("GRIP: " + label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(ResourceLoader.exists("res://scripts/weapon_grip.gd"), "custom weapon grip normalization exists")
	if not ResourceLoader.exists("res://scripts/weapon_grip.gd"):
		finish()
		return
	var rules = load("res://scripts/weapon_grip.gd")
	var strokes := [{"points": [Vector2(10, 10), Vector2(10, 12), Vector2(11, 12)]}]
	var grip := Vector2(10, 10.5)
	var weapon: Dictionary = rules.make_weapon(strokes, grip)
	check(not weapon.is_empty() and weapon.grip is Vector2, "chosen grip is stored in weapon-local coordinates")
	check((weapon.paths[0].points[0] - weapon.grip).is_equal_approx(Vector2(0, -0.5)), "drawing orientation and selected handle position are preserved")
	check((weapon.paths[0].points[2] - weapon.grip).is_equal_approx(Vector2(1, 1.5)), "entire drawing shares the selected origin")
	check(rules.make_weapon(strokes, Vector2(100, 100)).is_empty(), "a click away from the weapon cannot equip it")
	check(rules.make_weapon(strokes, Vector2(NAN, 0)).is_empty(), "invalid grip coordinates are rejected")
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_draw_mode(2)
	game.draft = strokes.duplicate(true)
	var objects_before: int = game.objects.size()
	game.generate()
	check(game.selecting_weapon_grip and game.equipped_weapon.is_empty(), "generate waits for the extra grip click")
	check(game.draft.size() == 1, "weapon drawing stays visible during grip selection")
	game.pointer_down(game.world_to_screen(Vector2(100, 100)))
	check(game.selecting_weapon_grip and game.active_stroke == null, "invalid grip click stays in selection without drawing a new stroke")
	game.pointer_down(game.world_to_screen(grip))
	game.pointer_up(game.world_to_screen(grip))
	check(game.selecting_weapon_grip and game.equipped_weapon.is_empty(), "valid click selects a point without immediately equipping")
	game.generate()
	check(game.selecting_weapon_type and game.equipped_weapon.is_empty(), "grip confirmation waits for weapon type")
	game.select_weapon_type("sword")
	game.generate()
	check(not game.selecting_weapon_grip and not game.equipped_weapon.is_empty() and game.draft.is_empty(), "confirmation equips and clears only the finished sketch")
	check(game.objects.size() == objects_before, "equipping does not create a world building")
	var saved_grip: Vector2 = game.equipped_weapon.grip
	var entry: Dictionary = game.bag.entries.back()
	check(entry.grip.is_equal_approx(saved_grip), "blueprint stores the chosen grip")
	check(BlueprintBag.make_object(entry, 0, 0).grip.is_equal_approx(saved_grip), "re-equipping a blueprint retains its grip")
	var mounted = game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	for direction in [1, -1]:
		game.facing = direction
		game.character_visual._process(0)
		mounted._process(0)
		check(mounted.to_global(mounted.local_point(saved_grip)).distance_to(mounted.get_parent().global_position) < 0.01, "chosen weapon point stays on the hand when facing " + str(direction))
	for ppu in [58.0, 78.0]:
		for crouch in [false, true]:
			game.PIXELS_PER_UNIT = ppu
			game.crouching = crouch
			game.character_visual._process(0)
			mounted._process(0)
			var tip: Vector2 = game.equipped_weapon.paths[0].points[1]
			var on_screen: float = mounted.to_global(mounted.local_point(tip)).distance_to(mounted.get_parent().global_position)
			check(is_equal_approx(on_screen, tip.distance_to(saved_grip) * ppu), "weapon keeps world scale across viewport/crouch " + str(ppu) + "/" + str(crouch))
	game.PIXELS_PER_UNIT = 78
	game.crouching = false
	game.undo()
	check(game.equipped_weapon.is_empty() and game.draft.size() == 1, "undo restores the sketch and previous equipment")
	game.redo()
	check(game.equipped_weapon.grip.is_equal_approx(saved_grip), "redo restores equipment with its grip")
	check(game.save_game(), "gripped weapon saves")
	game.equipped_weapon = {}
	game.load_game()
	check(game.equipped_weapon.grip is Vector2 and game.equipped_weapon.grip.is_equal_approx(saved_grip), "equipped grip survives validated JSON round trip")
	check(game.bag.entries.back().grip is Vector2, "blueprint grip restores to a usable vector")
	game.set_draw_mode(2)
	game.draft = strokes.duplicate(true)
	game.generate()
	game.cancel_weapon_grip()
	check(not game.selecting_weapon_grip and game.draft.size() == 1, "cancel keeps drawing available for edits")
	game.generate()
	game.set_draw_mode(3)
	check(not game.selecting_weapon_grip, "changing mode exits grip selection")
	game.set_draw_mode(2)
	check(game.draft.size() == 1, "mode switching preserves unfinished weapon sketch")
	game.generate()
	game.toggle_bag()
	game.select_blueprint(entry.id)
	game.equip_blueprint()
	check(not game.selecting_weapon_grip and game.draft.size() == 1, "equipping a saved weapon cancels grip selection and preserves sketch")
	game.combat.cooldown = 0
	game.aim_world = game.player.position + Vector2.RIGHT
	game.attack()
	check(game.combat.cooldown > 0, "weapon equipped from bag can immediately attack")
	BlueprintBag.bind_hotbar(game.bag, 5, entry.id)
	game.generate()
	game.equip_hotbar(5)
	check(not game.selecting_weapon_grip, "weapon hotbar equipment cancels grip selection")
	game.generate()
	game.toggle_bag()
	game.select_blueprint(game.bag.entries[0].id)
	game.equip_blueprint()
	check(not game.selecting_weapon_grip and game.placing_blueprint_id >= 0, "taking another blueprint exits grip selection before placement")
	game.set_draw_mode(2)
	check(game.draft.size() == 1, "taking a building blueprint retains the unfinished weapon sketch")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	game.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("WEAPON GRIP TESTS: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
