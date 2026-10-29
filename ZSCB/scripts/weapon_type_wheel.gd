class_name PaperWeaponTypeWheel
extends Control
## A non-pausing radial choice: mouse hover/touch selects, 3 confirms equipment.
var game = null
var buttons: Array[Button] = []
var title: Label
var description: Label
var confirm: Button
var panel: PanelContainer
func _ready() -> void:
	theme = PaperTheme.create()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel",PaperTheme.scrap())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var center := VBoxContainer.new()
	panel.add_child(center)
	title = Label.new(); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "武器类型"; center.add_child(title)
	description = Label.new(); description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size",13)
	center.add_child(description)
	confirm = Button.new(); confirm.text = "3 确认装备"; confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(func(): game.generate())
	center.add_child(confirm)
	for id in PaperWeaponTypes.IDS:
		var button := Button.new()
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
	var viewport := PaperGuiScale.apply(self)
	var radius := Vector2(minf(155,viewport.x*.39),minf(130,viewport.y*.31))
	var center := viewport * Vector2(.5,.53)
	panel.size = Vector2(188,100)
	panel.position = center - panel.size*.5
	var selected: String = game.selected_weapon_type
	title.text = "选择类型 · " + PaperWeaponTypes.LABELS[selected]
	description.text = PaperWeaponTypes.HINTS[selected]
	for i in buttons.size():
		var button := buttons[i]
		button.size = Vector2(90,46)
		button.position = center + Vector2.from_angle(-PI*.5+TAU*i/buttons.size())*radius - button.size*.5
		PaperTheme.selected(button,PaperWeaponTypes.IDS[i]==selected)
	queue_redraw()
func _draw() -> void:
	if not visible: return
	var center := PaperGuiScale.logical_size(self) * Vector2(.5,.53)
	for button in buttons:
		draw_line(center,button.position+button.size*.5,Color(.20,.36,.34,.35),2,true)
