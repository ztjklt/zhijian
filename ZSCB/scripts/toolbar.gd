class_name PaperCastleToolbar
extends Control

var game = null
var header: PanelContainer
var bottom: PanelContainer
var footer: HBoxContainer
var compact_delete: Button
var guide_panel: PanelContainer
var header_stack: VBoxContainer
var header_row: HBoxContainer
var mode_group: HBoxContainer
var mode_buttons: Array[Button] = []
var brand_title: Label
var subtitle: Label
var vitals: Control
var help_button: Button
var training_button: Button
var bag_button: Button
var works: MenuButton
var action_title: Label
var status_label: Label
var generator_button: Button
var own_button: Button
var candidate_button: Button
var confirm_button: Button
var generate_button: Button
var undo_button: Button
var redo_button: Button
var delete_button: Button
var carry_button: Button
var grip_cancel_button: Button
var clear_button: Button
var building_button: Button
var connection_button: Button
var lab_button: Button
var cooperation_button: Button
var mode_button: Button
var tool_button: Button
var move_button: Button
var guide_title: Label
var guide_body: Label
var guide_skip: Button
var guide_action:Button
var first_work_action:Button
var first_work_skip:Button
var status_text := ""
var status_time := 0.0
var last_state := ""
var free_button: Button
var top_actions: HBoxContainer
var map_button: Button
var navigation_open := false

