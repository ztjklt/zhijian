extends "res://tests/network_creation_receipt_test.gd"

func run() -> void:
	setup()
	var spawn := draw_building()
	var original: Array = game.draft.duplicate(true)
	var screen: Vector2 = game.world_to_screen(game.player.position + Vector2(1, 2))
	game.pointer_down(screen)
	game.pointer_move(screen + Vector2(50, 0))
	check(game.active_stroke != null and game.draft == original, "active amendment fixture uses actual pointer handlers")
	reply(spawn)
	game.pointer_up(screen + Vector2(50, 0))
	check(game.draft.size() == original.size() + 1 and game.draft[0] == original[0], "late ack preserves original strokes while an amendment is being drawn")
	cleanup()

	setup()
	var existing: Dictionary = BlueprintBag.add_entry(game.bag, PaperWeaponGrip.practice_sword()).entry
	spawn = draw_building()
	game.toggle_bag(); game.select_blueprint(existing.id)
	check(game.bag_open and game.selected_blueprint_id == existing.id, "new bag selection fixture uses actual select entry")
	reply(spawn)
	check(game.selected_blueprint_id == existing.id, "late ack preserves a newer selected backpack card")
	cleanup()

	setup()
	game.set_draw_mode(1)
	game.draft = [{"points": [game.player.position + Vector2(-.5, 1), game.player.position + Vector2(.5, 1)]}]
	game.generate(); spawn = commands("spawn").back()
	game.toolbar._choose_generator("library"); game.generate(); game.next_candidate()
	var candidates: Array = game.pending_match.duplicate(true)
	var paths: Array = game.preview_paths.duplicate(true)
	check(not candidates.is_empty(), "new material candidate fixture uses actual generator actions")
	reply(spawn)
	check(game.pending_match == candidates and game.preview_paths == paths, "late ack preserves a new material candidate selected for unchanged ink")
	cleanup()
	await process_frame
	print("CREATION CONTEXT: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
