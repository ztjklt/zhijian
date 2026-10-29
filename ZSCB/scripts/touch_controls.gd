class_name PaperTouchControls
extends Control

var game = null
var force_visible := false
var stick_center := Vector2.ZERO
var stick_finger := -1
var draw_finger := -1
var stick := Vector2.ZERO
var owners := {}
var attack_rect := Rect2()
var generate_rect := Rect2()
var last_draw := Vector2.ZERO
var radius := 52.0
var pressed_button: Dictionary = {}
var native_mouse_active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_layout)
	_layout()

func enabled() -> bool:
	return force_visible or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func _layout() -> void:
	var viewport := get_viewport_rect().size
	var amount := PaperGuiScale.factor(viewport)
	radius = 52.0 * amount
	var margin := 22.0 * amount
	stick_center = Vector2(margin + radius, viewport.y - radius - 28 * amount)
	attack_rect = Rect2(Vector2(viewport.x, viewport.y) - Vector2(93, 99) * amount, Vector2(72, 72) * amount)
	generate_rect = Rect2(Vector2(viewport.x, viewport.y) - Vector2(179, 82) * amount, Vector2(72, 56) * amount)
	queue_redraw()

func movement_vector() -> Vector2:
	return stick

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		force_visible = true
		if handle_touch(event): get_viewport().set_input_as_handled()
	elif event is InputEventMouse and event.device == -1 and enabled():
		# Owned fingers are handled here; only native text/scroll UI receives emulation.
		if not native_mouse_active:
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			native_mouse_active = false
	# End an owned mouse stroke even if a UI control handles the release.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if game.active_stroke != null or game.drag != null:
			game.pointer_up(event.position)

func handle_touch(event: InputEvent) -> bool:
	if not enabled() or game == null: return false
	if game.lab_open() or game.cooperation_open():
		if event is InputEventScreenTouch:
			if event.canceled: _release(event.index,true);return true
			if not event.pressed:
				var native: bool = owners.get(event.index,"")=="native"
				_release(event.index,false,event.position)
				return not native
			var modal:Control=game.cooperation_panel if game.cooperation_open() else game.weapon_lab_panel
			var button: BaseButton = _button_at(modal,event.position)
			if button != null: owners[event.index]="ui";pressed_button[event.index]=weakref(button);return true
			owners[event.index]="native"
		native_mouse_active=true
		return false
	if game.experience != null and game.experience.visible:
		# The modal owns touch UI; do not turn a button press into stick/attack input.
		native_mouse_active = true
		if event is InputEventScreenTouch:
			if event.pressed: owners[event.index] = "native"
			else: owners.erase(event.index)
		return false
	if event is InputEventScreenTouch:
		if event.canceled:
			_release(event.index, true)
			return true
		if not event.pressed:
			var native: bool = owners.get(event.index, "") == "native"
			if event.index == draw_finger: last_draw = event.position
			_release(event.index, false, event.position)
			return not native
		if not game.bag_open and event.position.distance_to(stick_center) <= radius + 24 * PaperGuiScale.factor(get_viewport_rect().size) and stick_finger == -1:
			stick_finger = event.index
			owners[event.index] = "stick"
			stick = ((event.position - stick_center) / radius).limit_length()
		elif not game.bag_open and attack_rect.has_point(event.position):
			owners[event.index] = "attack"
			# Touch attack aims toward the facing direction, independent of the drawing finger.
			game.aim_world = game.player.position + Vector2(game.facing * 2, .43 if game.combat.is_bow() or game.combat.is_firearm() else 0)
			game.attack()
		elif not game.bag_open and generate_rect.has_point(event.position):
			owners[event.index] = "generate"
			game.input_command("generate")
		else:
			var button: BaseButton = _button_at(game.backpack_panel, event.position) if game.bag_open else game.toolbar.touch_button_at(event.position)
			if button != null:
				owners[event.index] = "ui"
				pressed_button[event.index] = weakref(button)
			elif game.bag_open or game.toolbar.blocks_canvas(event.position):
				# Let the native GUI handle text fields and scrolling.
				owners[event.index] = "native"
				native_mouse_active = true
				return false
			elif draw_finger == -1:
				draw_finger = event.index
				owners[event.index] = "draw"
				last_draw = event.position
				game.pointer_down(event.position)
			else: owners[event.index] = "ignore"
	elif event is InputEventScreenDrag:
		if event.index == stick_finger: stick = ((event.position - stick_center) / radius).limit_length()
		elif event.index == draw_finger:
			last_draw = event.position
			if not game.toolbar.blocks_canvas(event.position): game.pointer_move(event.position)
		elif owners.get(event.index, "") == "native": return false
	queue_redraw()
	return true

func _release(index: int, canceled: bool, position_on_release: Vector2 = Vector2.INF) -> void:
	if index == stick_finger:
		stick_finger = -1
		stick = Vector2.ZERO
	if index == draw_finger:
		draw_finger = -1
		if canceled: game.cancel_pointer()
		else: game.pointer_up(last_draw)
	if pressed_button.has(index):
		var button = pressed_button[index].get_ref()
		if not canceled and is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(position_on_release):
			if button is MenuButton: button.show_popup()
			else: button.pressed.emit()
		pressed_button.erase(index)
	owners.erase(index)
	queue_redraw()

func reset() -> void:
	stick_finger = -1
	draw_finger = -1
	stick = Vector2.ZERO
	owners.clear()
	pressed_button.clear()
	native_mouse_active = false
	if game != null: game.cancel_pointer()
	queue_redraw()

func _button_at(node: Node, point: Vector2) -> BaseButton:
	if node is Control and (not node.is_visible_in_tree() or (node.clip_contents and not node.get_global_rect().has_point(point))): return null
	var children := node.get_children()
	children.reverse()
	for child in children:
		var result := _button_at(child, point)
		if result != null: return result
	if node is BaseButton and node.is_visible_in_tree() and not node.disabled and node.get_global_rect().has_point(point):
		return node
	return null

func _process(_delta: float) -> void:
	visible = enabled() and game != null and not game.bag_open
	if not visible and stick_finger != -1: reset()
	queue_redraw()

func _draw() -> void:
	if not enabled(): return
	var amount := PaperGuiScale.factor(get_viewport_rect().size)
	var fill := Color(0.99, 0.98, 0.93, 0.88)
	var ink := Color("376f65")
	draw_circle(stick_center, radius + 6 * amount, fill)
	draw_arc(stick_center, radius + 6 * amount, 0, TAU, 48, Color(0.21, 0.44, 0.4, 0.32), 2, true)
	draw_circle(stick_center + stick * (radius - 8 * amount), 22 * amount, Color(0.21, 0.44, 0.40, 0.65))
	var font := ThemeDB.fallback_font
	for offset in [Vector2(-42, 5), Vector2(34, 5), Vector2(-5, -34), Vector2(-5, 43)]:
		var text := "←" if offset.x < -10 else "→" if offset.x > 10 else "↑" if offset.y < 0 else "↓"
		draw_string(font, stick_center + offset * amount, text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(17 * amount), ink)
	draw_circle(attack_rect.get_center(), 36 * amount, ink)
	draw_string(font, attack_rect.position + Vector2(16, 43) * amount, "攻击", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(18 * amount), PaperTheme.PAPER)
	draw_style_box(PaperTheme.panel(fill, 14), generate_rect)
	draw_string(font, generate_rect.position + Vector2(17, 34) * amount, "放置" if not game.pending_building.is_empty() else "落下" if game.draw_mode == 3 else "生成", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(18 * amount), ink)