func _ready() -> void:
	theme = PaperTheme.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	header = PanelContainer.new()
	add_child(header)
	header_stack = VBoxContainer.new()
	header.add_child(header_stack)
	header_row = HBoxContainer.new()
	header_stack.add_child(header_row)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 1)
	header_row.add_child(brand)
	brand_title = _label(brand, "纸间", 23)
	subtitle = _label(brand, "边走 · 边画 · 边战斗", 11, PaperTheme.MUTED)
	brand_title.visible = false
	vitals = preload("res://scripts/vitals_hud.gd").new()
	vitals.toolbar = self
	brand.add_child(vitals)
	mode_group = HBoxContainer.new()
	header_row.add_child(mode_group)
	for i in range(5):
		var slot: int = [1, 3, 2, 4, 5][i]
		var button := _button(mode_group, ["1 造物", "2 建筑", "3 武器", "4 移动", "5 塑形"][i], func():
			if slot == 5: game.toggle_sculpt()
			else: game.activate_draw_mode(slot))
		button.custom_minimum_size = Vector2(70, 44)
		button.tooltip_text = ["1 开始多笔绘画，再按 1 生成动态实体", "2 开始多笔建筑绘画，再按 2 生成并下落", "3 画武器 → 3 选择笔迹握点 → 3 选类型 → 3 装备", "按住已有造物拖动；选中后点拆除或按 Delete。朋友开放协作后也可搬动／连接，拆除仍归作者。", "5 开始多笔绘画，再按 5 自动规整为几何部件；Esc 返回"][i]
		mode_buttons.append(button)
	tool_button = mode_buttons[0]
	move_button = mode_buttons[3]
	bag_button = _button(mode_group, "6 图纸", func(): game.toggle_bag())
	bag_button.tooltip_text = "收藏生成过的作品；选图纸可再次放置或装备。Shift+1–6 快速取用。"
	training_button = _button(header_row, "练习场", func():
		if game.combat != null:
			game.combat.set_training(not game.combat.training)
			game.message("练习已开启：画武器打靶，画墙挡住墨弹" if game.combat.training else "已结束练习，继续自由创作"))
	mode_button = training_button
	top_actions = HBoxContainer.new()
	add_child(top_actions)
	map_button = _button(top_actions, "地图", func(): navigation_open = not navigation_open)
	map_button.icon = PaperTheme.icon("map")
	works = MenuButton.new()
	works.text = "作品"
	works.custom_minimum_size = Vector2(48, 44)
	works.focus_mode = Control.FOCUS_NONE
	top_actions.add_child(works)
	works.icon = PaperTheme.icon("works")
	works.get_popup().add_item("保存作品", 0)
	works.get_popup().add_item("练习场 开 / 关", 6)
	works.get_popup().add_item("读取作品", 1)
	works.get_popup().add_separator()
	works.get_popup().add_item("本版体验 / 更新总览", 2)
	works.get_popup().add_item("显示 / 隐藏触控", 3)
	works.get_popup().add_separator()
	works.get_popup().add_item("切换短弓 / 近战  Q", 4)
	works.get_popup().add_item("纸间土著 开 / 关  N", 5)
	works.get_popup().add_separator()
	works.get_popup().add_item("返回地图选择（保留当前进度）", 7)
	works.get_popup().add_item("返回封面（保留当前进度）", 8)
	works.get_popup().add_item("保存并返回封面", 9)
	works.get_popup().add_item("武器试打 / 方案对照", 10)
	works.get_popup().add_item("双人协作 / 共同搭建", 11)
	works.get_popup().add_item("第一件作品 / 新手引导", 12)
	works.get_popup().id_pressed.connect(func(id: int):
		if id == 6: training_button.pressed.emit()
		elif id == 0: game.save_game()
		elif id == 1: game.load_game()
		elif id == 2: _show_experience()
		elif id == 4: game.combat.toggle_bow()
		elif id == 5: game.combat.set_natives(not game.combat.natives_enabled)
		elif id == 7: game.return_to_map_select()
		elif id == 8: game.return_to_map_select("res://scenes/title_menu.tscn")
		elif id == 9: game.save_and_return_to_title()
		elif id == 10: game.open_weapon_lab()
		elif id == 11: game.open_cooperation()
		elif id == 12: game.first_work.start();last_state="";update_buttons()
		elif id == 3 and game.touch_controls != null:
			game.touch_controls.force_visible = not game.touch_controls.force_visible
			_layout())
	help_button = _button(header_row, "本版体验", _show_experience)
	help_button.custom_minimum_size.x = 40
	_build_guide()
	_build_actions()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _label(parent: Node, text: String, font_size: int = 15, color: Color = PaperTheme.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 20: PaperTheme.heading(label)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(48, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_guide() -> void:
	guide_panel = PanelContainer.new()
	add_child(guide_panel)
	var stack := VBoxContainer.new()
	guide_panel.add_child(stack)
	_label(stack, "第一件作品", 12, PaperTheme.TEAL)
	guide_title = _label(stack, "画一把自己的武器", 21)
	guide_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_body = _label(stack, "按 3 画武器，可以多笔补画。WASD 可以同时移动。", 14, PaperTheme.MUTED)
	guide_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_body.custom_minimum_size = Vector2(220, 80)
	guide_action=_button(stack,"下一步",func():game.first_work.action())
	guide_action.visible=false
	guide_skip = _button(stack, "明白了，开始创作", func():
		if game.first_work!=null and game.first_work.visible:game.first_work.dismiss()
		else:game.onboarding.dismiss())
	guide_skip.add_theme_font_size_override("font_size", 12)

func _build_actions() -> void:
	bottom = PanelContainer.new()
	# The tools float on the world. Only their actual buttons consume input;
	# an invisible enclosing rectangle must not steal drawing gestures.
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(2)
	bottom.add_theme_stylebox_override("panel", empty)
	add_child(bottom)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 4)
	bottom.add_child(rows)
	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 5)
	rows.add_child(actions)
	action_title = _label(actions, "自由造物", 14)
	action_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	free_button = _button(actions, "1 自由绘制", func(): game.activate_draw_mode(1))
	mode_buttons[1].reparent(actions)
	mode_group.reparent(rows)
	rows.move_child(mode_group, 1)
	for index in [0, 2, 3, 4]:
		var button := mode_buttons[index]
		button.icon = PaperTheme.icon({0:"create",2:"weapon",3:"move",4:"sculpt"}[index])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 26)
	bag_button.icon = PaperTheme.icon("blueprint")
	bag_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	bag_button.add_theme_constant_override("icon_max_width", 26)
	own_button = _button(actions, "原笔迹", func(): _choose_generator("own"))
	generator_button = _button(actions, "素材识别", func(): _choose_generator("library"))
	building_button = _button(actions, "结构：自动 ▸", func():
		var index: int = DrawingRules.BUILD_KINDS.find(game.build_kind)
		game.build_kind = DrawingRules.BUILD_KINDS[(index + 1) % DrawingRules.BUILD_KINDS.size()]
		if not game.pending_building.is_empty():
			game.pending_building = {}
			game.prepare_building()
		game.message("建筑结构：" + _building_name() + " · 再点此按钮可以换一种"))
	candidate_button = _button(actions, "换候选", func(): game.next_candidate())
	confirm_button = _button(actions, "1 采用候选", func(): game.confirm_candidate())
	generate_button = _button(actions, "确认生成", func(): game.generate())
	PaperTheme.primary(generate_button)
	grip_cancel_button = _button(actions, "返回绘画", func(): game.cancel_weapon_grip())
	clear_button = _button(actions, "清空", func():
		game.cancel_weapon_grip(false)
		game.record()
		game.cancel_pointer()
		game.draft = []
		if game.draw_mode == 2: game.refine_model_fill = null; game.refine_weapon_type = ""
		game.mode_drafts[game.draw_mode] = []
		game.pending_building = {}
		game.placement_preview = {}
		game.clear_candidate())
	compact_delete = _button(actions, "拆除选中结构", func(): game.delete_selected())
	carry_button = _button(actions, "G 拿起", func(): game.toggle_carry())
	lab_button = _button(actions, "武器试打", func():game.open_weapon_lab())
	cooperation_button=_button(actions,"双人协作",func():game.open_cooperation())
	connection_button = _button(actions, "操作：移动 ▸", func():
		var choices := ["move", "fixed", "hinge", "unlink"]
		game.set_connection_tool(choices[(choices.find(game.connection_tool)+1)%choices.size()]))
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer = foot
	rows.add_child(foot)
	status_label = _label(foot, "", 12, PaperTheme.INK)
	status_label.add_theme_color_override("font_shadow_color", Color(1, 0.99, 0.95, 0.8))
	status_label.add_theme_constant_override("shadow_offset_x", 0)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 100
	undo_button = _button(foot, "撤销", func(): game.undo())
	redo_button = _button(foot, "重做", func(): game.redo())
	delete_button = _button(foot, "拆除", func(): game.delete_selected())
	first_work_action=_button(foot,"下一步",func():game.first_work.action())
	first_work_skip=_button(foot,"跳过",func():game.first_work.dismiss())
	for button in [first_work_action,first_work_skip]:button.custom_minimum_size=Vector2(0,30);button.add_theme_font_size_override("font_size",12);button.hide()
	_floating_button(carry_button)
	for button in [undo_button, redo_button, delete_button]:
		button.custom_minimum_size.y = 30
		button.add_theme_font_size_override("font_size", 12)
	for row in [actions, foot]:
		for control in row.get_children():
			if control is Button: _floating_button(control, control == generate_button)
	bottom.minimum_size_changed.connect(_fit_actions_height)

