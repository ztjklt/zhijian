extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("EXPERIENCE: " + label)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/sandbox.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.set_physics_process(false)
	game.player.freeze = true
	check(game.knowledge_world != null, "project run enters the six-chapter integrated map")
	var experience = game.get("experience")
	check(experience != null, "the running Godot project provides a complete experience entry")
	if experience == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	game.combat.set_natives(false)
	var p: Vector2 = game.player.position + Vector2(2, 2)
	game.pointer_down(game.world_to_screen(p))
	game.pointer_move(game.world_to_screen(p + Vector2(1, 0)))
	experience.open()
	await process_frame
	check(experience.visible and game.active_stroke == null and game.draft.size() == 1, "opening the experience panel preserves unfinished ink")
	var count: int = game.objects.size()
	game.pointer_down(Vector2(10, 10))
	game.input_command("generate")
	game.attack()
	check(game.active_stroke == null and game.objects.size() == count and game.combat.swing == 0, "panel input cannot draw, generate or attack behind the overlay")
	Input.action_press("hotbar_2")
	game._physics_process(0.016)
	Input.action_release("hotbar_2")
	check(game.draw_mode == 1, "number keys do not switch tools through the panel")
	var map_key := InputEventKey.new()
	map_key.pressed = true
	map_key.keycode = KEY_M
	game.knowledge_world._unhandled_input(map_key)
	check(not game.knowledge_world.overview, "map hotkeys do not leak through the panel")
	var original: Dictionary = PaperWeaponGrip.make_weapon([{"points": [Vector2.ZERO, Vector2(0, 1.1)]}], Vector2.ZERO)
	game.equipped_weapon = original.duplicate(true)
	experience.try_sword()
	check(not experience.visible and not game.equipped_weapon.is_empty() and game.equipped_weapon != original, "one action equips the trial sword and returns to the actual map")
	check(not game.combat.bow_equipped and game.combat.cooldown == 0, "trial melee is immediately usable")
	check(game.draft.size() == 1 and game.objects.size() == count, "trying equipment does not delete a draft or create world objects")
	game.combat.attack(Vector2.RIGHT)
	check(game.combat.swing > 0 and game.character_visual.sample_weapon().size() > 0, "trial equipment runs the real animated weapon and geometry")
	experience.open()
	experience.restore_weapon()
	check(game.equipped_weapon == original, "the original weapon can be restored after trying the sword")
	experience.open()
	experience.try_sword()
	game.equipped_weapon = original.duplicate(true) # Player subsequently creates/equips a new weapon.
	experience.restore_weapon()
	check(game.equipped_weapon == original, "restore never overwrites a weapon equipped after the trial")
	experience.open()
	experience.try_bow()
	check(not experience.visible and game.combat.bow_equipped, "bow trial returns to gameplay with the real bow")
	game.combat.attack(Vector2.RIGHT)
	check(game.combat.bow_charge > 0, "bow trial uses the live draw-and-shoot mechanism")
	experience.open()
	experience.visit_chapter(4)
	check(not experience.visible and game.player.position.x > 104 and game.player.position.x < 130, "chapter buttons enter the actual selected chapter")
	experience.open()
	experience.show_map()
	check(not experience.visible and game.knowledge_world.overview, "map entry opens the real six-chapter overview")
	game.knowledge_world.toggle_overview()
	for dimensions in [Vector2i(1280,720), Vector2i(960,540), Vector2i(844,390), Vector2i(390,844)]:
		root.size = dimensions
		experience.open()
		for i in range(3): await process_frame
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(experience.panel.get_global_rect()), "experience panel fits viewport " + str(dimensions))
		check(experience.scroll.get_global_rect().size.y > 60, "features remain accessible by scrolling at " + str(dimensions))
	experience.close()
	game.queue_free()
	await process_frame
	print("EXPERIENCE TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
