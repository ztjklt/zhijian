extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("RESPONSIVE UI: " + message)

func settle() -> void:
	for i in range(6): await process_frame

func click(button: BaseButton) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	# Route a complete GUI gesture in one frame. Native macOS pointer motion
	# during the next resize must not split this synthetic press/release pair.
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await settle()

func run() -> void:
	# Keep popups in the isolated test viewport so OS focus transitions cannot
	# race the synthetic press/release pair during rapid live resizing.
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/medieval.tscn").instantiate()
	game.onboarding.persist = false
	root.add_child(game)
	await settle()
	game.onboarding.dismiss()
	game.feedback.audio_enabled = false
	game.combat.set_natives(false)
	game.player.freeze = true
	game.set_physics_process(false)
	var building := BlueprintBag.add_entry(game.bag, {"kind": "freehand", "source": "own", "role": "building", "paths": [{"points": [Vector2.ZERO, Vector2(1, 0)]}]})
	game.backpack_panel.refresh()
	var base_height := 0.0
	var base_font := 0.0
	for dimensions in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(1280,720), Vector2i(390,844), Vector2i(844,390)]:
		root.min_size = dimensions
		root.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		var factor := PaperGuiScale.factor(Vector2(dimensions))
		check(is_equal_approx(game.PIXELS_PER_UNIT, (48.0 if dimensions.y < 500 else 60.0) * factor), "world zoom tracks UI without multiplication drift " + str(dimensions))
		var button: Button = game.toolbar.mode_buttons[1]
		var height := button.get_global_rect().size.y
		var font_size: float = button.get_theme_font_size("font_size") * button.get_global_transform().get_scale().x
		if base_height == 0:
			base_height = height
			base_font = font_size
		if dimensions.x >= 1280:
			check(is_equal_approx(height, base_height * factor), "button grows without resize drift at " + str(dimensions))
			check(is_equal_approx(font_size, base_font * factor), "font grows with button at " + str(dimensions))
		check(bounds.encloses(game.toolbar.header.get_global_rect()), "header inside " + str(dimensions))
		check(bounds.encloses(game.map_controls.panel.get_global_rect()), "map navigation inside " + str(dimensions))
		for tool in game.toolbar.mode_buttons:
			check(bounds.encloses(tool.get_global_rect()), "tool visible " + str(dimensions))
		var world_point := Vector2(12.3, 8.6)
		check(game.screen_to_world(game.world_to_screen(world_point)).distance_to(world_point) < 0.001, "scaled world coordinates roundtrip " + str(dimensions))
		# PopupMenu is a native Window. Inspect its real metrics separately from
		# viewport-routed GUI input, which deliberately targets the main Window.
		game.toolbar.works.show_popup()
		await process_frame
		check(game.toolbar.works.get_popup().visible, "native works popup opens " + str(dimensions))
		check(game.toolbar.works.get_popup().get_theme_font_size("font_size") == roundi(16 * factor), "popup typography scales outside Control transform " + str(dimensions))
		game.toolbar.works.get_popup().hide()
		await settle()
		game.activate_draw_mode(1)
		await click(button)
		check(game.draw_mode == 3 and game.active_stroke == null, "physical GUI click chooses building without drawing " + str(dimensions))
		check(game.toolbar.blocks_canvas(button.get_global_rect().get_center()), "scaled UI blocks canvas " + str(dimensions))
		await click(game.toolbar.bag_button)
		await settle()
		check(game.bag_open and bounds.encloses(game.backpack_panel.get_global_rect()), "physical click opens fitting bag " + str(dimensions))
		check(absf(game.backpack_panel.get_global_rect().get_center().x - dimensions.x*0.5) < 0.01, "collection stays centered " + str(dimensions))
		game.select_blueprint(building.entry.id)
		await settle()
		var place: Button = game.backpack_panel.place_button
		check(bounds.encloses(place.get_global_rect()), "bag primary action visible " + str(dimensions))
		check(game.touch_controls._button_at(game.backpack_panel, place.get_global_rect().get_center()) == place, "manual touch bounds match scaled bag " + str(dimensions))
		await click(place)
		check(not game.bag_open and game.placing_blueprint_id == building.entry.id and game.active_stroke == null, "physical click reuses blueprint " + str(dimensions))
		game.placing_blueprint_id = -1
		game.experience.open()
		await settle()
		check(bounds.encloses(game.experience.panel.get_global_rect()), "modal fits " + str(dimensions))
		check(game.experience.scroll.get_global_rect().size.y > 60, "modal scroll remains accessible " + str(dimensions))
		game.experience.close()
		await settle()
		game.touch_controls.force_visible = true
		game.touch_controls._layout()
		check(bounds.encloses(game.touch_controls.attack_rect) and bounds.encloses(game.touch_controls.generate_rect), "touch controls within viewport " + str(dimensions))
		check(is_equal_approx(game.touch_controls.attack_rect.size.x, 72 * factor), "touch target scales " + str(dimensions))
		game.touch_controls.force_visible = false
		game.camera_y = game.camera_target_y()
		var player_pixel: Vector2 = game.world_to_screen(game.player.position)
		var logical := Vector2(dimensions) / factor
		var compact: bool = logical.x < 600 or logical.y < 500
		var top: float = game.toolbar.bottom.get_global_rect().end.y if compact else game.toolbar.header.get_global_rect().end.y
		if game.map_controls.panel.is_visible_in_tree(): top=maxf(top,game.map_controls.panel.get_global_rect().end.y)
		var bottom: float = dimensions.y - 100 * factor if compact else game.toolbar.bottom.get_global_rect().position.y
		check(absf((player_pixel.y - top) / (bottom - top) - 0.76) < 0.01, "medieval framing uses lower76% of actual playable bounds " + str(dimensions))
	game.queue_free()
	await process_frame
	root.size = Vector2i(2560, 1440)
	var notebook = load("res://scenes/sandbox.tscn").instantiate()
	notebook.onboarding.persist = false
	root.add_child(notebook)
	await settle()
	check(is_equal_approx(notebook.PIXELS_PER_UNIT, 120.0), "initial highresolution knowledge entry applies world zoom")
	notebook.knowledge_world.toggle_overview()
	root.min_size = Vector2i(3840, 2160)
	root.size = Vector2i(3840, 2160)
	await settle()
	check(notebook.knowledge_world.overview, "resize preserves knowledge overview")
	notebook.knowledge_world.toggle_overview()
	check(is_equal_approx(notebook.PIXELS_PER_UNIT, 180.0), "leaving resized overview restores current UI/world zoom")
	notebook.queue_free()
	await process_frame
	var selector = load("res://scenes/map_select.tscn").instantiate()
	root.add_child(selector)
	for dimensions in [Vector2i(3840,2160), Vector2i(390,844), Vector2i(844,390), Vector2i(1280,720)]:
		root.min_size = dimensions
		root.size = dimensions
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(selector.scroll.get_global_rect()), "map selection fits after live resize " + str(dimensions))
	selector.queue_free()
	await process_frame
	print("RESPONSIVE UI: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