func _floating_button(button: Button, primary := false, selected := false) -> void:
	# Alpha belongs to the small background, never to text or the whole HUD.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		var color := Color(1.0, 0.985, 0.94, 0.68)
		if selected: color = Color(0.77, 0.86, 0.82, 0.76)
		if primary: color = Color(Color("23494b"), 0.78)
		if state == "hover": color.a = 0.84
		elif state == "pressed": color.a = 0.82
		elif state == "disabled": color = Color(0.96, 0.95, 0.91, 0.62)
		style.bg_color = color
		style.border_color = Color(PaperTheme.TEAL, 0.32 if state == "hover" else 0.12)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, PaperTheme.PAPER if primary else PaperTheme.TEAL if selected else PaperTheme.INK)
	button.add_theme_color_override("font_disabled_color", Color("727d77"))

func _layout_actions(viewport: Vector2) -> void:
	var compact := viewport.y < 500 or viewport.x < 600
	var width := minf(760, viewport.x - 24)
	bottom.custom_minimum_size.x = 0
	bottom.size.x = width
	mode_group.custom_minimum_size.x = 0
	mode_group.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.reset_size()
	bottom.size.x = width
	_fit_actions_height.call_deferred()

func _fit_actions_height() -> void:
	if bottom == null or not is_inside_tree(): return
	bottom.size.y = bottom.get_combined_minimum_size().y
	var viewport := PaperGuiScale.logical_size(self)
	var compact := viewport.x < 600 or viewport.y < 500
	bottom.position = Vector2((viewport.x-bottom.size.x)*0.5, header.get_rect().end.y+10 if compact else viewport.y-bottom.size.y-16)

