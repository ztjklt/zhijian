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
var jump_rect := Rect2()
var jump_finger := -1
var last_draw := Vector2.ZERO
var radius := 52.0
var pressed_button: Dictionary = {}
var native_mouse_active := false
var scroll_gestures: Dictionary = {}
var primary_contexts: Dictionary = {}
var skill_rects: Dictionary = {}
var pulses: Dictionary = {}
var seals: Texture2D

func _hold_button(index: int, button: BaseButton) -> void:
	pressed_button[index] = weakref(button)
	if button is PaperSealButton: button._press(1)

func _hit(rect: Rect2, point: Vector2) -> bool:
	return rect.has_area() and point.distance_to(rect.get_center()) <= minf(rect.size.x,rect.size.y)*.5

func primary_button() -> BaseButton:
	if game == null or game.placing_blueprint_id >= 0 or game.selecting_weapon_type: return null
	if game.draw_mode == 4:
		return game.toolbar.carry_button if game.connection_tool == "move" else null
	return game.toolbar.confirm_button if not game.pending_match.is_empty() else game.toolbar.generate_button

func primary_label() -> String:
	var button := primary_button()
	if button == null: return ""
	if button == game.toolbar.carry_button: return "放下" if game.carried_id != "" else "拿起"
	if button == game.toolbar.confirm_button: return "采用"
	if game.selecting_weapon_grip: return "选类型" if game.selected_weapon_grip != null else "选握点"
	if not game.pending_building.is_empty(): return "放置"
	if game.draw_mode == 2: return "选握点"
	return "塑形" if game.draw_mode == 5 else "生成"

func attack_available() -> bool:
	return not game.selecting_weapon_grip and (game.combat.bow_equipped or not game.equipped_weapon.get("paths", []).is_empty())

func _select_touch_grip(point: Vector2, report_miss: bool) -> void:
	var world: Vector2 = game.screen_to_world(point)
	game.grip_hover = world
	var tolerance: float = 22.0 * PaperGuiScale.factor(get_viewport_rect().size) / game.PIXELS_PER_UNIT
	var snapped: Variant = PaperWeaponGrip.snap_point(game.draft, world, tolerance)
	if snapped != null:
		if game.selected_weapon_grip == null or not game.selected_weapon_grip.is_equal_approx(snapped): game.select_weapon_grip(snapped)
	elif report_miss:
		game.message("请点武器线条附近，握点会自动贴到笔迹上")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if ResourceLoader.exists("res://assets/ui/modes/seals.png"): seals = load("res://assets/ui/modes/seals.png")

func enabled() -> bool:
	return force_visible or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func _layout() -> void:
	if not owners.is_empty():
		game.retain_active_stroke()
		reset()
	var viewport := get_viewport_rect().size
	var amount := PaperGuiScale.factor(viewport)
	var logical := PaperGuiScale.safe_rect(self)
	var bounds := Rect2(logical.position * amount, logical.size * amount)
	radius = 52.0 * amount
	var margin := 22.0 * amount
	stick_center = Vector2(bounds.position.x + margin + radius, bounds.end.y - radius - 28 * amount)
	var center := bounds.end - Vector2(53,76) * amount
	attack_rect = Rect2(center-Vector2.ONE*39*amount,Vector2.ONE*78*amount)
	generate_rect = Rect2(center+Vector2(15,-112)*amount-Vector2.ONE*29*amount,Vector2.ONE*58*amount)
	jump_rect = Rect2(center+Vector2(-66,38)*amount-Vector2.ONE*25*amount,Vector2.ONE*50*amount)
	skill_rects.clear()
	for slot in [1,2,5]:
		var offset: Vector2 = {1:Vector2(-109,-4),2:Vector2(-92,-62),5:Vector2(-50,-115)}[slot]
		skill_rects[slot] = Rect2(center+offset*amount-Vector2.ONE*26*amount,Vector2.ONE*52*amount)
	queue_redraw()

