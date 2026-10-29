extends Control

var game = null
var panel: PanelContainer
var navigation: HBoxContainer
var regions: OptionButton
var trial_row: HBoxContainer
var menu_button: Button
var heading: Label
var trial_entry: Button
var trial_button: Button
var trial_note: Label
var last_trial_phase := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = PaperTheme.create()
	panel = PanelContainer.new()
	var style := PaperTheme.panel()
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	heading = Label.new()
	heading.text = "墨线边境 · 黑线画出的中世纪"
	heading.add_theme_font_size_override("font_size", 12)
	column.add_child(heading)
	navigation = HBoxContainer.new()
	column.add_child(navigation)
	regions = OptionButton.new()
	regions.focus_mode = Control.FOCUS_NONE
	for section in MedievalWorld.SECTIONS: regions.add_item(section.name)
	regions.item_selected.connect(visit)
	navigation.add_child(regions)
	trial_row = HBoxContainer.new()
	column.add_child(trial_row)
	menu_button = _button(navigation, "选择地图", func(): game.return_to_map_select())
	trial_entry = _button(trial_row,"磨坊试桥",visit_trial)
	trial_button = _button(trial_row,"布置试桥台",func():
		if game.medieval_world != null: game.bridge_trial_action("prepare" if game.medieval_world.bridge_trial.phase == "idle" else "start"))
	trial_note = Label.new()
	trial_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trial_note.custom_minimum_size.x = 260
	trial_note.add_theme_font_size_override("font_size",13)
	trial_note.add_theme_color_override("font_color",PaperTheme.INK)
	column.add_child(trial_note)
	refresh()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(72, 29)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func refresh() -> void:
	if panel == null: return
	var medieval: bool = game.medieval_world != null
	regions.visible = medieval
	trial_row.visible = medieval
	heading.visible = medieval

func _process(_delta: float) -> void:
	if game == null: return
	var size := PaperGuiScale.apply(self)
	var compact := size.x < 600 or size.y < 500
	var medieval: bool = game.medieval_world != null
	var near: bool = medieval and game.player.position.distance_to(Vector2(133.5,5.2)) <= 12
	var side_event: bool = compact and size.y < 500 and not game.toolbar.navigation_open
	trial_note.custom_minimum_size.x = 190 if side_event else 260
	heading.visible = medieval and game.toolbar.navigation_open and not compact
	navigation.visible = game.toolbar.navigation_open
	trial_row.visible = medieval and (game.toolbar.navigation_open or near)
	trial_note.visible = trial_row.visible
	panel.visible = (game.toolbar.navigation_open or near) and not game.bag_open and not game.onboarding.visible and not (game.experience != null and game.experience.visible)
	if medieval:
		var trial = game.medieval_world.bridge_trial
		trial_button.disabled = not near or trial.phase == "running"
		trial_button.text = {"idle":"布置试桥台","ready":"投放货物","running":"正在运输…","failed":"重新投放","delivered":"换种搭法再试"}.get(trial.phase,"投放货物")
		trial_note.text = {"idle":"可选 · 磨坊试桥：布置两端，画一座能承重的桥。","ready":"桥板、斜坡或组合支撑都可以。画好后投放小货车。","running":"货物运输中 · 桥有些不稳？可以继续补画加固。","failed":"货物掉下来了 · 搭建都还在，补好再试。","delivered":"送达！你的桥承住了货物 · 也可以换种搭法再试。"}.get(trial.phase,"")
		if not near: trial_note.text = "可选 · 磨坊试桥，位于磨坊渡口。前往后可布置和投放货物。"
		if last_trial_phase != "" and last_trial_phase != trial.phase and near:
			if trial.phase == "delivered": game.message("送达！这座手绘桥真正承住了货物")
			elif trial.phase == "failed": game.message("货物掉下来了 · 搭建保留，可以补好再试")
		last_trial_phase = trial.phase
	if game.medieval_world != null:
		var top: float = (game.toolbar.header.get_global_rect().end.y / scale.y) + 10
		if compact and not side_event: top = maxf(top,game.toolbar.bottom.get_global_rect().end.y / scale.y + (8 if size.y < 500 else 40))
		panel.position = Vector2(12 if compact else 20,top)
	else:
		panel.position = Vector2(maxf(12, size.x - panel.size.x - 16), game.toolbar.header.position.y + game.toolbar.header.size.y + 10)
	panel.reset_size()
	if compact and size.y < 500 and not side_event:
		panel.position.x = maxf(12,(size.x-panel.size.x)*.5)
	PaperGuiScale.popup(regions.get_popup(), scale.x)

func visit_trial() -> void:
	if game.network_session != null:
		game.message("磨坊试桥在磨坊渡口，沿路走到约129米处；联机不会直接传送")
		return
	visit(6)
	game.toolbar.navigation_open = false
	game.message("来到磨坊试桥 · 先布置试桥台，再画桥、投放货物")

func visit(index: int) -> void:
	if game.network_session != null:
		game.message("联机请与朋友一起走过去；Home 可返回地面")
		return
	if game.medieval_world == null or index < 0 or index >= MedievalWorld.SECTIONS.size(): return
	# Navigation never commits, discards or silently moves unfinished ink.
	game.retain_active_stroke()
	game.cancel_pointer()
	if game.touch_controls != null: game.touch_controls.reset()
	game.player.reset_movement()
	game.player.position = game.medieval_world.safe_spawn_position(float(MedievalWorld.SECTIONS[index].x))
	game.player.linear_velocity = Vector2.ZERO
	PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, game.player.position))
	game.camera_x = game.player.position.x
	game.camera_y = game.camera_target_y()
	game.combat.cancel_draw()
	game._update_world_chunks()
	game.message("来到" + MedievalWorld.SECTIONS[index].name + " · 房屋、村民和城堡都可受击")

func blocks_canvas(point: Vector2) -> bool:
	return panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(point)

func _unhandled_key_input(event: InputEvent) -> void:
	if game==null or game.medieval_world==null or not event is InputEventKey or not event.pressed or event.echo: return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or game.bag_open or game.personal_overlay_open(): return
	if event.keycode==KEY_HOME:
		game.respawn_medieval()
		get_viewport().set_input_as_handled()