func _layout() -> void:
	if not header or not bottom: return
	var viewport := PaperGuiScale.apply(self)
	var compact := viewport.y < 500 or viewport.x < 600
	var style := PaperTheme.panel()
	style.set_content_margin_all(10 if compact else 14)
	header.add_theme_stylebox_override("panel", style)
	header.position = Vector2(12 if compact else 24, 12 if compact else 22)
	header.size = Vector2(192 if compact else 232, 68 if compact else 82)
	help_button.hide()
	training_button.hide()
	subtitle.hide()
	header.reset_size()
	top_actions.reset_size()
	top_actions.position = Vector2(viewport.x-top_actions.size.x-(12 if compact else 24), header.position.y)
	for button in [map_button, works]:
		button.add_theme_constant_override("icon_max_width", 20)
		button.custom_minimum_size = Vector2(64 if compact else 78, 38 if compact else 44)
		button.add_theme_font_size_override("font_size", 14 if compact else 16)
	mode_group.add_theme_constant_override("separation", 5 if compact else 10)
	for button in [tool_button,mode_buttons[2],move_button,mode_buttons[4],bag_button]:
		button.custom_minimum_size = Vector2(58 if viewport.x < 600 else 74, 60 if compact else 72)
		button.add_theme_font_size_override("font_size", 14 if compact else 16)
		button.add_theme_constant_override("icon_max_width", 22 if compact else 26)
	mode_buttons[1].custom_minimum_size = Vector2(70,36)
	guide_panel.size = Vector2(252, 240)
	guide_panel.position = Vector2(20, header.get_rect().end.y + 14)
	PaperGuiScale.popup(works.get_popup(), scale.x)
	last_state = ""
	update_buttons()

func _select_dock(button: Button, active: bool) -> void:
	var style := PaperTheme.surface(PaperTheme.TEAL if active else PaperTheme.PAPER, 9)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_color_override("font_color", PaperTheme.PAPER if active else PaperTheme.INK)
	button.add_theme_color_override("icon_normal_color", PaperTheme.PAPER if active else PaperTheme.INK)

func _choose_tool(value: String) -> void:
	game.set_draw_mode(4 if value == "move" else 1)

func _choose_generator(value: String) -> void:
	game.creation_context += 1
	game.generator = value
	game.clear_candidate()
	game.message("保留原始笔迹" if value == "own" else "画出轮廓，再选择相近的形状")

func _show_help() -> void:
	game.onboarding.restart(not game.objects.is_empty() or not game.equipped_weapon.is_empty())
	game.message("1 自由 2 建筑 3 武器 4 移动/拆除 5 塑形 6 图纸；W/空格二连跳，双击 S 下平台；左键画，右键攻击。")

func _show_experience() -> void:
	if game.experience != null: game.experience.open()

func _building_name() -> String:
	return {"auto": "自动识别", "freehand": "原笔迹"}.get(game.build_kind, BlueprintBag.NAMES.get(game.build_kind, "建筑"))

func set_status(text: String) -> void:
	status_text = text
	status_time = 4.5
	last_state = ""

func _process(delta: float) -> void:
	if game == null: return
	if status_time > 0:
		status_time -= delta
		if status_time <= 0: status_text = ""
	update_buttons()