func movement_vector() -> Vector2:
	return stick

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var was_enabled := enabled()
		force_visible = true
		if not was_enabled: game.toolbar._layout()
		if handle_touch(event): get_viewport().set_input_as_handled()
	elif event is InputEventMouse and event.device == -1 and enabled():
		# Owned fingers are handled here; only native text/scroll UI receives emulation.
		# Some platforms deliver the emulated mouse press before ScreenTouch.
		if game.bag_open and _text_field_at(game.backpack_panel, event.position):
			native_mouse_active = true
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
	if game.landscape_guard != null and game.landscape_guard.is_active():
		if not owners.is_empty(): game.retain_active_stroke(); reset()
		return true
	var modal: Control = null
	if game.next_steps_open(): modal = game.next_steps
	elif game.cooperation_open(): modal = game.cooperation_panel
	elif game.lab_open(): modal = game.weapon_lab_panel
	elif game.experience != null and game.experience.visible: modal = game.experience
	elif game.bag_open: modal = game.backpack_panel
	if modal != null:
		if event is InputEventScreenTouch:
			if event.canceled: _release(event.index,true);return true
			if not event.pressed:
				var native: bool = owners.get(event.index,"")=="native"
				_release(event.index,false,event.position)
				return not native
			var scroll := _scroll_at(modal, event.position)
			if scroll != null:
				scroll_gestures[event.index] = {"node": weakref(scroll), "start": event.position, "last": event.position}
			var button: BaseButton = _button_at(modal,event.position)
			if button != null: owners[event.index]="ui";_hold_button(event.index,button);return true
			if scroll != null and not _text_field_at(modal, event.position):
				owners[event.index] = "scroll"
				return true
			owners[event.index]="native"
			native_mouse_active = true
			return false
		if event is InputEventScreenDrag: return _scroll_drag(event)
	if event is InputEventScreenTouch:
		if event.canceled:
			_release(event.index, true)
			return true
		if not event.pressed:
			var native: bool = owners.get(event.index, "") == "native"
			if event.index == draw_finger and not game.toolbar.blocks_canvas(event.position): last_draw = event.position
			_release(event.index, false, event.position)
			return not native
		# Real UI owns its hit area before the floating thumb controls.
		var ui_button: BaseButton = game.toolbar.touch_button_at(event.position)
		if ui_button != null:
			owners[event.index] = "ui"
			_hold_button(event.index,ui_button)
			return true
		if game.selecting_weapon_type:
			owners[event.index] = "ignore"
			return true
		if game.toolbar.mobile_navigation_open():
			if game.toolbar.blocks_canvas(event.position):
				owners[event.index] = "native"; native_mouse_active = true; return false
			owners[event.index] = "ignore"
			return true
		if game.knowledge_world != null and game.knowledge_world.overview:
			owners[event.index] = "ignore"
			game.pointer_down(event.position)
			return true
		for slot in skill_rects:
			if _hit(skill_rects[slot],event.position):
				owners[event.index] = "skill_"+str(slot)
				queue_redraw()
				return true
		if not game.bag_open and event.position.distance_to(stick_center) <= radius + 24 * PaperGuiScale.factor(get_viewport_rect().size) and stick_finger == -1 and not jump_rect.has_point(event.position):
			stick_finger = event.index
			owners[event.index] = "stick"
			stick = ((event.position - stick_center) / radius).limit_length()
		elif not game.bag_open and _hit(attack_rect,event.position):
			owners[event.index] = "attack"
			pulses["attack"] = 1.0
			# Touch attack aims toward the facing direction, independent of the drawing finger.
			if attack_available():
				game.aim_world = game.player.position + Vector2(game.facing * 2, .43 if game.combat.is_bow() or game.combat.is_firearm() else 0)
				game.attack()
		elif not game.bag_open and primary_button() != null and _hit(generate_rect,event.position):
			owners[event.index] = "generate"
			var button := primary_button()
			if not button.disabled:
				_hold_button(event.index,button)
				primary_contexts[event.index] = game.creation_context
		elif not game.bag_open and _hit(jump_rect,event.position):
			owners[event.index] = "jump"
			if jump_finger == -1:
				jump_finger = event.index
				Input.action_press("touch_jump")
		else:
			var button: BaseButton = _button_at(game.backpack_panel, event.position) if game.bag_open else game.toolbar.touch_button_at(event.position)
			if button != null:
				owners[event.index] = "ui"
				_hold_button(event.index,button)
			elif game.bag_open or game.toolbar.blocks_canvas(event.position):
				# Let the native GUI handle text fields and scrolling.
				owners[event.index] = "native"
				native_mouse_active = true
				return false
			elif draw_finger == -1:
				draw_finger = event.index
				owners[event.index] = "draw"
				last_draw = event.position
				if game.selecting_weapon_grip: _select_touch_grip(event.position, true)
				else: game.pointer_down(event.position)
			else: owners[event.index] = "ignore"
	elif event is InputEventScreenDrag:
		if event.index == stick_finger: stick = ((event.position - stick_center) / radius).limit_length()
		elif event.index == draw_finger:
			if not game.toolbar.blocks_canvas(event.position): game.pointer_move(event.position)
			if not game.toolbar.blocks_canvas(event.position):
				last_draw = event.position
				if game.selecting_weapon_grip: _select_touch_grip(event.position, false)
		elif owners.get(event.index, "") == "native": return false
	queue_redraw()
	return true

