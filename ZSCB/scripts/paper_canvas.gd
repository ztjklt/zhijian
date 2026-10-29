class_name PaperCanvas
extends Node2D

var game = null

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouse and event.device == -1 and game.touch_controls != null and game.touch_controls.enabled(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				game.pointer_down(event.position)
			else:
				game.pointer_up(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			game.input_command("secondary")
	elif event is InputEventMouseMotion:
		game.pointer_move(event.position)

func _line(a: Vector2, b: Vector2, color: Color, width: float = 2.0) -> void:
	draw_line(a, b, color, width, true)

func _world_path(points: Array, offset: Vector2, color: Color, width: float, object: Dictionary = {}) -> void:
	if points.size() < 2:
		return
	var packed := PackedVector2Array()
	for point in points:
		var world: Vector2 = game.object_point(object, point) if not object.is_empty() else point + offset
		packed.append(game.world_to_screen(world))
	draw_polyline(packed, Color(0.32, 0.25, 0.22, 0.17), width + 3.0, true)
	draw_polyline(packed, color, width, true)

func _draw_paper(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("faf7eb"))
	var y := 26.0
	while y < size.y:
		_line(Vector2(20, y), Vector2(size.x - 20, y), Color(0.39, 0.59, 0.68, 0.18), 1)
		y += 30.0
	_line(Vector2(80, 14), Vector2(80, size.y - 14), Color(0.81, 0.42, 0.45, 0.34), 2)
	for hole_y in range(95, int(size.y - 35), 132):
		draw_circle(Vector2(37, hole_y), 7, Color("dfd8c0"))

func _draw_landscape(size: Vector2) -> void:
	var ground_y: float = game.world_to_screen(Vector2(0, game.GROUND_Y)).y
	for layer in range(2):
		var points := PackedVector2Array()
		for px in range(0, int(size.x) + 10, 10):
			var world_x: float = game.camera_x + (px - size.x * 0.5) / game.PIXELS_PER_UNIT
			var height: float = game.GROUND_Y + 1.9 + layer * 0.8 + abs(sin(world_x * (0.19 if layer == 0 else 0.11) + layer * 2.2)) * 0.9
			points.append(Vector2(px, game.world_to_screen(Vector2(world_x, height)).y))
		draw_polyline(points, Color(0.36, 0.44, 0.39, 0.30 if layer == 0 else 0.17), 1.8, true)
	_line(Vector2(14, ground_y), Vector2(size.x - 14, ground_y), Color(0.23, 0.21, 0.22, 0.84), 3)

func _draw() -> void:
	if game == null or not is_instance_valid(game):
		return
	var size := get_viewport_rect().size
	if game.knowledge_world != null:
		game.knowledge_world.draw_background(self, size)
		game.knowledge_world.draw_landscape(self, size)
	else:
		_draw_paper(size)
		if game.medieval_world == null: _draw_landscape(size)
		else: game.medieval_world.draw_world(self)
	if game.onboarding.visible and game.onboarding.stage == 0 and game.mode == "build" and not game.bag_open:
		var start := Vector2(size.x * 0.54 - 90, size.y * 0.48)
		for dash in range(12):
			_line(start + Vector2(dash * 16, 0), start + Vector2(dash * 16 + 8, 0), Color(0.21, 0.44, 0.40, 0.32), 2)
	for index in game.objects.size():
		var object: Dictionary = game.objects[index]
		if index < game.object_nodes.size():
			var body = game.object_nodes[index]
			if is_instance_valid(body):
				# Triangulate the small local cut pieces before applying screen-space
				# translation, avoiding precision loss on distant/large maps.
				draw_set_transform(game.world_to_screen(Vector2(object.x,object.y)),-float(object.get("angle",0)),Vector2(game.PIXELS_PER_UNIT,-game.PIXELS_PER_UNIT))
				for contour in body.fill_contours:
					if contour.size()>=3:draw_colored_polygon(contour,Color(.36,.44,.39,.10))
				draw_set_transform(Vector2.ZERO)
		var color := Color("2d3a4f") if object.get("source") == "library" else Color("29282d")
		var live_paths:Array=object.get("paths",[])
		if index<game.object_nodes.size() and is_instance_valid(game.object_nodes[index]):live_paths=game.object_nodes[index].damage_paths
		for path in live_paths:
			_world_path(path.points, Vector2.ZERO, color, 3.5 if path.get("collision", true) else 2.0, object)
		if index == game.selected and game.draw_mode == 4:
			var bounds: Rect2 = game.object_bounds(object)
			var top_left: Vector2 = game.world_to_screen(Vector2(bounds.position.x, bounds.end.y))
			var bottom_right: Vector2 = game.world_to_screen(Vector2(bounds.end.x, bounds.position.y))
			draw_rect(Rect2(top_left - Vector2(7, 7), bottom_right - top_left + Vector2(14, 14)), Color(0.23, 0.52, 0.64, 0.75), false, 1.5)
	if game.structure_links != null: game.structure_links.draw_world(self)
	if game.weapon_lab != null: game.weapon_lab.draw_world(self)
	if game.first_work!=null:game.first_work.draw_world(self)
	if game.pending_building.is_empty():
		for stroke in game.draft:
			_world_path(stroke.points, Vector2.ZERO, Color(0.13, 0.42, 0.48, 0.85), 2.8)
	if game.active_stroke:
		_world_path(game.active_stroke.points, Vector2.ZERO, Color(0.10, 0.52, 0.57, 0.88), 2.8)
	if game.preview_paths != null:
		for path in game.preview_paths:
			_world_path(path.points, Vector2(game.preview_x, game.preview_y), Color(0.63, 0.31, 0.22, 0.65), 3.4)
	_draw_build_preview()
	_draw_weapon_grip_selection()
	_draw_combat()
	if game.flip_timer > 0:
		var progress: float = min(1.0, game.flip_timer / 0.36)
		var edge: float = size.x * (1.0 - progress)
		draw_rect(Rect2(edge, 0, size.x - edge, size.y), Color(1, 0.99, 0.95, progress * 0.9))

func _draw_weapon_grip_selection() -> void:
	if not game.selecting_weapon_grip: return
	var bounds := ShapeMatcher.bounds(game.draft)
	if bounds.is_empty(): return
	var top_left: Vector2 = game.world_to_screen(Vector2(bounds.min_x, bounds.max_y))
	var bottom_right: Vector2 = game.world_to_screen(Vector2(bounds.max_x, bounds.min_y))
	draw_rect(Rect2(top_left - Vector2(10, 10), bottom_right - top_left + Vector2(20, 20)), Color(0.21, 0.44, 0.40, 0.55), false, 1.5)
	var anchor: Vector2 = game.selected_weapon_grip if game.selected_weapon_grip != null else game.grip_hover
	var point: Vector2 = game.world_to_screen(anchor)
	var ink := Color("376f65") if PaperWeaponGrip.accepts(game.draft, anchor) else Color("b05845")
	draw_circle(point, 8, Color("faf7eb"))
	draw_arc(point, 8, 0, TAU, 24, ink, 2, true)
	_line(point + Vector2(-4, 0), point + Vector2(4, 0), ink, 1.5)
	_line(point + Vector2(0, -4), point + Vector2(0, 4), ink, 1.5)
	var hint := "类型已选好后按 3 装备" if game.selecting_weapon_type else "握持点已选中 · 3 选择类型" if game.selected_weapon_grip != null else "点击武器笔迹上的握持位置"
	draw_string(ThemeDB.fallback_font, top_left + Vector2(0, -20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("376f65"))

func _draw_build_preview() -> void:
	if game.placement_preview.is_empty(): return
	var preview: Dictionary = game.placement_preview.object
	var ink := Color(0.18, 0.59, 0.42, 0.75) if game.placement_preview.valid else Color(0.78, 0.28, 0.22, 0.75)
	for path in preview.paths: _world_path(path.points, Vector2.ZERO, ink, 3, preview)
	var location: Vector2 = game.world_to_screen(Vector2(preview.x, preview.y))
	draw_circle(location, 5, ink)
	var font := ThemeDB.fallback_font
	draw_string(font, location + Vector2(12, -12), "可放置" if game.placement_preview.valid else "需要支撑 / 调整位置", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)

func _draw_combat() -> void:
	if game.combat == null: return
	var battle = game.combat
	var font := ThemeDB.fallback_font
	for target in battle.targets:
		var center: Vector2 = game.world_to_screen(target.position)
		var live: bool = target.health > 0
		var ink := Color("bb6c4b") if target.flash > 0 else Color("657369")
		if not live: ink.a = 0.25
		draw_circle(center, 19, Color("f4e7cd"))
		draw_arc(center, 19, 0, TAU, 36, ink, 3, true)
		draw_arc(center, 10, 0, TAU, 24, ink, 2, true)
		draw_circle(center, 3, ink)
		_line(center + Vector2(-9, 19), center + Vector2(-14, 42), ink, 3)
		_line(center + Vector2(9, 19), center + Vector2(14, 42), ink, 3)
		draw_rect(Rect2(center + Vector2(-22, -33), Vector2(44, 4)), Color("d9d4c5"))
		draw_rect(Rect2(center + Vector2(-22, -33), Vector2(44 * target.health / 80.0, 4)), Color("5d8b70"))
		draw_string(font, center + Vector2(-28, -42), "练习靶" if live else "稍后复原", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PaperTheme.MUTED)
	if battle.training:
		var emitter: Vector2 = game.world_to_screen(battle.emitter)
		draw_circle(emitter, 17, Color("8c7568"))
		draw_circle(emitter, 8, Color("4e4843"))
		draw_string(font, emitter + Vector2(-28, -27), "墨弹发射器", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PaperTheme.MUTED)
	# Personal health is shown once in the upper-left HUD.
	for projectile in battle.projectiles:
		if projectile.get("kind", "") in ["arrow", "bullet"]: continue
		var center: Vector2 = game.world_to_screen(projectile.position)
		draw_circle(center, 5, Color("775462"))
		_line(center, center - Vector2(projectile.velocity.x, -projectile.velocity.y).normalized() * 12, Color(0.46, 0.33, 0.38, 0.45), 3)
	for effect in battle.effects:
		var center: Vector2 = game.world_to_screen(effect.position) + Vector2(-15, -66 - (0.8 - effect.time) * 32)
		var tint: Color = effect.color
		tint.a = clampf(effect.time / 0.25, 0, 1)
		draw_string_outline(font, center, effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 3, Color(1, 0.98, 0.94, tint.a))
		draw_string(font, center, effect.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tint)
	for object in game.objects:
		if object.get("role", "") != "building" or object.health >= object.max_health: continue
		var b: Rect2 = game.object_bounds(object)
		var top: Vector2 = game.world_to_screen(Vector2(object.x, b.end.y))
		draw_rect(Rect2(top + Vector2(-24, -13), Vector2(48, 4)), Color("d9d4c5"))
		draw_rect(Rect2(top + Vector2(-24, -13), Vector2(48 * object.health / object.max_health, 4)), Color("5d8b70"))
