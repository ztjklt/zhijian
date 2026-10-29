extends Control
const Preferences := preload("res://scripts/preferences.gd")
var panel: PanelContainer
var volume: HSlider
var antialias: CheckButton
var sharpen: CheckButton
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
	var scroll := ScrollContainer.new()
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
	antialias.button_pressed = values.antialias
	body.add_child(antialias)
	sharpen = CheckButton.new()
	sharpen.text = "世界轻锐化"
	sharpen.button_pressed = values.sharpen
	body.add_child(sharpen)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	var help := Label.new()
	help.text = "1–5 工具 · 同键确认 · 6 图纸\nA/D 移动 · W/空格跳跃 · R 攻击\nQ 切弓 · 作品菜单保存与返回"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help)
	close_button = Button.new()
	close_button.text = "完成，返回封面"
	close_button.custom_minimum_size.y = 44
	close_button.pressed.connect(func(): hide())
	column.add_child(close_button)
	volume.value_changed.connect(func(_value): _changed())
	antialias.toggled.connect(func(_value): _changed())
	sharpen.toggled.connect(func(_value): _changed())
	Preferences.apply(get_viewport(), values)
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide()
func _changed() -> void:
	var values := {"volume":volume.value,"antialias":antialias.button_pressed,"sharpen":sharpen.button_pressed}
	Preferences.apply(get_viewport(), values)
	var error := Preferences.save(values)
	status.text = "音量 %d%% · 立即生效，已保存" % volume.value if error == OK else "设置保存失败，当前窗口仍已应用"
func _layout() -> void:
	var viewport := get_viewport_rect().size
	panel.reset_size()
	panel.size = Vector2(minf(480, viewport.x - 24), minf(470, viewport.y - 24))
	panel.position = (viewport - panel.size) * 0.5
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		hide()
		get_viewport().set_input_as_handled()