func _release(index: int, canceled: bool, position_on_release: Vector2 = Vector2.INF) -> void:
	var owner: String = owners.get(index,"")
	if owner.begins_with("skill_"):
		var slot := int(owner.trim_prefix("skill_"))
		if not canceled and _hit(skill_rects.get(slot,Rect2()),position_on_release):
			if draw_finger != -1:
				game.retain_active_stroke()
				owners[draw_finger] = "ignore"
				draw_finger = -1
			game.toolbar.select_tool(slot)
			pulses[owner] = 1.0
	if index == jump_finger:
		jump_finger = -1
		Input.action_release("touch_jump")
	scroll_gestures.erase(index)
	if index == stick_finger:
		stick_finger = -1
		stick = Vector2.ZERO
	if index == draw_finger:
		draw_finger = -1
		if canceled: game.cancel_pointer()
		else: game.pointer_up(last_draw)
	if pressed_button.has(index):
		var button = pressed_button[index].get_ref()
		if is_instance_valid(button) and button is PaperSealButton: button._press(0)
		var is_primary: bool = owners.get(index, "") == "generate"
		var hit: bool = _hit(generate_rect,position_on_release) if is_primary else is_instance_valid(button) and button.get_global_rect().has_point(position_on_release)
		if not is_primary and is_instance_valid(button) and button is PaperSealButton: hit = button._has_point(button.get_global_transform().affine_inverse()*position_on_release)
		var current: bool = not is_primary or (button == primary_button() and primary_contexts.get(index, -1) == game.creation_context)
		if not canceled and hit and current and is_instance_valid(button) and (is_primary or button.is_visible_in_tree()) and not button.disabled:
			if is_primary and draw_finger != -1:
				game.retain_active_stroke()
				owners[draw_finger] = "ignore"
				draw_finger = -1
			if button is MenuButton or button is OptionButton: button.show_popup()
			else: button.pressed.emit()
			pulses[owner] = 1.0
		pressed_button.erase(index)
	primary_contexts.erase(index)
	owners.erase(index)
	queue_redraw()

func reset() -> void:
	if jump_finger >= 0: Input.action_release("touch_jump")
	jump_finger = -1
	stick_finger = -1
	draw_finger = -1
	stick = Vector2.ZERO
	owners.clear()
	for reference in pressed_button.values():
		var button = reference.get_ref()
		if is_instance_valid(button) and button is PaperSealButton and button.is_inside_tree(): button._press(0)
	pressed_button.clear()
	primary_contexts.clear()
	pulses.clear()
	scroll_gestures.clear()
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
		if node is PaperSealButton and not node._has_point(node.get_global_transform().affine_inverse()*point): return null
		return node
	return null

func _scroll_at(node: Node, point: Vector2) -> ScrollContainer:
	if node is Control and (not node.is_visible_in_tree() or (node.clip_contents and not node.get_global_rect().has_point(point))): return null
	for child in node.get_children():
		var found := _scroll_at(child, point)
		if found != null: return found
	if node is ScrollContainer and node.get_global_rect().has_point(point) and node.get_v_scroll_bar().max_value > node.size.y:
		return node
	return null