func update_buttons() -> void:
	if game == null or generate_button == null: return
	var viewport := PaperGuiScale.apply(self)
	var compact := viewport.y < 500 or viewport.x < 600
	var work:bool=game.first_work!=null and game.first_work.visible
	var state := str([navigation_open, game.placement_preview.get("reason", ""), game.draw_mode, game.connection_tool, game.draft.size(), game.generator, game.build_kind, game.pending_building.size(), game.selecting_weapon_grip, game.selecting_weapon_type, game.selected_weapon_type, game.selected_weapon_grip, game.selected, game.carried_id, game.pending_match.size(), game.candidate_index, game.undo_stack.size(), game.redo_stack.size(), game.onboarding.stage, game.onboarding.visible, game.bag_open, game.weapon_lab.brief, status_text, compact,work,game.first_work.stage if work else 0,game.first_work.notice if work else "",game.personal_overlay_open()])
	if state == last_state: return
	last_state = state
	bottom.visible = not game.bag_open
	var candidate: bool = not game.pending_match.is_empty()
	for index in [0,2,3,4]: _select_dock(mode_buttons[index], game.draw_mode in [1,3] if index == 0 else game.draw_mode == [1,3,2,4,5][index])
	_select_dock(bag_button, game.bag_open)
	mode_buttons[1].visible = game.draw_mode in [1,3]
	free_button.visible = game.draw_mode in [1,3]
	_floating_button(mode_buttons[1], false, game.draw_mode == 3)
	_floating_button(free_button, false, game.draw_mode == 1)
	own_button.visible = game.draw_mode == 1 and not compact
	generator_button.visible = game.draw_mode == 1 and not compact
	_floating_button(own_button, false, game.generator == "own")
	_floating_button(generator_button, false, game.generator == "library")
	building_button.visible = game.draw_mode == 3
	lab_button.visible = game.draw_mode == 2 and not game.selecting_weapon_grip
	connection_button.visible = game.draw_mode == 4
	carry_button.visible = game.draw_mode == 4
	carry_button.text = "G 放下" if game.carried_id != "" else "G 拿起"
	cooperation_button.visible=game.draw_mode==4
	connection_button.text = "操作：" + {"move":"移动", "fixed":"固定连接", "hinge":"转轴", "unlink":"解除连接"}[game.connection_tool] + " ▸"
	building_button.text = "轮廓：" + _building_name() + " ▸"
	candidate_button.visible = candidate
	confirm_button.visible = candidate
	grip_cancel_button.visible = game.selecting_weapon_grip
	generate_button.visible = not candidate and game.draw_mode != 4
	generate_button.disabled = game.selected_weapon_grip == null if game.selecting_weapon_grip else game.draft.is_empty() and game.pending_building.is_empty() and game.active_stroke == null
	generate_button.text = "3 确认装备" if game.selecting_weapon_type else "3 选择类型" if game.selecting_weapon_grip else "放置" if not game.pending_building.is_empty() else "3 选择握点" if game.draw_mode == 2 else "2 确认生成" if game.draw_mode == 3 else "5 确认塑形" if game.draw_mode == 5 else "1 确认生成"
	footer.visible = true
	compact_delete.visible = compact and game.draw_mode == 4
	var may_delete:bool=game.selected>=0 and game.selected<game.objects.size() and (game.network_session==null or game.objects[game.selected].get("author","")==game.network_session.player_id)
	compact_delete.disabled = not may_delete
	clear_button.visible = game.draw_mode != 4
	clear_button.disabled = game.draft.is_empty() and game.pending_building.is_empty()
	action_title.visible = not compact
	action_title.text = ["", "造物", "手绘武器", "建筑结构", "移动 / 拆除", "自动塑形"][game.draw_mode] + ((" · %d 笔" % game.draft.size()) if game.draw_mode != 4 else "")
	undo_button.visible = not compact
	redo_button.visible = not compact
	delete_button.visible = game.draw_mode == 4 and not compact
	delete_button.disabled = not may_delete
	undo_button.disabled = game.undo_stack.is_empty() and game.network_session == null
	redo_button.disabled = game.redo_stack.is_empty() or game.network_session != null
	var hints := ["", "多笔绘画 · 1 确认生成 · WASD 移动 · 右键攻击", "画好按 3 → 点握点 → 3 选类型 → 3 装备", "可以反复补画多笔 · 2 确认生成 · 保留原形并真实下落", "按住已有造物拖动；选中后点拆除 / Delete", "可以画多笔 · 5 规整并生成 · Esc 返回 · WASD 移动"]
	status_label.text = game.placement_preview.get("reason", "") if not game.pending_building.is_empty() else status_text if not status_text.is_empty() else game.weapon_lab.brief if game.weapon_lab.active else hints[game.draw_mode]
	guide_panel.visible = (work or game.onboarding.visible) and not game.bag_open and not compact and not game.personal_overlay_open()
	var titles := ["画一把自己的武器", "让笔迹成为能力", "带着作品走起来", "边移动，边创造", "画出你的战术"]
	var bodies := ["按 3 画武器，2 画建筑。可以多轮补画，同时用 WASD 移动。", "武器画好后按 3，点选笔迹上的握持位置，再按 3 选择类型，最后按 3 装备；建筑再次按 2 才生成下落。", "A/D 移动，W/空格二连跳，双击 S 下平台（底层不可穿透），W/S 爬梯。右键或 R 攻击。", "试着边走边画，再开启练习场，用建筑挡住飞来的墨弹。", "细长武器够得远，宽重武器伤害高。平台、墙和梯子可以组合成你的防线。"]
	guide_title.text = titles[game.onboarding.stage]
	guide_body.text = bodies[game.onboarding.stage]
	guide_action.visible=work
	first_work_action.visible=work and compact
	first_work_skip.visible=work and compact
	guide_skip.text="跳过引导，继续自由创作" if work else "明白了，开始创作"
	if work:
		guide_title.text=game.first_work.title();guide_body.text=game.first_work.body_text();guide_action.text=game.first_work.action_text()
		first_work_action.text=["1 画","确认生成","4 搬动","保存","完成"][game.first_work.stage]
		if game.first_work.stage==1:first_work_action.text={1:"1 生成",3:"2 生成",5:"5 塑形"}.get(game.first_work.drawing_mode,"确认生成")
		if game.first_work.stage==1 and game.draw_mode!=game.first_work.drawing_mode:first_work_action.text="回到笔迹"
		if compact and status_text.is_empty():status_label.text=game.first_work.short_hint()
	_layout_actions(viewport)

