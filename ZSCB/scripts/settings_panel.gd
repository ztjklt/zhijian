extends Control
const Preferences := preload("res://scripts/preferences.gd")
var game
var general_scroll: ScrollContainer
var ai_scroll: ScrollContainer
var ai
var general_tab: Button
var ai_tab: Button
var panel: PanelContainer
var volume: HSlider
var antialias: CheckButton
var sharpen: CheckButton
var save_button: Button
var close_button: Button
var status: Label
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = PaperTheme.create_menu()
	var shade := ColorRect.new()
	shade.color = Color(0.1,0.1,0.1,0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "设置"
	heading.add_theme_font_size_override("font_size", PaperTheme.menu_font_size(26))
	column.add_child(heading)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	general_tab = Button.new()
	general_tab.text = "声音与画面"
	tabs.add_child(general_tab)
	ai_tab = Button.new()
	ai_tab.text = "AI 角色"
	tabs.add_child(ai_tab)
	var group := ButtonGroup.new()
	for tab in [general_tab,ai_tab]:
		tab.toggle_mode = true
		tab.button_group = group
	tabs.visible = OS.get_name() in ["macOS","Windows","Linux","FreeBSD","NetBSD","OpenBSD"]
	general_tab.pressed.connect(func(): show_page(false))
	ai_tab.pressed.connect(func(): show_page(true))
	var scroll := ScrollContainer.new()
	general_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var audio := Label.new()
	audio.text = "总音量"
	body.add_child(audio)
	var values := Preferences.read()
	volume = HSlider.new()
	volume.min_value = 0; volume.max_value = 100; volume.step = 1
	volume.custom_minimum_size.y = 42
	volume.value = values.volume
	body.add_child(volume)
	antialias = CheckButton.new()
	antialias.text = "4× 抗锯齿"
	antialias.custom_minimum_size.y = 44
	antialias.button_pressed = values.antialias
	body.add_child(antialias)
	sharpen = CheckButton.new()
	sharpen.text = "世界轻锐化"
	sharpen.custom_minimum_size.y = 44
	sharpen.button_pressed = values.sharpen
	body.add_child(sharpen)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var help := Label.new()
	help.text = "1–5 工具 · 同键确认 · 6 图纸\nA/D 移动 · W/空格跳跃 · R 攻击\nQ 切弓 · 作品菜单保存与返回"
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		help.text = "点上方工具切换 · 画好后点生成\n左手摇杆移动 · 右侧跳跃与攻击\n图纸复用作品 · 作品菜单保存与返回"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help)
	ai_scroll = ScrollContainer.new()
	ai_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ai_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(ai_scroll)
	ai = preload("res://scripts/ai_roles_panel.gd").new()
	ai.game = game
	ai_scroll.add_child(ai)
	ai_scroll.hide()
	general_tab.set_pressed_no_signal(true)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	save_button = PaperSealButton.new()
	save_button.text = "保存连接"
	save_button.custom_minimum_size.y = 44
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(ai.save_edit)
	footer.add_child(save_button)
	save_button.hide()
	close_button = PaperSealButton.new()
	close_button.text = "完成，返回游戏" if game!=null else "完成，返回封面"
	close_button.custom_minimum_size.y = 44
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(func():
		if not ai_scroll.visible or not ai.cancel_edit(): hide())
	footer.add_child(close_button)
	ai.edit_state_changed.connect(_edit_state)
	volume.value_changed.connect(func(_value): _changed())
	antialias.toggled.connect(func(_value): _changed())
	sharpen.toggled.connect(func(_value): _changed())
	Preferences.apply(get_viewport(), values)
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide()
func _edit_state() -> void:
	var editing: bool = ai_scroll.visible and ai.editor
	save_button.visible = editing
	save_button.disabled = ai.busy
	close_button.text = "取消编辑" if editing else ("完成，返回游戏" if game!=null else "完成，返回封面")

func show_page(roles: bool) -> void:
	if not roles:
		ai.leave_page()
	general_scroll.visible = not roles
	ai_scroll.visible = roles
	general_tab.set_pressed_no_signal(not roles)
	ai_tab.set_pressed_no_signal(roles)
	if roles:
		ai_scroll.scroll_vertical = 0
		ai.open_page()
	_layout()

func _on_visibility() -> void:
	if not visible:
		show_page(false)

func _changed() -> void:
	var values := {"volume":volume.value,"antialias":antialias.button_pressed,"sharpen":sharpen.button_pressed}
	Preferences.apply(get_viewport(), values)
	var error := Preferences.save(values)
	status.text = "音量 %d%% · 立即生效，已保存" % volume.value if error == OK else "设置保存失败，当前窗口仍已应用"
func _layout() -> void:
	PaperGuiScale.apply(self)
	panel.reset_size()
	PaperGuiScale.fit_panel(panel, Vector2(736,670) if ai_scroll.visible else Vector2(480,510))
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		if not ai_scroll.visible or not ai.cancel_edit(): hide()
		get_viewport().set_input_as_handled()
