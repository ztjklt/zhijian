extends Control
const Flow:=preload("res://scripts/net/online_flow.gd")
signal confirmed
signal canceled
var title:=""
var dialog_text:=""
var panel:PanelContainer
var content:VBoxContainer
var label:Label
var heading:Label
var scroll:ScrollContainer
var ok:Button
var cancel:Button
var cancel_visible:=true
var desired_width:=520.0
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.25);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	panel=PanelContainer.new();panel.theme=PaperTheme.create_menu();panel.add_theme_stylebox_override("panel",PaperTheme.panel());add_child(panel)
	var margin:=MarginContainer.new()
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,18)
	panel.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);margin.add_child(column)
	heading=Label.new();heading.add_theme_font_size_override("font_size",PaperTheme.menu_font_size(22));heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(heading)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	content=VBoxContainer.new();content.add_theme_constant_override("separation",12);content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	label=Label.new();label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",PaperTheme.menu_font_size(16));content.add_child(label)
	var buttons:=VBoxContainer.new();buttons.add_theme_constant_override("separation",8);column.add_child(buttons)
	ok=Button.new();ok.text="确定";ok.custom_minimum_size.y=44;PaperTheme.primary(ok);buttons.add_child(ok)
	cancel=Button.new();cancel.text="取消";cancel.custom_minimum_size.y=44;buttons.add_child(cancel)
	ok.pressed.connect(func():hide();confirmed.emit())
	cancel.pressed.connect(func():hide();canceled.emit())
	hide()
func get_ok_button()->Button:return ok
func get_cancel_button()->Button:return cancel
func get_label()->Label:return label
func popup_centered(dimensions:Vector2i)->void:
	desired_width=dimensions.x;heading.text=title;label.text=dialog_text;label.visible=not dialog_text.is_empty();cancel.visible=cancel_visible
	show();_layout()
func _process(_delta:float)->void:
	if visible:_layout()
func _layout()->void:
	var viewport:=get_viewport_rect().size
	var amount:=Flow.ui_scale(viewport)
	var logical:=viewport/amount
	var width:=minf(desired_width,logical.x-32)
	content.custom_minimum_size.x=maxf(180,width-44)
	scroll.custom_minimum_size.y=minf(content.get_combined_minimum_size().y,maxf(70,logical.y-230))
	panel.scale=Vector2(amount,amount);panel.size=Vector2(width,0);panel.reset_size()
	panel.position=(viewport-panel.size*amount)*.5
func _input(event:InputEvent)->void:
	if visible and event.is_action_pressed("cancel"):
		hide();canceled.emit();get_viewport().set_input_as_handled()