func touch_button_at(point: Vector2) -> BaseButton:
	if game.weapon_type_wheel != null:
		var type_button := _touch_button(game.weapon_type_wheel, point)
		if type_button != null: return type_button
	if game.map_controls != null:
		var map_button := _touch_button(game.map_controls, point)
		if map_button != null: return map_button
	return _touch_button(self, point)

func _touch_button(node: Node, point: Vector2) -> BaseButton:
	for child in node.get_children():
		var found := _touch_button(child, point)
		if found != null: return found
	if node is BaseButton and node.is_visible_in_tree() and not node.disabled and node.get_global_rect().has_point(point): return node
	return null

func blocks_canvas(point: Vector2) -> bool:
	if game.selecting_weapon_type: return true
	if game.map_controls != null and game.map_controls.blocks_canvas(point): return true
	if game.lab_open(): return true
	if game.experience != null and game.experience.visible: return true
	if game.knowledge_world != null and game.knowledge_world.controls.blocks_canvas(point): return true
	for panel in [header, guide_panel]:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point): return true
	return _over_button(self, point)

func _over_button(node: Node, point: Vector2) -> bool:
	if node is Control and not node.is_visible_in_tree(): return false
	if node is BaseButton and node.get_global_rect().has_point(point): return true
	for child in node.get_children():
		if _over_button(child, point): return true
	return false
