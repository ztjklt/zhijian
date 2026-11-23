class_name PaperWeaponTypeWheel
extends Control
## A non-pausing radial choice: mouse hover/touch selects, 3 confirms equipment.
var game = null
var buttons: Array[Button] = []
var title: Label
var description: Label
var confirm: Button
var panel: PanelContainer
var center_stack: VBoxContainer
var cancel: Button
func _ready() -> void:
	theme = PaperTheme.create()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",PaperTheme.scrap())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var center := VBoxContainer.new()
	center_stack = center
	panel.add_child(center)
	title = Label.new(); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "武器类型"; center.add_child(title)
	description = Label.new(); description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size",13)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(description)
	confirm = PaperSealButton.new(); confirm.text = "3 确认装备"; confirm.focus_mode = Control.FOCUS_NONE
	confirm.custom_minimum_size.y = 44
	confirm.pressed.connect(func(): game.generate())
	center.add_child(confirm)
	cancel = PaperSealButton.new(); cancel.text = "返回绘画"; cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size.y = 44
	cancel.pressed.connect(func(): game.cancel_weapon_grip())
	add_child(cancel); cancel.hide()
	for id in PaperWeaponTypes.IDS:
		var button := PaperSealButton.new()
		button.text = PaperWeaponTypes.LABELS[id]
		button.tooltip_text = PaperWeaponTypes.HINTS[id]
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_entered.connect(func(): game.select_weapon_type(id))
		button.pressed.connect(func(): game.select_weapon_type(id))
		add_child(button); buttons.append(button)
	visible = false
func _process(_delta: float) -> void:
	if game == null: return
	visible = game.selecting_weapon_type and not game.bag_open and (game.experience==null or not game.experience.visible)
	if not visible: return
	confirm.text = "装备" if game.touch_controls != null and game.touch_controls.enabled() else "3 确认装备"
	var viewport := PaperGuiScale.apply(self)
	var bounds := PaperGuiScale.safe_rect(self).grow(-12)
	var radius := Vector2(minf(155,viewport.x*.39),minf(130,viewport.y*.31))
	var center := bounds.position + bounds.size * Vector2(.5,.53)
	var selected: String = game.selected_weapon_type
	title.text = "选择类型 · " + PaperWeaponTypes.LABELS[selected]
	description.text = PaperWeaponTypes.HINTS[selected]
	if bounds.size.x < 600 or viewport.y < 500:
		cancel.show()
		if confirm.get_parent() != self: confirm.reparent(self)
		var columns := 5 if bounds.size.x >= 520 else 2
		var width := minf(420, bounds.size.x)
		var button_width := (width - (columns-1)*8) / columns
		var option_height := ceili(5.0 / columns)*52
		var total_height := 132.0 + option_height
		panel.size = Vector2(width, 80)
		panel.position = Vector2(bounds.get_center().x-width*0.5, bounds.get_center().y-total_height*0.5)
		for i in buttons.size():
			buttons[i].size = Vector2(button_width, 44)
			buttons[i].position = panel.position + Vector2((i % columns)*(button_width+8), 88 + (i / columns)*52)
			PaperTheme.selected(buttons[i], PaperWeaponTypes.IDS[i]==selected)
		cancel.size = Vector2(100,44)
		cancel.position = panel.position + Vector2(0,88+option_height)
		confirm.size = Vector2(width-108, 44)
		confirm.position = cancel.position + Vector2(108, 0)
		PaperTheme.primary(confirm)
		queue_redraw()
		return
	cancel.hide()
	if confirm.get_parent() != center_stack: confirm.reparent(center_stack)
	panel.size = Vector2(188,100)
	panel.position = center - panel.size*.5
	for i in buttons.size():
		var button := buttons[i]
		button.size = Vector2(90,46)
		button.position = center + Vector2.from_angle(-PI*.5+TAU*i/buttons.size())*radius - button.size*.5
		PaperTheme.selected(button,PaperWeaponTypes.IDS[i]==selected)
	queue_redraw()
func _draw() -> void:
	if not visible: return
	var viewport := PaperGuiScale.logical_size(self)
	if viewport.x < 624 or viewport.y < 500: return
	var center := PaperGuiScale.logical_size(self) * Vector2(.5,.53)
	for button in buttons:
		draw_line(center,button.position+button.size*.5,Color(.20,.36,.34,.35),2,true)