func _text_field_at(node: Node, point: Vector2) -> bool:
	if node is Control and not node.is_visible_in_tree(): return false
	if (node is LineEdit or node is TextEdit) and node.get_global_rect().has_point(point): return true
	for child in node.get_children():
		if _text_field_at(child, point): return true
	return false

func _scroll_drag(event: InputEventScreenDrag) -> bool:
	if owners.get(event.index, "") == "native": return false
	if not scroll_gestures.has(event.index): return owners.get(event.index, "") != "native"
	var gesture: Dictionary = scroll_gestures[event.index]
	if event.position.distance_to(gesture.start) < 10 and owners.get(event.index) == "ui": return true
	var scroll: ScrollContainer = gesture.node.get_ref()
	if is_instance_valid(scroll):
		scroll.scroll_vertical -= roundi((event.position.y - gesture.last.y) / scroll.get_global_transform().get_scale().y)
	gesture.last = event.position
	owners[event.index] = "scroll"
	if pressed_button.has(event.index):
		var button = pressed_button[event.index].get_ref()
		if is_instance_valid(button) and button is PaperSealButton: button._press(0)
	pressed_button.erase(event.index)
	return true

func _process(delta: float) -> void:
	visible = enabled() and game != null and not game.bag_open and not game.personal_overlay_open() and not game.selecting_weapon_type and (game.knowledge_world == null or not game.knowledge_world.overview)
	var gameplay_owned: bool = stick_finger != -1 or jump_finger != -1 or draw_finger != -1 or owners.values().any(func(owner): return owner in ["attack","generate"] or str(owner).begins_with("skill_"))
	if not visible and gameplay_owned:
		game.retain_active_stroke()
		reset()
	for key in pulses.keys():
		pulses[key] = maxf(0,float(pulses[key])-delta*4)
		if pulses[key] <= 0: pulses.erase(key)
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
	_seal(attack_rect,"攻击" if attack_available() else "未装备","attack",0,attack_available(),false)
	_seal(jump_rect,"跳跃","jump",-1,true,false)
	for slot in skill_rects:
		_seal(skill_rects[slot],{1:"造物",2:"武器",5:"塑形"}[slot],"skill_"+str(slot),{1:2,2:1,5:3}[slot],true,game.draw_mode in [1,3] if slot==1 else game.draw_mode==slot)
	var primary := primary_button()
	if primary != null:
		_seal(generate_rect,primary_label(),"generate",-1,not primary.disabled,true)

func _seal(rect: Rect2, label: String, key: String, cell: int, available: bool, selected: bool) -> void:
	var amount := PaperGuiScale.factor(get_viewport_rect().size)
	var center := rect.get_center()
	var held: bool = owners.values().has(key)
	var pulse: float = pulses.get(key,0.0)
	var box := rect.grow(-2*amount if held else pulse*2*amount)
	draw_circle(center+Vector2(0,2)*amount,rect.size.x*.49,Color(.14,.22,.18,.10))
	var color := Color("315f52") if available else Color("8e958c")
	if cell < 0 or seals == null or selected: draw_circle(center,box.size.x*.48,Color("edf1e6") if selected else Color("faf8ef"))
	if seals != null and cell >= 0:
		var atlas := Rect2(Vector2(cell%2,cell/2)*seals.get_size()*.5,seals.get_size()*.5)
		draw_texture_rect_region(seals,box,atlas,Color(1,1,1,.92 if available else .45))
	if selected or cell < 0: draw_arc(center,box.size.x*.48,0,TAU,64,Color(color,.8 if selected else .28),2*amount if selected else amount,true)
	if pulse > 0:
		draw_arc(center,rect.size.x*(.5+(1-pulse)*.12),0,TAU,48,Color(color,pulse*.45),amount,true)
	var font := ThemeDB.fallback_font
	var font_size := roundi((14 if rect.size.x/amount>=58 else 12)*amount)
	var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var baseline: float = center.y+(rect.size.y*.30 if cell>=0 else 5*amount)
	if cell >= 0: draw_circle(Vector2(center.x,baseline-4*amount),width*.58,Color("faf8ef"))
	draw_string(font,Vector2(center.x-width*.5,baseline),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
