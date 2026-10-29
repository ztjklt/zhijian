extends SceneTree

var failures: Array[String] = []
var count := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	count += 1
	if not ok:
		failures.append(label)
		push_error("PAPER UI: " + label)

func buttons(node: Node) -> Array[BaseButton]:
	var found: Array[BaseButton] = []
	if node is BaseButton: found.append(node)
	for child in node.get_children(): found.append_array(buttons(child))
	return found

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/main.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await process_frame
	game.onboarding.dismiss()
	game.combat.set_natives(false)
	game.bag = BlueprintBag.new_bag()
	game.backpack_panel.refresh()
	game.toggle_bag()
	await process_frame
	# An empty collection must never offer actions that silently do nothing.
	var empty_actions := buttons(game.backpack_panel).filter(func(b: BaseButton) -> bool: return b.text in ["拿到纸上  →", "再次放置", "装备武器", "先选择一张图纸"])
	check(empty_actions.size() == 1 and empty_actions[0].disabled, "reuse is disabled until a blueprint is selected")
	var building := BlueprintBag.add_entry(game.bag, {"kind": "freehand", "source": "own", "role": "building", "paths": [{"points": [Vector2.ZERO, Vector2(1, 0)]}]})
	game.backpack_panel.refresh()
	game.backpack_panel.grid.get_child(0).pressed.emit()
	check(game.selected_blueprint_id == building.entry.id and not game.backpack_panel.place_button.disabled, "selecting a card enables reuse for the selected creation")
	game.backpack_panel.hotbar.get_child(4).pressed.emit()
	check(game.bag.hotbar[4] == building.entry.id, "clicking a shortcut binds the selected blueprint without consuming it")
	game.backpack_panel.place_button.pressed.emit()
	check(not game.bag_open and game.placing_blueprint_id == building.entry.id and game.bag.entries.size() == 1, "reuse closes the collection and begins placement while keeping the blueprint")
	game.placing_blueprint_id = -1
	var weapon := BlueprintBag.add_entry(game.bag, {"kind": "weapon", "source": "own", "role": "weapon", "grip": Vector2(0, 0.2), "paths": [{"points": [Vector2.ZERO, Vector2(0, 1)]}]})
	game.toggle_bag()
	game.select_blueprint(weapon.entry.id)
	game.backpack_panel.place_button.pressed.emit()
	check(not game.bag_open and game.equipped_weapon.get("blueprint_id", -1) == weapon.entry.id and game.bag.entries.size() == 2, "weapon reuse equips the actual selected weapon and preserves the collection")
	for window_size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(844, 390), Vector2i(390, 844)]:
		root.size = window_size
		for i in range(4): await process_frame
		var viewport := Rect2(Vector2.ZERO, Vector2(window_size))
		check(viewport.encloses(game.toolbar.header.get_global_rect()), "toolbar fits %s: %s" % [window_size, game.toolbar.header.get_global_rect()])
		for button in game.toolbar.mode_buttons:
			check(viewport.encloses(button.get_global_rect()), "tool %s remains reachable in %s" % [button.text, window_size])
		for mode in [1, 3, 2, 4, 5]:
			game.activate_draw_mode(mode)
			for i in range(2): await process_frame
			for button in buttons(game.toolbar):
				if button.is_visible_in_tree():
					check(viewport.encloses(button.get_global_rect()), "visible toolbar action %s stays whole in %s" % [button.text, window_size])
		game.activate_draw_mode(4)
		await process_frame
		check(game.toolbar.status_label.is_visible_in_tree(), "move/remove guidance remains visible in %s" % window_size)
		game.toggle_bag()
		for i in range(4): await process_frame
		check(viewport.encloses(game.backpack_panel.get_global_rect()), "collection fits %s" % window_size)
		check(viewport.encloses(game.backpack_panel.place_button.get_global_rect()), "reuse action stays reachable without scrolling in %s" % window_size)
		var next_page: BaseButton = buttons(game.backpack_panel).filter(func(b: BaseButton) -> bool: return b.text == "下一页")[0]
		var hit: BaseButton = game.touch_controls._button_at(game.backpack_panel, next_page.get_global_rect().get_center())
		check(viewport.encloses(next_page.get_global_rect()) and hit == next_page, "visible pagination is reachable by touch in %s" % window_size)
		if hit != next_page:
			print("PAGE HIT DIAGNOSTIC: window=", window_size, " button=", next_page.get_global_rect(), " hit=", hit)
			var ancestor: Node = next_page.get_parent()
			while ancestor is Control:
				print("  ", ancestor.get_class(), " rect=", ancestor.get_global_rect(), " clip=", ancestor.clip_contents)
				ancestor = ancestor.get_parent()
		game.toggle_bag()
	game.queue_free()
	await process_frame
	print("PAPER UI: ", count, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
